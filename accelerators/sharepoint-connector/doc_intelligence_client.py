"""
Azure AI Document Intelligence — Layout model (prebuilt-layout).

Extracts structured content from PDFs, Word, PowerPoint, Excel, and image files:
  - Paragraphs in reading order, with page + bounding polygon
  - Figures (embedded images) with cropped bytes, page, bounding polygon
  - Tables (serialised as paragraphs for chunking)

Returns a list of blocks.Block ready for the chunker.

Authenticates via managed identity (DefaultAzureCredential). Uses the official
`azure-ai-documentintelligence` SDK so HTTP plumbing, pagination, and the LRO
poller are handled for us.
"""

from __future__ import annotations

import json
import logging

from azure.identity import DefaultAzureCredential

from blocks import Block, BlockKind, LocationMetadata
from config import DocIntelConfig

logger = logging.getLogger(__name__)


# Document Intelligence Layout supports these file types (4.0 / GA).
LAYOUT_SUPPORTED_EXTS: frozenset[str] = frozenset({
    ".pdf", ".docx", ".docm", ".xlsx", ".xlsm", ".pptx", ".pptm",
    ".png", ".jpg", ".jpeg", ".tiff", ".bmp", ".heif",
})

_CONTENT_TYPE_BY_EXT: dict[str, str] = {
    ".pdf": "application/pdf",
    ".docx": "application/vnd.openxmlformats-officedocument.wordprocessingml.document",
    ".docm": "application/vnd.openxmlformats-officedocument.wordprocessingml.document",
    ".xlsx": "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet",
    ".xlsm": "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet",
    ".pptx": "application/vnd.openxmlformats-officedocument.presentationml.presentation",
    ".pptm": "application/vnd.openxmlformats-officedocument.presentationml.presentation",
    ".png": "image/png",
    ".jpg": "image/jpeg",
    ".jpeg": "image/jpeg",
    ".tiff": "image/tiff",
    ".bmp": "image/bmp",
    ".heif": "image/heif",
}


class DocIntelligenceClient:
    """Thin wrapper around azure-ai-documentintelligence begin_analyze_document."""

    def __init__(self, config: DocIntelConfig, credential: DefaultAzureCredential | None = None):
        self._cfg = config
        self._credential = credential or DefaultAzureCredential()
        self._client = None  # Lazy

    @property
    def enabled(self) -> bool:
        return bool(self._cfg.endpoint)

    def _lazy_client(self):
        if self._client is None:
            from azure.ai.documentintelligence import DocumentIntelligenceClient  # type: ignore
            self._client = DocumentIntelligenceClient(
                endpoint=self._cfg.endpoint,
                credential=self._credential,
            )
        return self._client

    # ------------------------------------------------------------------ #

    def extract_blocks(self, file_path: str, ext: str) -> list[Block]:
        """Run Layout on a file path and convert the result into Blocks.

        Empty list if the extension is unsupported or the service fails.
        """
        if not self.enabled:
            return []
        if ext.lower() not in LAYOUT_SUPPORTED_EXTS:
            return []

        try:
            client = self._lazy_client()
            content_type = _CONTENT_TYPE_BY_EXT.get(ext.lower(), "application/octet-stream")
            with open(file_path, "rb") as f:
                poller = client.begin_analyze_document(
                    model_id="prebuilt-layout",
                    body=f,
                    content_type=content_type,
                    # Request figure cropping so the LRO returns embedded image bytes.
                    output=["figures"],
                )
            result = poller.result()
        except Exception as e:  # noqa: BLE001
            logger.warning(f"Document Intelligence failed for {file_path}: {e}")
            return []

        blocks: list[Block] = []
        order = 0

        # ---- Text: one block per paragraph (reading order preserved). ----
        for paragraph in getattr(result, "paragraphs", None) or []:
            text = (paragraph.content or "").strip()
            if not text:
                continue
            loc = _first_bounding_region(paragraph.bounding_regions if hasattr(paragraph, "bounding_regions") else None)
            blocks.append(Block(
                kind=BlockKind.TEXT,
                order=order,
                text=text,
                location=loc,
            ))
            order += 1

        # ---- Tables: serialised as TSV-ish paragraph blocks. ----
        for tbl in getattr(result, "tables", None) or []:
            rows: list[list[str]] = [[""] * (tbl.column_count or 0) for _ in range(tbl.row_count or 0)]
            for cell in tbl.cells or []:
                if 0 <= cell.row_index < len(rows) and 0 <= cell.column_index < len(rows[0]):
                    rows[cell.row_index][cell.column_index] = (cell.content or "").replace("\t", " ")
            text = "\n".join("\t".join(r) for r in rows if any(c.strip() for c in r)).strip()
            if text:
                loc = _first_bounding_region(tbl.bounding_regions if hasattr(tbl, "bounding_regions") else None)
                blocks.append(Block(
                    kind=BlockKind.TEXT,
                    order=order,
                    text=f"[TABLE]\n{text}",
                    location=loc,
                ))
                order += 1

        # ---- Figures: image blocks with cropped bytes. ----
        figures = getattr(result, "figures", None) or []
        for idx, fig in enumerate(figures):
            loc = _first_bounding_region(getattr(fig, "bounding_regions", None))
            caption = ""
            cap = getattr(fig, "caption", None)
            if cap is not None:
                caption = getattr(cap, "content", "") or ""

            image_bytes: bytes | None = None
            try:
                # Newer SDK versions expose a helper to fetch the cropped figure.
                client = self._lazy_client()
                stream = client.get_analyze_result_figure(
                    model_id="prebuilt-layout",
                    result_id=getattr(poller, "details", {}).get("operation_id") if hasattr(poller, "details") else "",
                    figure_id=getattr(fig, "id", f"fig_{idx}"),
                )
                image_bytes = b"".join(stream) if stream else None
            except Exception as e:  # noqa: BLE001
                logger.debug(f"Could not fetch figure {idx} crop: {e}")

            blocks.append(Block(
                kind=BlockKind.IMAGE,
                order=order,
                text=caption,
                image_bytes=image_bytes,
                image_mime="image/png",
                location=loc,
            ))
            order += 1

        logger.info(f"DocIntel extracted {len(blocks)} blocks from {file_path} "
                    f"({sum(1 for b in blocks if b.is_image)} images)")
        return blocks

    def close(self) -> None:
        if self._client is not None:
            try:
                self._client.close()
            except Exception:  # noqa: BLE001
                pass


def _first_bounding_region(regions) -> LocationMetadata:
    """Convert the first bounding region (if any) into our LocationMetadata."""
    if not regions:
        return LocationMetadata()
    first = regions[0]
    page = int(getattr(first, "page_number", 0) or 0)
    poly = getattr(first, "polygon", None) or []
    # Layout polygons are flat [x1,y1,x2,y2,...]. Pair them up and JSON-encode.
    try:
        paired = [[poly[i], poly[i + 1]] for i in range(0, len(poly), 2)]
        poly_str = json.dumps(paired)
    except Exception:  # noqa: BLE001
        poly_str = ""
    return LocationMetadata(page_number=page, bounding_polygons=poly_str)
