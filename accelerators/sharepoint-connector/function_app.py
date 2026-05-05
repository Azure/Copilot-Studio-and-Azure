"""
Azure Function entry points.

Two processing modes, selected via the FUNCTION_PROCESSING_MODE env var:

  queue   (default, scalable)
    - sp_dispatcher       : timer-triggered. Lists changed files and enqueues one
                            message per file.
    - sp_worker           : queue-triggered. Downloads + processes a single file.
                            Runs in parallel across many function instances.
    - sp_poison_handler   : queue-triggered on the poison queue. Records terminal
                            failures for human investigation.

  inline  (legacy)
    - sp_indexer_timer    : the original single-function timer that does
                            everything in one invocation. Good for small sites.

Switch modes via the Bicep `functionProcessingMode` parameter or the
`FUNCTION_PROCESSING_MODE` app setting.
"""

from __future__ import annotations

import json
import logging
import os
import uuid

import azure.functions as func

app = func.FunctionApp()

SCHEDULE = "%INDEXER_SCHEDULE%"                    # default: "0 0 * * * *"
BACKUP_SCHEDULE = "%BACKUP_SCHEDULE%"              # default: "0 0 3 * * *" (03:00 UTC daily)
INDEXER_QUEUE = os.getenv("INDEXER_QUEUE_NAME", "sp-indexer-q")
POISON_QUEUE = f"{INDEXER_QUEUE}-poison"
PROCESSING_FLAG = os.getenv("FUNCTION_PROCESSING_MODE", "queue").strip().lower()
MAX_FAILURES = 5

# Search endpoint (query-time) — lazy-initialised singletons so a single
# Function instance reuses JWKS/HTTPX clients across HTTP invocations.
_identity_resolver = None
_search_client_singleton = None


# ---------------------------------------------------------------------------
# Legacy inline mode
# ---------------------------------------------------------------------------

@app.timer_trigger(schedule=SCHEDULE, arg_name="timer", run_on_startup=False)
def sp_indexer_timer(timer: func.TimerRequest) -> None:
    """Single-function timer (inline mode) OR dispatcher (queue mode)."""
    if timer.past_due:
        logging.warning("Timer is past due — running anyway")

    if PROCESSING_FLAG == "inline":
        logging.info("SharePoint indexer triggered (inline mode)")
        try:
            from indexer import run_indexer
            stats = run_indexer()
            logging.info(stats.summary())
        except Exception as e:
            logging.error(f"Indexer run failed: {e}", exc_info=True)
            raise
        return

    # Queue mode → dispatch
    logging.info("SharePoint dispatcher triggered (queue mode)")
    try:
        _dispatch_files()
    except Exception as e:
        logging.error(f"Dispatch failed: {e}", exc_info=True)
        raise


# ---------------------------------------------------------------------------
# Queue mode — worker
# ---------------------------------------------------------------------------

@app.queue_trigger(
    arg_name="msg",
    queue_name=INDEXER_QUEUE,
    connection="AzureWebJobsStorage",
)
def sp_worker(msg: func.QueueMessage) -> None:
    """Process a single file. Retried automatically on unhandled exceptions."""
    payload = json.loads(msg.get_body().decode("utf-8"))
    item_id = payload.get("item_id")
    run_id = payload.get("run_id")
    logging.info(f"Worker picked up {item_id} (run {run_id})")

    from state_store import get_store
    store = get_store()

    if store.get_failure_count(item_id) >= MAX_FAILURES:
        logging.warning(f"File {item_id} has failed {MAX_FAILURES}+ times; skipping to poison")
        raise RuntimeError(f"Terminal failure threshold for {item_id}")

    try:
        from indexer import process_single_message
        process_single_message(payload)
        store.clear_failed_file(item_id)
        store.record_run_progress(run_id, completed_delta=1)
    except Exception as e:
        count = store.record_failed_file(item_id, str(e))
        logging.error(f"Worker error on {item_id} (attempt {count}): {e}", exc_info=True)
        store.record_run_progress(run_id, failed_delta=1)
        raise  # Let Azure Functions retry / move to poison queue


