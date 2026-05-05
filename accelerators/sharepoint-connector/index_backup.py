"""
Nightly backup of the AI Search index + connector state.

Writes to a dedicated `backup` blob container under a dated folder:

    backup/
      2026-04-23/
        index-schema.json        # SearchIndex definition (fields, vector
                                 # search, semantic config, vectorizers)
        documents.jsonl          # All indexed chunks (one JSON object/line,
                                 # vector fields stripped to keep size down)
        watermarks.jsonl         # Per-drive watermark + delta tokens
        failed-files.jsonl       # Terminal / in-progress failures
      2026-04-22/
      …

Retention is enforced by deleting folders older than BACKUP_RETENTION_DAYS.

The backup is *recoverable enough to rebuild the index shape and know which
parents existed*. Vectors are NOT persisted (they'd inflate the export by
~4 KB/chunk for no DR value — a restore re-ingests from SharePoint, which
regenerates vectors anyway). Use the backup to:

  1. Quickly re-create the index schema after accidental deletion.
  2. Replay the per-drive delta tokens to resume incremental ingestion
     without a full reindex.
  3. Audit what was indexed and when.
"""

from __future__ import annotations

import hashlib
import json
import logging
import os
import time
from dataclasses import dataclass
from datetime import datetime, timedelta, timezone
from io import BytesIO
from typing import Any

from azure.core.exceptions import HttpResponseError, ResourceExistsError
from azure.data.tables import TableClient, TableServiceClient
from azure.identity import DefaultAzureCredential
from azure.search.documents import SearchClient
from azure.search.documents.indexes import SearchIndexClient
from azure.storage.blob import BlobServiceClient, ContentSettings

from config import AppConfig

logger = logging.getLogger(__name__)

_DEFAULT_CONTAINER = os.getenv("BACKUP_CONTAINER", "backup")
_DEFAULT_RETENTION_DAYS = int(os.getenv("BACKUP_RETENTION_DAYS", "7"))
_DEFAULT_DOC_PAGE_SIZE = 500


@dataclass
class BackupResult:
    folder: str
    schema_bytes: int
    docs_count: int
    watermarks_count: int
    failed_files_count: int
    duration_s: float

    def summary(self) -> str:
        return (
            f"Backup {self.folder}: schema={self.schema_bytes}B, "
            f"docs={self.docs_count}, watermarks={self.watermarks_count}, "
            f"failed-files={self.failed_files_count}, took {self.duration_s:.1f}s"
        )


