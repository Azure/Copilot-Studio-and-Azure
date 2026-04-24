"""
Main indexer orchestrator — Pattern A (unified multimodal).

Per-file pipeline:
  1. Stream download → tempfile.
  2. extract_blocks() → ordered list of TEXT + IMAGE blocks.
     - Standalone image files → single IMAGE block with raw bytes.
     - PDF/DOCX/PPTX/XLSX (DocIntel enabled) → Layout → text + figure blocks.
     - Plain-text formats → single TEXT block.
  3. chunk_blocks() → one chunk per image, plus text chunks with overlap.
  4. Azure AI Vision multimodal embeds every chunk:
     - Text chunks  → vectorizeText  → content_embedding (1024d).
     - Image chunks → vectorizeImage → content_embedding (1024d, same space).
     - Image crops uploaded to blob for citation rendering (content_path).
  5. Single upload to the unified-vector index.

No Azure OpenAI embedding, no gpt-4o vision — only Azure AI Vision multimodal
and (optionally) Document Intelligence for layout-aware extraction.
"""

from __future__ import annotations

import hashlib
import logging
import os
import tempfile
import threading
from concurrent.futures import ThreadPoolExecutor, as_completed
from dataclasses import dataclass, field
from datetime import datetime, timezone
from typing import Any

from chunker import TextChunk, chunk_blocks
from config import AppConfig, ProcessingMode, load_config
from doc_intelligence_client import DocIntelligenceClient
from document_processor import extract_blocks
from image_storage import ImageStore
from multimodal_embeddings_client import MultimodalEmbeddingsClient
from search_client import SearchPushClient
from sharepoint_client import SharePointClient, SharePointFile
from state_store import get_store

logger = logging.getLogger(__name__)


@dataclass
class IndexerStats:
    """Thread-safe statistics for an indexer run."""
    files_discovered: int = 0
    files_processed: int = 0
    files_skipped_fresh: int = 0
    files_skipped_error: int = 0
    chunks_uploaded: int = 0
    errors: list[str] = field(default_factory=list)
    _lock: threading.Lock = field(default_factory=threading.Lock, repr=False)

    def record_processed(self, chunks: int) -> None:
        with self._lock:
            self.files_processed += 1
            self.chunks_uploaded += chunks

    def record_skipped_fresh(self) -> None:
        with self._lock:
            self.files_skipped_fresh += 1

    def record_error(self, message: str) -> None:
        with self._lock:
            self.files_skipped_error += 1
            self.errors.append(message)

    def summary(self) -> str:
        return (
            f"Indexer run complete: "
            f"{self.files_discovered} discovered, "
            f"{self.files_processed} processed, "
            f"{self.files_skipped_fresh} skipped (fresh), "
            f"{self.files_skipped_error} errors, "
            f"{self.chunks_uploaded} chunks uploaded"
        )


def _make_parent_id(drive_id: str, item_id: str) -> str:
    raw = f"{drive_id}:{item_id}"
    return hashlib.sha256(raw.encode()).hexdigest()[:32]


def _is_fresh(
    search_client: SearchPushClient,
    parent_id: str,
    file_last_modified: datetime,
) -> bool:
    existing = search_client.check_freshness(parent_id)
    if existing is None:
        return False
    try:
        if isinstance(existing, str):
            indexed_dt = datetime.fromisoformat(existing.replace("Z", "+00:00"))
        else:
            indexed_dt = existing
        return (file_last_modified - indexed_dt).total_seconds() <= 1.0
    except Exception as e:  # noqa: BLE001
        logger.debug("Freshness check parse error for %s: %s", parent_id, e)
        return False


# ---------------------------------------------------------------------------
# Per-file pipeline
# ---------------------------------------------------------------------------