# ---------------------------------------------------------------------------
# Queue mode — poison handler (terminal failures)
# ---------------------------------------------------------------------------

@app.queue_trigger(
    arg_name="msg",
    queue_name=POISON_QUEUE,
    connection="AzureWebJobsStorage",
)
def sp_poison_handler(msg: func.QueueMessage) -> None:
    try:
        payload = json.loads(msg.get_body().decode("utf-8"))
    except Exception:
        logging.error(f"Poison message is not valid JSON: {msg.get_body()!r}")
        return

    from state_store import get_store
    store = get_store()
    store.record_failed_file(
        payload.get("item_id", "unknown"),
        "poison queue — exceeded retry budget",
        terminal=True,
    )
    logging.error(f"Terminally failed: {payload}")


# ---------------------------------------------------------------------------
# Dispatcher internals
# ---------------------------------------------------------------------------

def _dispatch_files() -> None:
    """Enumerate changed files and enqueue one message per file."""
    from datetime import datetime, timezone

    from config import ProcessingMode, load_config
    from indexer import _resolve_modified_since  # internal helper, reused
    from sharepoint_client import SharePointClient
    from state_store import get_store

    cfg = load_config()
    store = get_store()
    run_id = str(uuid.uuid4())
    run_started_at = datetime.now(timezone.utc)

    sp = SharePointClient(cfg.entra, cfg.sharepoint)
    try:
        modified_since = _resolve_modified_since(cfg, run_started_at)
        items = sp.list_all_files(
            modified_since=modified_since,
            extensions=cfg.indexer.indexed_extensions,
        )
    finally:
        sp.close()

    if not items:
        logging.info("No files to enqueue")
        if cfg.indexer.processing_mode == ProcessingMode.SINCE_LAST_RUN:
            try:
                store.write_watermark(run_started_at)
            except Exception as e:  # noqa: BLE001
                logging.warning(f"Could not write watermark: {e}")
        return

    store.record_run_start(run_id, expected=len(items))
    enqueued = 0
    for item in items:
        payload = {
            "run_id": run_id,
            "drive_id": item.get("_drive_id", ""),
            "drive_name": item.get("_drive_name", ""),
            "item_id": item["id"],
            "name": item.get("name", ""),
            "size": item.get("size", 0),
            "web_url": item.get("webUrl", ""),
            "last_modified": item.get("lastModifiedDateTime", ""),
        }
        try:
            store.enqueue(payload)
            enqueued += 1
        except Exception as e:  # noqa: BLE001
            logging.error(f"Failed to enqueue {item.get('name', item['id'])}: {e}")

    logging.info(f"Dispatched run {run_id}: enqueued {enqueued}/{len(items)} files")

    # Advance watermark immediately after successful enumeration.
    # Individual file failures are tracked in failedFiles and retried separately.
    if cfg.indexer.processing_mode == ProcessingMode.SINCE_LAST_RUN:
        try:
            store.write_watermark(run_started_at)
        except Exception as e:  # noqa: BLE001
            logging.warning(f"Could not write watermark: {e}")


# ---------------------------------------------------------------------------
# HTTP trigger: /api/search
#
# Returns documents visible to the authenticated caller. Copilot Studio (or any
# Entra-authenticated client) POSTs with a bearer token + JSON query body.
# ---------------------------------------------------------------------------