class IndexBackup:
    """Exports index + state to blob under a dated folder."""

    def __init__(self, cfg: AppConfig):
        self._cfg = cfg
        self._credential = DefaultAzureCredential()

        storage_account = os.getenv("AzureWebJobsStorage__accountName")
        if not storage_account:
            raise EnvironmentError("AzureWebJobsStorage__accountName must be set")

        self._blob_svc = BlobServiceClient(
            account_url=f"https://{storage_account}.blob.core.windows.net",
            credential=self._credential,
        )
        self._container = self._blob_svc.get_container_client(_DEFAULT_CONTAINER)
        try:
            self._container.create_container()
        except ResourceExistsError:
            pass

        self._index_client = SearchIndexClient(endpoint=cfg.search.endpoint, credential=self._credential)
        self._search_client = SearchClient(
            endpoint=cfg.search.endpoint,
            index_name=cfg.search.index_name,
            credential=self._credential,
        )
        self._table_svc = TableServiceClient(
            endpoint=f"https://{storage_account}.table.core.windows.net",
            credential=self._credential,
        )

    # ------------------------------------------------------------------ #

    def run(self) -> BackupResult:
        started = time.monotonic()
        folder = datetime.now(timezone.utc).strftime("%Y-%m-%d")

        schema_bytes = self._export_schema(folder)
        docs_count = self._export_documents(folder)
        watermarks_count = self._export_table(folder, os.getenv("WATERMARK_TABLE", "watermark"), "watermarks.jsonl")
        failed_count = self._export_table(folder, os.getenv("FAILED_FILES_TABLE", "failedFiles"), "failed-files.jsonl")

        self._apply_retention()

        result = BackupResult(
            folder=folder,
            schema_bytes=schema_bytes,
            docs_count=docs_count,
            watermarks_count=watermarks_count,
            failed_files_count=failed_count,
            duration_s=time.monotonic() - started,
        )
        logger.info(result.summary())
        return result

    # ------------------------------------------------------------------ #

    def _export_schema(self, folder: str) -> int:
        name = self._cfg.search.index_name
        try:
            index = self._index_client.get_index(name)
        except HttpResponseError as e:
            logger.warning(f"Could not fetch index '{name}' schema: {e.message}")
            return 0
        # SDK models support .as_dict() → JSON-serialisable shape.
        schema_payload = index.as_dict() if hasattr(index, "as_dict") else {"name": name}
        body = json.dumps(schema_payload, indent=2).encode("utf-8")
        self._upload(folder, "index-schema.json", body, "application/json")
        return len(body)

    def _export_documents(self, folder: str) -> int:
        """Walk the whole index in pages, write as JSONL. Vector fields stripped."""
        blob_name = f"{folder}/documents.jsonl"
        blob = self._container.get_blob_client(blob_name)
        buffer = BytesIO()
        count = 0

        try:
            skip = 0
            while True:
                results = list(self._search_client.search(
                    search_text="*",
                    include_total_count=False,
                    top=_DEFAULT_DOC_PAGE_SIZE,
                    skip=skip,
                ))
                if not results:
                    break
                for doc in results:
                    # Strip the vector field — it's reproducible from re-ingestion
                    # and bloats the backup by ~4 KB per chunk.
                    doc.pop("content_embedding", None)
                    doc.pop("@search.score", None)
                    doc.pop("@search.reranker_score", None)
                    buffer.write(json.dumps(doc, default=str).encode("utf-8"))
                    buffer.write(b"\n")
                    count += 1
                skip += _DEFAULT_DOC_PAGE_SIZE
                if len(results) < _DEFAULT_DOC_PAGE_SIZE:
                    break
        except Exception as e:  # noqa: BLE001
            logger.warning(f"Document export stopped early at {count}: {e}")

        if count > 0:
            blob.upload_blob(
                buffer.getvalue(),
                overwrite=True,
                content_settings=ContentSettings(content_type="application/x-ndjson"),
            )
        return count

    def _export_table(self, folder: str, table_name: str, output_name: str) -> int:
        try:
            tbl: TableClient = self._table_svc.get_table_client(table_name)
            entities = list(tbl.list_entities())
        except Exception as e:  # noqa: BLE001
            logger.warning(f"Could not export table '{table_name}': {e}")
            return 0

        buffer = BytesIO()
        for e in entities:
            buffer.write(json.dumps(dict(e), default=str).encode("utf-8"))
            buffer.write(b"\n")

        if entities:
            self._upload(folder, output_name, buffer.getvalue(), "application/x-ndjson")
        return len(entities)

    def _upload(self, folder: str, name: str, body: bytes, content_type: str) -> None:
        blob_name = f"{folder}/{name}"
        blob = self._container.get_blob_client(blob_name)
        blob.upload_blob(
            body,
            overwrite=True,
            content_settings=ContentSettings(content_type=content_type),
        )

    def _apply_retention(self) -> None:
        """Delete backup folders older than BACKUP_RETENTION_DAYS."""
        keep_after = datetime.now(timezone.utc) - timedelta(days=_DEFAULT_RETENTION_DAYS)
        seen_dates: set[str] = set()
        try:
            for blob in self._container.list_blobs():
                date_segment = blob.name.split("/", 1)[0]
                if date_segment in seen_dates:
                    continue
                seen_dates.add(date_segment)
                try:
                    folder_dt = datetime.strptime(date_segment, "%Y-%m-%d").replace(tzinfo=timezone.utc)
                except ValueError:
                    continue
                if folder_dt < keep_after:
                    self._delete_folder(date_segment)
        except Exception as e:  # noqa: BLE001
            logger.warning(f"Retention pass encountered an error: {e}")

    def _delete_folder(self, prefix: str) -> None:
        deleted = 0
        for blob in self._container.list_blobs(name_starts_with=f"{prefix}/"):
            try:
                self._container.delete_blob(blob.name)
                deleted += 1
            except Exception as e:  # noqa: BLE001
                logger.debug(f"Could not delete {blob.name}: {e}")
        if deleted:
            logger.info(f"Retention: deleted {deleted} blob(s) under {prefix}/")