def _process_single_file(
    sp_file: SharePointFile,
    config: AppConfig,
    search: SearchPushClient,
    multimodal: MultimodalEmbeddingsClient,
    stats: IndexerStats,
    content_path: str | None = None,
    doc_intel: DocIntelligenceClient | None = None,
    image_store: ImageStore | None = None,
) -> None:
    """Extract → chunk → embed → push. Unified 1024d vector for every chunk."""
    parent_id = _make_parent_id(sp_file.drive_id, sp_file.id)

    if _is_fresh(search, parent_id, sp_file.last_modified):
        stats.record_skipped_fresh()
        logger.debug(f"Skipping (fresh): {sp_file.name}")
        return

    if not sp_file.content and not content_path:
        logger.warning(f"No content for {sp_file.name}, skipping")
        stats.record_error(f"No content: {sp_file.name}")
        return

    # Ensure a file path for extractors (they prefer disk over in-memory).
    cleanup_tmp: str | None = None
    effective_path = content_path
    if effective_path is None and sp_file.content is not None:
        fd, effective_path = tempfile.mkstemp(prefix="sp-inline-", suffix=f"-{_safe_name(sp_file.name)}")
        with os.fdopen(fd, "wb") as f:
            f.write(sp_file.content)
        cleanup_tmp = effective_path

    try:
        blocks = extract_blocks(effective_path, sp_file.name, doc_intel=doc_intel)
        if not blocks:
            logger.warning(f"No blocks extracted from {sp_file.name}, skipping")
            stats.record_error(f"No blocks: {sp_file.name}")
            return

        chunks = chunk_blocks(
            blocks,
            doc_id=parent_id,
            chunk_size=config.indexer.chunk_size,
            chunk_overlap=config.indexer.chunk_overlap,
        )
        if not chunks:
            logger.warning(f"No chunks generated for {sp_file.name}")
            stats.record_error(f"No chunks: {sp_file.name}")
            return

        # --- Embed every chunk through the same multimodal endpoint --------
        # Chunks are vectorised in parallel up to `vectorise_concurrency`.
        # The MultimodalEmbeddingsClient holds its own semaphore so Vision
        # rate limits are honoured even if callers are over-eager.
        def _vectorise_one(chunk: TextChunk) -> dict[str, Any] | None:
            if chunk.is_image:
                return _build_image_doc(chunk, parent_id, sp_file, multimodal, image_store)
            return _build_text_doc(chunk, parent_id, sp_file, multimodal)

        workers = max(1, min(config.indexer.vectorise_concurrency, len(chunks)))
        if workers == 1:
            results = [_vectorise_one(c) for c in chunks]
        else:
            with ThreadPoolExecutor(max_workers=workers, thread_name_prefix="vec") as pool:
                results = list(pool.map(_vectorise_one, chunks))
        docs: list[dict[str, Any]] = [d for d in results if d is not None]

        if not docs:
            stats.record_error(f"All chunks failed to embed: {sp_file.name}")
            return

        # Delete any previous chunks for this document.
        try:
            search.delete_documents_by_parent(parent_id)
        except Exception as e:  # noqa: BLE001
            logger.warning(f"Could not delete old chunks for {sp_file.name}: {e}")

        try:
            uploaded = search.upload_documents(docs)
            stats.record_processed(uploaded)
            n_text = sum(1 for c in chunks if not c.is_image)
            n_image = sum(1 for c in chunks if c.is_image)
            logger.info(
                f"Indexed: {sp_file.name} — {n_text} text + {n_image} image chunks"
            )
        except Exception as e:  # noqa: BLE001
            logger.error(f"Upload failed for {sp_file.name}: {e}")
            stats.record_error(f"Upload error: {sp_file.name} - {e}")

    finally:
        if cleanup_tmp is not None:
            try:
                os.unlink(cleanup_tmp)
            except OSError:
                pass


def _common_fields(chunk: TextChunk, parent_id: str, sp_file: SharePointFile) -> dict[str, Any]:
    return {
        "chunk_id": chunk.chunk_id,
        "parent_id": parent_id,
        "content_text": chunk.text,
        "title": sp_file.name,
        "source_url": sp_file.web_url,
        "last_modified": sp_file.last_modified.isoformat(),
        "content_type": sp_file.content_type,
        "file_size": sp_file.size,
        "created_by": sp_file.created_by,
        "modified_by": sp_file.modified_by,
        "drive_name": sp_file.drive_name,
        "permission_ids": sp_file.permissions or [],
        "location_metadata": {
            "page_number": chunk.location.page_number,
            "bounding_polygons": chunk.location.bounding_polygons,
        },
    }


