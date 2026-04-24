"""
Configuration loader for the SharePoint → Azure AI Search connector
(Pattern A — unified multimodal).

One embedding service: Azure AI Vision multimodal (Florence).
Text chunks and image chunks both produce 1024-d vectors in the same space.

Authentication everywhere via DefaultAzureCredential (managed identity in prod,
Azure CLI for local dev). Optional CLIENT_SECRET fallback for Graph, resolved
from Key Vault via @Microsoft.KeyVault(...) app-setting reference.
"""

import logging
import os
from dataclasses import dataclass, field
from datetime import datetime, timezone
from enum import Enum
from urllib.parse import urlparse

from dotenv import load_dotenv

load_dotenv()
logger = logging.getLogger(__name__)


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------


def _get_required(key: str) -> str:
    value = os.getenv(key)
    if not value:
        raise EnvironmentError(f"Missing required environment variable: {key}")
    return value


def _get_optional(key: str, default: str = "") -> str:
    return os.getenv(key, default)


def _get_bool(key: str, default: bool = False) -> bool:
    raw = os.getenv(key)
    if raw is None or raw == "":
        return default
    return raw.strip().lower() in ("1", "true", "yes", "on")


# ---------------------------------------------------------------------------
# Enums
# ---------------------------------------------------------------------------


class ProcessingMode(str, Enum):
    FULL = "full"
    SINCE_DATE = "since-date"
    SINCE_LAST_RUN = "since-last-run"


class FunctionProcessingMode(str, Enum):
    QUEUE = "queue"
    INLINE = "inline"


# ---------------------------------------------------------------------------
# Dataclasses
# ---------------------------------------------------------------------------


@dataclass(frozen=True)
class EntraConfig:
    tenant_id: str
    client_id: str = ""
    client_secret: str = ""

    @property
    def use_managed_identity(self) -> bool:
        return not self.client_secret


@dataclass(frozen=True)
class SharePointConfig:
    site_url: str
    libraries: list[str] = field(default_factory=list)

    @property
    def hostname(self) -> str:
        return urlparse(self.site_url).hostname or ""

    @property
    def site_path(self) -> str:
        return urlparse(self.site_url).path.rstrip("/")


@dataclass(frozen=True)
class SearchConfig:
    endpoint: str
    index_name: str


@dataclass(frozen=True)
class MultimodalConfig:
    """Azure AI Vision multimodal embeddings (Florence) — 1024d vectors for
    text AND images in the same space.

    Must be populated for the indexer to produce any vectors.
    """
    endpoint: str                          # e.g. https://<foundry>.cognitiveservices.azure.com
    model_version: str = "2023-04-15"
    images_container: str = "images"

    @property
    def enabled(self) -> bool:
        return bool(self.endpoint)


@dataclass(frozen=True)
class DocIntelConfig:
    """Azure AI Document Intelligence (Layout) — optional structural extractor.

    When set, supported formats (PDF, DOCX, PPTX, XLSX, images) go through the
    prebuilt-layout model for reading-order paragraphs, tables, and figures with
    bounding polygons. When empty, the hand-written extractors are used for all
    formats; image files are embedded directly without layout metadata.
    """
    endpoint: str = ""
    skip_below_kb: int = 5
    max_image_size_mb: int = 20

    @property
    def enabled(self) -> bool:
        return bool(self.endpoint)


@dataclass(frozen=True)
class IndexerConfig:
    indexed_extensions: list[str] = field(default_factory=lambda: [
        ".pdf", ".docx", ".docm", ".xlsx", ".xlsm", ".pptx", ".pptm",
        ".txt", ".md", ".csv", ".json", ".xml", ".kml",
        ".html", ".htm",
        ".rtf", ".eml", ".epub", ".msg",
        ".odt", ".ods", ".odp",
        ".zip", ".gz",
        ".png", ".jpg", ".jpeg", ".tiff", ".bmp",
    ])
    chunk_size: int = 2000
    chunk_overlap: int = 200
    max_concurrency: int = 4
    max_file_size_mb: int = 500
    processing_mode: ProcessingMode = ProcessingMode.SINCE_LAST_RUN
    start_date: datetime | None = None
    function_processing_mode: FunctionProcessingMode = FunctionProcessingMode.QUEUE
    extract_images: bool = True
    # DESTRUCTIVE one-shot: drops + recreates the AI Search index on next run.
    force_recreate_index: bool = False
    # Per-file chunk vectorisation concurrency. The ceiling is also bounded by
    # MultimodalEmbeddingsClient's own semaphore (MULTIMODAL_MAX_IN_FLIGHT).
    vectorise_concurrency: int = 8
    # Optional folder paths inside each library to scope the indexer to.
    # Empty = whole library. Paths are relative to the drive root
    # (e.g. "Finance/Reports,HR/Policies").
    root_paths: list[str] = field(default_factory=list)
    # Periodic full reconciliation cadence (only when not running in FULL mode).
    # Every Nth run compares the index to SharePoint and removes orphans.
    # 0 = disabled.
    reconcile_every_n_runs: int = 24


@dataclass(frozen=True)
class AppConfig:
    entra: EntraConfig
    sharepoint: SharePointConfig
    search: SearchConfig
    multimodal: MultimodalConfig
    docintel: DocIntelConfig
    indexer: IndexerConfig