@app.route(
    route="search",
    methods=["POST"],
    auth_level=func.AuthLevel.ANONYMOUS,  # JWT is validated in code, not by Functions keys
)
def sp_search(req: func.HttpRequest) -> func.HttpResponse:
    """Security-trimmed search endpoint.

    Primary consumer: the `OnKnowledgeRequested` topic inside a Copilot Studio
    generative-orchestration agent. The topic's HTTP action POSTs here with
    the signed-in user's delegated Entra token in `Authorization`; we validate
    the JWT, resolve the user's transitive groups via Graph, and run a single-
    vector hybrid + semantic query with a permission filter applied server-side.
    """
    from config import load_config
    from search_client import SearchPushClient
    from search_security import GraphIdentityResolver, TokenValidationError, validate_user_token

    cfg = load_config()

    api_audience = os.getenv("API_AUDIENCE") or os.getenv("CLIENT_ID")
    if not api_audience:
        return _json_error(500, "API_AUDIENCE (or CLIENT_ID) app setting is not configured")

    auth_header = req.headers.get("authorization") or req.headers.get("Authorization")
    if not auth_header:
        return _json_error(401, "Missing Authorization header")

    try:
        user = validate_user_token(auth_header, audience=api_audience, tenant_id=cfg.entra.tenant_id)
    except TokenValidationError as e:
        logging.warning(f"Rejecting request: {e}")
        return _json_error(401, str(e))

    try:
        body = req.get_json()
    except ValueError:
        return _json_error(400, "Request body must be JSON")

    query = (body or {}).get("query", "").strip()
    if not query:
        return _json_error(400, "`query` is required")
    top = int((body or {}).get("top", 10))
    top = max(1, min(top, 50))

    global _identity_resolver, _search_client_singleton
    if _identity_resolver is None:
        _identity_resolver = GraphIdentityResolver()
    if _search_client_singleton is None:
        _search_client_singleton = SearchPushClient(cfg.search, cfg.multimodal)

    identity_ids = _identity_resolver.get_identity_ids(user.oid)
    logging.info(
        f"/api/search user={user.upn or user.oid} identities={len(identity_ids)} query={query!r} top={top}"
    )

    try:
        # AI Search's registered AI-Services-Vision vectorizer converts the
        # query text into a 1024d vector server-side — no client-side embedding
        # needed. Callers who want to supply a pre-computed vector can still
        # pass `query_vector=` to search_with_trimming directly.
        citations = _search_client_singleton.search_with_trimming(
            query=query,
            identity_ids=identity_ids,
            top=top,
        )
    except Exception as e:  # noqa: BLE001
        logging.error(f"Search failed: {e}", exc_info=True)
        return _json_error(500, "Search execution failed")

    return func.HttpResponse(
        body=json.dumps({
            "query": query,
            "user": {"oid": user.oid, "upn": user.upn},
            "count": len(citations),
            "results": citations,
        }),
        status_code=200,
        mimetype="application/json",
    )


def _json_error(status: int, message: str) -> func.HttpResponse:
    return func.HttpResponse(
        body=json.dumps({"error": message}),
        status_code=status,
        mimetype="application/json",
    )


# ---------------------------------------------------------------------------
# Scheduled index backup (+ manual HTTP trigger for on-demand runs)
# ---------------------------------------------------------------------------

@app.timer_trigger(schedule=BACKUP_SCHEDULE, arg_name="timer", run_on_startup=False)
def sp_backup_timer(timer: func.TimerRequest) -> None:
    logging.info("SharePoint index-backup timer fired")
    try:
        _run_backup()
    except Exception as e:  # noqa: BLE001
        logging.error(f"Backup failed: {e}", exc_info=True)
        raise


@app.route(route="backup", methods=["POST"], auth_level=func.AuthLevel.FUNCTION)
def sp_backup_manual(req: func.HttpRequest) -> func.HttpResponse:
    """On-demand backup trigger. Requires an `x-functions-key` header — this
    endpoint is for operators, not end-user callers."""
    try:
        result = _run_backup()
        return func.HttpResponse(
            body=json.dumps({
                "folder": result.folder,
                "schema_bytes": result.schema_bytes,
                "docs_count": result.docs_count,
                "watermarks_count": result.watermarks_count,
                "failed_files_count": result.failed_files_count,
                "duration_s": round(result.duration_s, 2),
            }),
            status_code=200,
            mimetype="application/json",
        )
    except Exception as e:  # noqa: BLE001
        logging.error(f"Manual backup failed: {e}", exc_info=True)
        return _json_error(500, f"Backup failed: {e}")


def _run_backup():
    from config import load_config
    from index_backup import IndexBackup
    cfg = load_config()
    backup = IndexBackup(cfg)
    return backup.run()