def _build_text_doc(
    chunk: TextChunk,
    parent_id: str,
    sp_file: SharePointFile,
    multimodal: MultimodalEmbeddingsClient,
) -> dict[str, Any] | None:
    vector = multimodal.vectorize_text(chunk.text)
    if vector is None:
        logger.warning(f"Skipping text chunk {chunk.chunk_id}: vectorizeText returned None")
        return None
    doc = _common_fields(chunk, parent_id, sp_file)
    doc.update({
        "has_image": False,
        "content_path": "",
        "content_embedding": vector,
    })
    return doc


def _build_image_doc(
    chunk: TextChunk,
    parent_id: str,
    sp_file: SharePointFile,
    multimodal: MultimodalEmbeddingsClient,
    image_store: ImageStore | None,
) -> dict[str, Any] | None:
    if not chunk.image_bytes:
        return None

    vector = multimodal.vectorize_image(chunk.image_bytes, mime=chunk.image_mime)
    if vector is None:
        logger.warning(f"Skipping image chunk {chunk.chunk_id}: vectorizeImage returned None")
        return None

    content_path = ""
    if image_store is not None:
        uploaded = image_store.upload_image(
            parent_id=parent_id,
            chunk_id=chunk.chunk_id,
            image_bytes=chunk.image_bytes,
            mime=chunk.image_mime,
        )
        if uploaded:
            content_path = uploaded.relative_path

    doc = _common_fields(chunk, parent_id, sp_file)
    doc.update({
        "has_image": True,
        "content_path": content_path,
        "content_embedding": vector,
    })
    return doc


# ---------------------------------------------------------------------------
# Processing-mode resolution
# ---------------------------------------------------------------------------


def _resolve_modified_since(config: AppConfig, now: datetime) -> datetime | None:
    mode = config.indexer.processing_mode
    if mode == ProcessingMode.FULL:
        logger.info("Processing mode: FULL (all files)")
        return None
    if mode == ProcessingMode.SINCE_DATE:
        assert config.indexer.start_date is not None
        logger.info(f"Processing mode: SINCE_DATE ({config.indexer.start_date.isoformat()})")
        return config.indexer.start_date

    try:
        wm = get_store().read_watermark()
    except Exception as e:  # noqa: BLE001
        logger.warning(f"Could not read watermark, falling back to full reindex: {e}")
        return None

    if wm is None:
        logger.info("Processing mode: SINCE_LAST_RUN — no watermark yet, processing all files")
        return None
    logger.info(f"Processing mode: SINCE_LAST_RUN (watermark = {wm.isoformat()})")
    return wm


def _filter_by_root_paths(files: list[dict], root_paths: list[str]) -> list[dict]:
    """Drop delta-query items that aren't under any of the configured roots."""
    if not root_paths:
        return files
    # Normalise the configured roots for comparison.
    roots = [rp.strip("/").lower() for rp in root_paths if rp.strip()]
    if not roots:
        return files

    kept: list[dict] = []
    for f in files:
        parent = f.get("parentReference", {}) or {}
        path = str(parent.get("path", ""))  # e.g. "/drives/{id}/root:/Finance/Reports"
        anchor = "root:"
        tail = path.split(anchor, 1)[-1] if anchor in path else path
        tail = tail.strip("/").lower()
        if any(tail == r or tail.startswith(r + "/") for r in roots):
            kept.append(f)
    return kept