# ---------------------------------------------------------------------------
# Loader
# ---------------------------------------------------------------------------


def _parse_start_date(raw: str) -> datetime | None:
    if not raw:
        return None
    try:
        dt = datetime.fromisoformat(raw.replace("Z", "+00:00"))
    except ValueError as e:
        raise EnvironmentError(f"START_DATE is not a valid ISO-8601 date: {raw!r} ({e})") from e
    if dt.tzinfo is None:
        dt = dt.replace(tzinfo=timezone.utc)
    return dt


def _resolve_processing_mode() -> tuple[ProcessingMode, datetime | None]:
    raw_mode = _get_optional("PROCESSING_MODE").strip().lower()

    legacy = _get_optional("INCREMENTAL_MINUTES")
    if raw_mode == "" and legacy != "":
        logger.warning(
            "INCREMENTAL_MINUTES is deprecated; use PROCESSING_MODE=full|since-date|since-last-run."
        )
        try:
            minutes = int(legacy)
        except ValueError:
            minutes = 0
        return (ProcessingMode.FULL if minutes == 0 else ProcessingMode.SINCE_LAST_RUN, None)

    if raw_mode == "":
        return (ProcessingMode.SINCE_LAST_RUN, None)

    try:
        mode = ProcessingMode(raw_mode)
    except ValueError as e:
        raise EnvironmentError(
            f"PROCESSING_MODE must be one of {[m.value for m in ProcessingMode]}, got {raw_mode!r}"
        ) from e

    start_date = _parse_start_date(_get_optional("START_DATE"))
    if mode == ProcessingMode.SINCE_DATE and start_date is None:
        raise EnvironmentError("PROCESSING_MODE=since-date requires START_DATE (ISO-8601 UTC).")
    return (mode, start_date)


def load_config() -> AppConfig:
    libraries_raw = _get_optional("SHAREPOINT_LIBRARIES", "")
    libraries = [lib.strip() for lib in libraries_raw.split(",") if lib.strip()] if libraries_raw else []

    root_paths_raw = _get_optional("SHAREPOINT_ROOT_PATHS", "")
    root_paths = [p.strip().lstrip("/") for p in root_paths_raw.split(",") if p.strip()] if root_paths_raw else []

    extensions_raw = _get_optional(
        "INDEXED_EXTENSIONS",
        ".pdf,.docx,.docm,.xlsx,.xlsm,.pptx,.pptm,.txt,.md,.csv,.json,.xml,.kml,"
        ".html,.htm,.rtf,.eml,.epub,.msg,.odt,.ods,.odp,.zip,.gz,"
        ".png,.jpg,.jpeg,.tiff,.bmp"
    )
    extensions = [ext.strip() for ext in extensions_raw.split(",") if ext.strip()]

    mode, start_date = _resolve_processing_mode()

    fn_mode_raw = _get_optional("FUNCTION_PROCESSING_MODE", "queue").strip().lower()
    try:
        fn_mode = FunctionProcessingMode(fn_mode_raw)
    except ValueError as e:
        raise EnvironmentError(
            f"FUNCTION_PROCESSING_MODE must be one of {[m.value for m in FunctionProcessingMode]}, "
            f"got {fn_mode_raw!r}"
        ) from e

    return AppConfig(
        entra=EntraConfig(
            tenant_id=_get_required("TENANT_ID"),
            client_id=_get_optional("CLIENT_ID"),
            client_secret=_get_optional("CLIENT_SECRET"),
        ),
        sharepoint=SharePointConfig(
            site_url=_get_required("SHAREPOINT_SITE_URL"),
            libraries=libraries,
        ),
        search=SearchConfig(
            endpoint=_get_required("SEARCH_ENDPOINT"),
            index_name=_get_optional("SEARCH_INDEX_NAME", "sharepoint-index"),
        ),
        multimodal=MultimodalConfig(
            endpoint=_get_required("MULTIMODAL_ENDPOINT"),
            model_version=_get_optional("MULTIMODAL_MODEL_VERSION", "2023-04-15"),
            images_container=_get_optional("IMAGES_CONTAINER", "images"),
        ),
        docintel=DocIntelConfig(
            endpoint=_get_optional("DOCINTEL_ENDPOINT", ""),
            skip_below_kb=int(_get_optional("DOCINTEL_SKIP_BELOW_KB", "5")),
            max_image_size_mb=int(_get_optional("DOCINTEL_MAX_IMAGE_SIZE_MB", "20")),
        ),
        indexer=IndexerConfig(
            indexed_extensions=extensions,
            chunk_size=int(_get_optional("CHUNK_SIZE", "2000")),
            chunk_overlap=int(_get_optional("CHUNK_OVERLAP", "200")),
            max_concurrency=int(_get_optional("MAX_CONCURRENCY", "4")),
            max_file_size_mb=int(_get_optional("MAX_FILE_SIZE_MB", "500")),
            processing_mode=mode,
            start_date=start_date,
            function_processing_mode=fn_mode,
            extract_images=_get_bool("EXTRACT_IMAGES", True),
            force_recreate_index=_get_bool("FORCE_RECREATE_INDEX", False),
            vectorise_concurrency=int(_get_optional("VECTORISE_CONCURRENCY", "8")),
            root_paths=root_paths,
            reconcile_every_n_runs=int(_get_optional("RECONCILE_EVERY_N_RUNS", "24")),
        ),
    )
