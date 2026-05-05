"""
State store backed by Azure Storage (Tables + Queue).

Tracks:
  - Per-drive watermarks (last successful run timestamp)
  - Per-file failure counters (for poison-queue handling)
  - Per-run progress (for "run complete" finalisation)

All access via managed identity (DefaultAzureCredential).
"""

from __future__ import annotations

import json
import logging
import os
from dataclasses import dataclass
from datetime import datetime, timezone
from typing import Any

from azure.core.exceptions import ResourceExistsError, ResourceNotFoundError
from azure.data.tables import TableClient, TableServiceClient, UpdateMode
from azure.identity import DefaultAzureCredential
from azure.storage.queue import QueueClient

logger = logging.getLogger(__name__)


# Table / blob name env overrides (match Bicep outputs)
_WATERMARK_TABLE = os.getenv("WATERMARK_TABLE", "watermark")
_FAILED_FILES_TABLE = os.getenv("FAILED_FILES_TABLE", "failedFiles")
_RUN_STATE_TABLE = os.getenv("RUN_STATE_TABLE", "runState")
_INDEXER_QUEUE = os.getenv("INDEXER_QUEUE_NAME", "sp-indexer-q")

_PARTITION = "sp-connector"


@dataclass
class RunProgress:
    run_id: str
    expected: int
    completed: int
    failed: int
    started_at: str
    completed_at: str | None