def _delete_chunks_for_items(
    sp_client: SharePointClient,
    search: SearchPushClient,
    item_ids: list[str],
) -> None:
    """Remove chunks from the index for items deleted at source.

    We don't have the drive_id on a deletion event (Graph doesn't echo it in
    the `deleted` shape), so we compute the parent_id across every target
    drive and send blind deletes. `delete_documents_by_parent` is a no-op
    when the parent_id doesn't exist.
    """
    try:
        drives = sp_client.get_target_drives()
    except Exception as e:  # noqa: BLE001
        logger.warning(f"Could not enumerate drives for deletion cleanup: {e}")
        return

    for item_id in item_ids:
        for drive in drives:
            drive_id = drive.get("id", "")
            if not drive_id:
                continue
            parent_id = _make_parent_id(drive_id, item_id)
            try:
                search.delete_documents_by_parent(parent_id)
            except Exception as e:  # noqa: BLE001
                logger.debug(f"Deletion cleanup for {parent_id} skipped: {e}")


def _reconcile_deleted_files(
    search: SearchPushClient,
    indexed_parent_ids: set[str],
    current_parent_ids: set[str],
) -> int:
    orphaned = indexed_parent_ids - current_parent_ids
    removed = 0
    for parent_id in orphaned:
        try:
            search.delete_documents_by_parent(parent_id)
            removed += 1
        except Exception as e:  # noqa: BLE001
            logger.warning(f"Failed to remove orphaned chunks for {parent_id}: {e}")
    if removed:
        logger.info(f"Reconciliation: removed chunks for {removed} deleted files")
    return removed


# ---------------------------------------------------------------------------
# Inline run (legacy single-function mode)
# ---------------------------------------------------------------------------


