"""
Block model shared across extraction, chunking, and indexing.

A file is decomposed into an ordered list of Blocks. Each Block is either a
TEXT segment (paragraph / heading / table-cell) or an IMAGE (a figure cropped
from the source document with its page number and bounding polygon).

- Plain-text formats (TXT, MD, CSV, JSON, HTML, …) produce exactly one TEXT
  Block covering the whole document.
- Document Intelligence Layout emits one Block per paragraph + one Block per
  figure, in reading order, with spatial metadata preserved.

The downstream chunker consumes Blocks — text Blocks are chunked with overlap,
image Blocks always become a standalone chunk (neighbour-text association is
preserved by putting the preceding paragraph into the chunk's `neighbour_text`).
"""

from __future__ import annotations

from dataclasses import dataclass, field
from enum import Enum


class BlockKind(str, Enum):
    TEXT = "text"
    IMAGE = "image"


@dataclass
class LocationMetadata:
    """Spatial metadata mirroring the Azure AI Search multimodal tutorial shape."""
    page_number: int = 0
    # JSON-encoded list of polygon coordinates, e.g. "[[x1,y1],[x2,y2],…]".
    # Kept as a string for index compatibility (Edm.String per the tutorial).
    bounding_polygons: str = ""


@dataclass
class Block:
    """A text or image segment extracted from a source document."""
    kind: BlockKind
    order: int
    text: str = ""                          # TEXT: the paragraph text. IMAGE: optional caption.
    image_bytes: bytes | None = None        # IMAGE: raw cropped image bytes.
    image_mime: str = "image/png"           # IMAGE: mime type of image_bytes.
    location: LocationMetadata = field(default_factory=LocationMetadata)

    @property
    def is_image(self) -> bool:
        return self.kind == BlockKind.IMAGE

    @property
    def is_text(self) -> bool:
        return self.kind == BlockKind.TEXT