class StateStore:
    """Facade over Table Storage + Queue Storage for connector state."""

    def __init__(self, account_url: str | None = None, queue_url: str | None = None):
        # account_url example: https://spindexer st.table.core.windows.net
        storage_account = os.getenv("AzureWebJobsStorage__accountName")
        if not storage_account:
            raise EnvironmentError("AzureWebJobsStorage__accountName must be set to use StateStore")

        self._credential = DefaultAzureCredential()
        self._table_endpoint = account_url or f"https://{storage_account}.table.core.windows.net"
        self._queue_endpoint = queue_url or f"https://{storage_account}.queue.core.windows.net"

        self._svc = TableServiceClient(endpoint=self._table_endpoint, credential=self._credential)

    # ------------------------------------------------------------------ #
    # Table helpers
    # ------------------------------------------------------------------ #

    def _table(self, name: str) -> TableClient:
        client = self._svc.get_table_client(name)
        try:
            client.create_table()
        except ResourceExistsError:
            pass
        return client

    # ------------------------------------------------------------------ #
    # Watermark: per-drive last-successful-run timestamp
    # ------------------------------------------------------------------ #

    def read_watermark(self, drive_id: str = "global") -> datetime | None:
        """Return the last successful-run timestamp for a drive, or None if not set."""
        tbl = self._table(_WATERMARK_TABLE)
        try:
            entity = tbl.get_entity(partition_key=_PARTITION, row_key=drive_id)
        except ResourceNotFoundError:
            return None
        ts = entity.get("watermark_iso")
        if not ts:
            return None
        return datetime.fromisoformat(str(ts).replace("Z", "+00:00"))

    def write_watermark(self, ts: datetime, drive_id: str = "global") -> None:
        """Persist the watermark (UTC)."""
        if ts.tzinfo is None:
            ts = ts.replace(tzinfo=timezone.utc)
        tbl = self._table(_WATERMARK_TABLE)
        tbl.upsert_entity(
            entity={
                "PartitionKey": _PARTITION,
                "RowKey": drive_id,
                "watermark_iso": ts.isoformat(),
            },
            mode=UpdateMode.REPLACE,
        )
        logger.info(f"Watermark for drive '{drive_id}' = {ts.isoformat()}")

    # ------------------------------------------------------------------ #
    # Delta tokens: per-drive cursor for Graph `/delta` incremental queries.
    # Separate from the watermark table so the two state types can be cleared
    # independently (e.g. resetting delta without losing the human-readable
    # "last successful run" timestamp).
    # ------------------------------------------------------------------ #

    def read_delta_tokens(self) -> dict[str, str]:
        """Return the delta token for every drive we have state for."""
        tbl = self._table(_WATERMARK_TABLE)
        tokens: dict[str, str] = {}
        try:
            for entity in tbl.list_entities(filter=f"PartitionKey eq 'delta-{_PARTITION}'"):
                drive_id = str(entity.get("RowKey", ""))
                token = str(entity.get("delta_token", ""))
                if drive_id and token:
                    tokens[drive_id] = token
        except Exception as e:  # noqa: BLE001
            logger.warning(f"Could not read delta tokens: {e}")
        return tokens

    def write_delta_tokens(self, tokens: dict[str, str]) -> None:
        """Replace delta tokens for the provided drives."""
        tbl = self._table(_WATERMARK_TABLE)
        for drive_id, token in tokens.items():
            tbl.upsert_entity(
                entity={
                    "PartitionKey": f"delta-{_PARTITION}",
                    "RowKey": drive_id,
                    "delta_token": token,
                },
                mode=UpdateMode.REPLACE,
            )
        if tokens:
            logger.info(f"Persisted delta tokens for {len(tokens)} drive(s)")

    # ------------------------------------------------------------------ #
    # Run counter — how many times the dispatcher has fired since deployment.
    # Used to decide when to run a periodic full reconciliation.
    # ------------------------------------------------------------------ #

    def increment_run_counter(self, scope: str = "global") -> int:
        tbl = self._table(_RUN_STATE_TABLE)
        row_key = f"counter-{scope}"
        for _ in range(5):
            try:
                entity = tbl.get_entity(partition_key=_PARTITION, row_key=row_key)
                entity["count"] = int(entity.get("count", 0)) + 1
            except ResourceNotFoundError:
                entity = {
                    "PartitionKey": _PARTITION,
                    "RowKey": row_key,
                    "count": 1,
                }
            try:
                tbl.upsert_entity(entity=entity, mode=UpdateMode.REPLACE)
                return int(entity["count"])
            except Exception as e:  # noqa: BLE001
                logger.debug(f"Run-counter retry: {e}")
        return 0

    # ------------------------------------------------------------------ #
    # Failed files: per-file retry counter
    # ------------------------------------------------------------------ #

    def record_failed_file(self, file_id: str, error: str, terminal: bool = False) -> int:
        """Increment the failure counter for a file. Returns the new count."""
        tbl = self._table(_FAILED_FILES_TABLE)
        try:
            entity = tbl.get_entity(partition_key=_PARTITION, row_key=file_id)
            count = int(entity.get("failure_count", 0)) + 1
        except ResourceNotFoundError:
            count = 1
        tbl.upsert_entity(
            entity={
                "PartitionKey": _PARTITION,
                "RowKey": file_id,
                "failure_count": count,
                "last_error": error[:32000],  # Table string cap
                "last_seen_iso": datetime.now(timezone.utc).isoformat(),
                "terminal": terminal,
            },
            mode=UpdateMode.REPLACE,
        )
        return count

    def get_failure_count(self, file_id: str) -> int:
        tbl = self._table(_FAILED_FILES_TABLE)
        try:
            entity = tbl.get_entity(partition_key=_PARTITION, row_key=file_id)
            return int(entity.get("failure_count", 0))
        except ResourceNotFoundError:
            return 0

    def clear_failed_file(self, file_id: str) -> None:
        """Reset the failure counter after a successful processing."""
        tbl = self._table(_FAILED_FILES_TABLE)
        try:
            tbl.delete_entity(partition_key=_PARTITION, row_key=file_id)
        except ResourceNotFoundError:
            pass

    # ------------------------------------------------------------------ #
    # Run state: coordinate queue-mode completion
    # ------------------------------------------------------------------ #

    def record_run_start(self, run_id: str, expected: int) -> None:
        tbl = self._table(_RUN_STATE_TABLE)
        tbl.upsert_entity(
            entity={
                "PartitionKey": _PARTITION,
                "RowKey": run_id,
                "expected": expected,
                "completed": 0,
                "failed": 0,
                "started_at": datetime.now(timezone.utc).isoformat(),
                "completed_at": "",
            },
            mode=UpdateMode.REPLACE,
        )

    def record_run_progress(self, run_id: str, completed_delta: int = 0, failed_delta: int = 0) -> RunProgress:
        """Atomically bump completion/failure counters. Returns current progress."""
        tbl = self._table(_RUN_STATE_TABLE)
        # Simple optimistic concurrency with retries
        for _ in range(5):
            try:
                entity = tbl.get_entity(partition_key=_PARTITION, row_key=run_id)
            except ResourceNotFoundError:
                # Unknown run (possibly from legacy code path). Create it.
                tbl.upsert_entity(
                    entity={
                        "PartitionKey": _PARTITION,
                        "RowKey": run_id,
                        "expected": 0,
                        "completed": completed_delta,
                        "failed": failed_delta,
                        "started_at": datetime.now(timezone.utc).isoformat(),
                        "completed_at": "",
                    },
                    mode=UpdateMode.REPLACE,
                )
                return RunProgress(run_id, 0, completed_delta, failed_delta,
                                   datetime.now(timezone.utc).isoformat(), None)
            entity["completed"] = int(entity.get("completed", 0)) + completed_delta
            entity["failed"] = int(entity.get("failed", 0)) + failed_delta
            try:
                tbl.update_entity(entity=entity, mode=UpdateMode.REPLACE)
                return RunProgress(
                    run_id=run_id,
                    expected=int(entity.get("expected", 0)),
                    completed=int(entity["completed"]),
                    failed=int(entity["failed"]),
                    started_at=str(entity.get("started_at", "")),
                    completed_at=str(entity.get("completed_at") or "") or None,
                )
            except Exception as e:  # noqa: BLE001
                logger.debug(f"Run progress update retry: {e}")
        raise RuntimeError(f"Could not update run_state for {run_id}")

    def mark_run_completed(self, run_id: str) -> None:
        tbl = self._table(_RUN_STATE_TABLE)
        try:
            entity = tbl.get_entity(partition_key=_PARTITION, row_key=run_id)
        except ResourceNotFoundError:
            return
        entity["completed_at"] = datetime.now(timezone.utc).isoformat()
        tbl.update_entity(entity=entity, mode=UpdateMode.REPLACE)

    # ------------------------------------------------------------------ #
    # Queue helpers
    # ------------------------------------------------------------------ #

    def enqueue(self, payload: dict[str, Any], queue_name: str | None = None) -> None:
        """Enqueue a JSON-encoded message."""
        name = queue_name or _INDEXER_QUEUE
        client = QueueClient(account_url=self._queue_endpoint, queue_name=name, credential=self._credential)
        try:
            client.create_queue()
        except ResourceExistsError:
            pass
        client.send_message(json.dumps(payload))


# ------------------------------------------------------------------ #
# Module-level singleton for convenience
# ------------------------------------------------------------------ #

_store: StateStore | None = None


def get_store() -> StateStore:
    global _store
    if _store is None:
        _store = StateStore()
    return _store