def run_indexer(config: AppConfig | None = None) -> IndexerStats:
    if config is None:
        config = load_config()

    stats = IndexerStats()
    max_file_size = config.indexer.max_file_size_mb * 1024 * 1024

    sp_client = SharePointClient(config.entra, config.sharepoint)
    search = SearchPushClient(config.search, config.multimodal)
    multimodal = MultimodalEmbeddingsClient(
        endpoint=config.multimodal.endpoint,
        model_version=config.multimodal.model_version,
    )
    doc_intel = DocIntelligenceClient(config.docintel) if config.docintel.enabled else None
    image_store: ImageStore | None = None
    try:
        image_store = ImageStore(container=config.multimodal.images_container)
    except Exception as e:  # noqa: BLE001
        logger.warning(f"ImageStore init failed; image crops will not be uploaded: {e}")

    run_started_at = datetime.now(timezone.utc)

    try:
        search.ensure_index(force_recreate=config.indexer.force_recreate_index)
        if config.indexer.force_recreate_index:
            logger.warning(
                "FORCE_RECREATE_INDEX=true — index was destroyed and recreated. "
                "Unset this flag before the next run to avoid wiping data."
            )

        # ----- File discovery ------------------------------------------------
        # For `since-last-run` mode, prefer Graph delta queries — they return
        # deletions as well as additions/modifications, so we can mirror
        # source-side deletions into the index in real time.
        deleted_item_ids: list[str] = []
        delta_tokens_updated: dict[str, str] = {}
        use_delta = (config.indexer.processing_mode == ProcessingMode.SINCE_LAST_RUN)

        if use_delta:
            try:
                existing_tokens = get_store().read_delta_tokens()
            except Exception as e:  # noqa: BLE001
                logger.warning(f"Could not read delta tokens, falling back to listing: {e}")
                existing_tokens = {}
                use_delta = False

        if use_delta:
            raw_files, deleted_item_ids, delta_tokens_updated = sp_client.list_changes_all_drives(
                delta_tokens=existing_tokens,
                extensions=config.indexer.indexed_extensions,
            )
            logger.info(
                f"Delta query: {len(raw_files)} modified, {len(deleted_item_ids)} deleted"
            )
            # If the user has scoped to specific root paths, filter deltas client-side.
            if config.indexer.root_paths:
                raw_files = _filter_by_root_paths(raw_files, config.indexer.root_paths)
        else:
            modified_since = _resolve_modified_since(config, run_started_at)
            raw_files = sp_client.list_all_files(
                modified_since=modified_since,
                extensions=config.indexer.indexed_extensions,
                root_paths=config.indexer.root_paths,
            )

        stats.files_discovered = len(raw_files)
        logger.info(f"Discovered {stats.files_discovered} files to process")

        # ----- Deletion propagation ------------------------------------------
        # Even if there are no new files, we may still have deletions to process.
        if deleted_item_ids:
            _delete_chunks_for_items(sp_client, search, deleted_item_ids)

        if not raw_files and not deleted_item_ids:
            logger.info("No changes to index")
            return stats

        current_parent_ids = {
            _make_parent_id(item.get("_drive_id", ""), item["id"])
            for item in raw_files
        }

        def _process_item(item: dict) -> None:
            try:
                sp_file = sp_client.build_file_record(
                    item,
                    include_content=True,
                    include_permissions=True,
                    drive_name=item.get("_drive_name", ""),
                    max_file_size=max_file_size,
                )
                _process_single_file(
                    sp_file,
                    config,
                    search,
                    multimodal,
                    stats,
                    doc_intel=doc_intel,
                    image_store=image_store,
                )
            except Exception as e:  # noqa: BLE001
                logger.error(f"Error processing {item.get('name', 'unknown')}: {e}")
                stats.record_error(f"{item.get('name', 'unknown')}: {e}")

        max_workers = min(config.indexer.max_concurrency, len(raw_files))
        with ThreadPoolExecutor(max_workers=max_workers) as executor:
            futures = {executor.submit(_process_item, item): item for item in raw_files}
            for future in as_completed(futures):
                future.result()

        # ----- Reconciliation -----------------------------------------------
        # FULL mode: always run a full scan against SharePoint.
        # SINCE_LAST_RUN: delta query already caught deletions, but every Nth
        #   run we still do a belt-and-braces full scan in case any deletion
        #   slipped past delta (e.g. items removed before a delta token was
        #   first minted).
        should_full_reconcile = False
        if config.indexer.processing_mode == ProcessingMode.FULL:
            should_full_reconcile = True
        elif (
            config.indexer.reconcile_every_n_runs > 0
            and config.indexer.processing_mode == ProcessingMode.SINCE_LAST_RUN
        ):
            try:
                run_count = get_store().increment_run_counter()
                if run_count % config.indexer.reconcile_every_n_runs == 0:
                    logger.info(f"Periodic reconciliation triggered (run #{run_count})")
                    should_full_reconcile = True
            except Exception as e:  # noqa: BLE001
                logger.warning(f"Run counter unavailable: {e}")

        if should_full_reconcile:
            try:
                indexed_ids = search.get_all_parent_ids()
                # For full-reconcile we need the *complete* set of parent_ids,
                # which in delta-mode we may not have. Re-list the drive root.
                full_listing = sp_client.list_all_files(
                    modified_since=None,
                    extensions=config.indexer.indexed_extensions,
                    root_paths=config.indexer.root_paths,
                )
                full_parent_ids = {
                    _make_parent_id(item.get("_drive_id", ""), item["id"])
                    for item in full_listing
                }
                _reconcile_deleted_files(search, indexed_ids, full_parent_ids)
            except Exception as e:  # noqa: BLE001
                logger.warning(f"Reconciliation skipped: {e}")

        # ----- Persist state -------------------------------------------------
        if config.indexer.processing_mode == ProcessingMode.SINCE_LAST_RUN:
            store = get_store()
            try:
                store.write_watermark(run_started_at)
            except Exception as e:  # noqa: BLE001
                logger.warning(f"Could not write watermark: {e}")
            if delta_tokens_updated:
                try:
                    store.write_delta_tokens(delta_tokens_updated)
                except Exception as e:  # noqa: BLE001
                    logger.warning(f"Could not write delta tokens: {e}")

        logger.info(stats.summary())
        return stats

    finally:
        sp_client.close()
        search.close()
        multimodal.close()
        if doc_intel is not None:
            doc_intel.close()
        if image_store is not None:
            image_store.close()


# ---------------------------------------------------------------------------
# Queue-mode single-file processor
# ---------------------------------------------------------------------------

_client_pool_lock = threading.Lock()
_sp_client: SharePointClient | None = None
_search_client: SearchPushClient | None = None
_multimodal_client: MultimodalEmbeddingsClient | None = None
_doc_intel_client: DocIntelligenceClient | None = None
_image_store: ImageStore | None = None


def _get_worker_clients(cfg: AppConfig):
    """Build or return pooled per-worker clients."""
    global _sp_client, _search_client, _multimodal_client, _doc_intel_client, _image_store
    with _client_pool_lock:
        if _sp_client is None:
            _sp_client = SharePointClient(cfg.entra, cfg.sharepoint)
        if _search_client is None:
            _search_client = SearchPushClient(cfg.search, cfg.multimodal)
        if _multimodal_client is None:
            _multimodal_client = MultimodalEmbeddingsClient(
                endpoint=cfg.multimodal.endpoint,
                model_version=cfg.multimodal.model_version,
            )
        if _doc_intel_client is None and cfg.docintel.enabled:
            _doc_intel_client = DocIntelligenceClient(cfg.docintel)
        if _image_store is None:
            try:
                _image_store = ImageStore(container=cfg.multimodal.images_container)
            except Exception as e:  # noqa: BLE001
                logger.warning(f"ImageStore init failed: {e}")
    return (_sp_client, _search_client, _multimodal_client, _doc_intel_client, _image_store)


def process_single_message(payload: dict[str, Any]) -> None:
    """Process one queue message: download + index a single file."""
    cfg = load_config()
    sp, search, multimodal, doc_intel, image_store = _get_worker_clients(cfg)

    drive_id = payload["drive_id"]
    item_id = payload["item_id"]
    name = payload.get("name", item_id)
    web_url = payload.get("web_url", "")
    drive_name = payload.get("drive_name", "")
    last_mod_str = payload.get("last_modified", "")
    last_modified = (
        datetime.fromisoformat(last_mod_str.replace("Z", "+00:00"))
        if last_mod_str else datetime.now(timezone.utc)
    )

    size = int(payload.get("size", 0))
    max_bytes = cfg.indexer.max_file_size_mb * 1024 * 1024
    if size > max_bytes:
        logger.warning(
            f"Skipping {name}: {size / (1024*1024):.1f} MB exceeds limit "
            f"{cfg.indexer.max_file_size_mb} MB"
        )
        return

    search.ensure_index(force_recreate=False)

    tmpdir = os.getenv("TMPDIR") or tempfile.gettempdir()
    os.makedirs(tmpdir, exist_ok=True)
    fd, tmp_path = tempfile.mkstemp(prefix="sp-", suffix=f"-{_safe_name(name)}", dir=tmpdir)
    os.close(fd)
    try:
        bytes_written = sp.download_file_to_path(drive_id, item_id, tmp_path)
        logger.info(f"Streamed {bytes_written} bytes for {name}")

        try:
            permissions = sp.get_item_permissions(drive_id, item_id)
        except Exception as e:  # noqa: BLE001
            logger.warning(f"Could not fetch permissions for {name}: {e}")
            permissions = []

        sp_file = SharePointFile(
            id=item_id,
            name=name,
            size=size,
            web_url=web_url,
            drive_id=drive_id,
            last_modified=last_modified,
            created_by=payload.get("created_by", ""),
            modified_by=payload.get("modified_by", ""),
            content_type=payload.get("content_type", ""),
            drive_name=drive_name,
            content=None,
            permissions=permissions,
        )

        stats = IndexerStats()
        _process_single_file(
            sp_file,
            cfg,
            search,
            multimodal,
            stats,
            content_path=tmp_path,
            doc_intel=doc_intel,
            image_store=image_store,
        )
        logger.info(stats.summary())
    finally:
        try:
            os.unlink(tmp_path)
        except OSError:
            pass


def _safe_name(name: str) -> str:
    keep = "-._"
    return "".join(c if c.isalnum() or c in keep else "_" for c in name)[:80]
