"""
Text chunking with overlap.
Splits extracted document text into chunks suitable for embedding and indexing.

Two public entry points:

  chunk_text(text, doc_id, chunk_size, chunk_overlap)
      Back-compat: split a flat string into overlapping TextChunks.

  chunk_blocks(blocks, doc_id, chunk_size, chunk_overlap)
      Preferred for multimodal: each IMAGE block becomes its own standalone
      chunk with `is_image=True` and `image_bytes` carried through. TEXT
      blocks are concatenated and then split with overlap, preserving page /
      bounding-box location metadata on each resulting chunk. Neighbour text
      from the paragraph immediately before/after an image is captured on
      the image chunk so RAG responses can ground on surrounding context.
"""

from __future__ import annotations

import logging
from dataclasses import dataclass, field

from blocks import Block, BlockKind, LocationMetadata

logger = logging.getLogger(__name__)


@dataclass
class TextChunk:
    """A chunk of text with its position metadata."""
    chunk_id: str
    text: str
    index: int
    total_chunks: int
    # Multimodal extensions (defaulted so existing call-sites still work).
    is_image: bool = False
    image_bytes: bytes | None = None
    image_mime: str = "image/png"
    neighbour_text: str = ""
    location: LocationMetadata = field(default_factory=LocationMetadata)


def chunk_text(
    text: str,
    doc_id: str,
    chunk_size: int = 2000,
    chunk_overlap: int = 200,
) -> list[TextChunk]:
    """
    Split text into overlapping chunks.

    Args:
        text: The full document text.
        doc_id: Unique document identifier (used to build chunk IDs).
        chunk_size: Maximum characters per chunk.
        chunk_overlap: Number of overlapping characters between consecutive chunks.

    Returns:
        List of TextChunk objects.
    """
    if not text or not text.strip():
        return []

    # Guard against misconfiguration that would cause infinite loops
    if chunk_overlap >= chunk_size:
        logger.warning(
            f"chunk_overlap ({chunk_overlap}) >= chunk_size ({chunk_size}), "
            f"clamping overlap to {chunk_size // 4}"
        )
        chunk_overlap = chunk_size // 4

    text = text.strip()

    # If text fits in a single chunk, return as-is
    if len(text) <= chunk_size:
        return [TextChunk(
            chunk_id=f"{doc_id}_c00000",
            text=text,
            index=0,
            total_chunks=1,
        )]

    chunks: list[TextChunk] = []
    start = 0
    chunk_index = 0

    while start < len(text):
        end = start + chunk_size

        # Try to break at a sentence or paragraph boundary
        if end < len(text):
            # Look for paragraph break
            para_break = text.rfind("\n\n", start + chunk_size // 2, end)
            if para_break > start:
                end = para_break + 2
            else:
                # Look for sentence break
                for sep in (". ", ".\n", "! ", "? ", ";\n", "\n"):
                    sep_pos = text.rfind(sep, start + chunk_size // 2, end)
                    if sep_pos > start:
                        end = sep_pos + len(sep)
                        break

        chunk_text_content = text[start:end].strip()

        if chunk_text_content:
            chunks.append(TextChunk(
                chunk_id=f"{doc_id}_c{chunk_index:05d}",
                text=chunk_text_content,
                index=chunk_index,
                total_chunks=0,  # Will be set after all chunks are created
            ))
            chunk_index += 1

        # Move start forward, accounting for overlap
        start = end - chunk_overlap
        if start >= len(text):
            break

    # Set total_chunks on all chunks
    total = len(chunks)
    for chunk in chunks:
        chunk.total_chunks = total

    logger.debug(f"Split doc {doc_id} into {total} chunks (size={chunk_size}, overlap={chunk_overlap})")
    return chunks


# ======================================================================
# Block-aware chunking (multimodal path)
# ======================================================================


def chunk_blocks(
    blocks: list[Block],
    doc_id: str,
    chunk_size: int = 2000,
    chunk_overlap: int = 200,
) -> list[TextChunk]:
    """
    Chunk a block-structured document.

    Rules:
      - IMAGE blocks always become their own chunk (never merged with text).
        The text of the immediately preceding TEXT block is carried as
        `neighbour_text` for grounding context.
      - Consecutive TEXT blocks are concatenated and then split via
        chunk_text(), preserving the location of the first text block that
        contributed to each resulting chunk.

    Page numbers and bounding polygons are preserved on every chunk.
    """
    if not blocks:
        return []

    chunks: list[TextChunk] = []
    chunk_index = 0
    text_buffer: list[Block] = []

    def _flush_text_buffer() -> None:
        nonlocal chunk_index
        if not text_buffer:
            return
        # Concatenate with blank-line separators so paragraph boundaries remain
        # visible to the boundary-detection logic in chunk_text.
        combined = "\n\n".join(b.text for b in text_buffer if b.text.strip())
        if not combined.strip():
            text_buffer.clear()
            return

        pieces = chunk_text(
            combined,
            doc_id=doc_id,
            chunk_size=chunk_size,
            chunk_overlap=chunk_overlap,
        )
        # Use the location of the first TEXT block as the chunk's anchor.
        anchor = text_buffer[0].location
        for piece in pieces:
            chunks.append(TextChunk(
                chunk_id=f"{doc_id}_c{chunk_index:05d}",
                text=piece.text,
                index=chunk_index,
                total_chunks=0,  # Patched after all chunks created.
                is_image=False,
                location=anchor,
            ))
            chunk_index += 1
        text_buffer.clear()

    previous_text = ""
    for idx, block in enumerate(blocks):
        if block.is_image:
            # Emit any accumulated text first so reading order is preserved.
            _flush_text_buffer()

            # Peek at the next text block (if any) for suffix context.
            next_text = ""
            for look in range(idx + 1, len(blocks)):
                if blocks[look].is_text and blocks[look].text.strip():
                    next_text = blocks[look].text.strip()
                    break

            neighbour = "\n".join(t for t in (previous_text, next_text) if t)
            caption = (block.text or "").strip()
            # The chunk's `text` field is the caption (if DocIntel gave one)
            # plus the neighbour context, so text search still catches it.
            display_text = caption
            if neighbour:
                display_text = f"{display_text}\n\n{neighbour}".strip()

            chunks.append(TextChunk(
                chunk_id=f"{doc_id}_c{chunk_index:05d}",
                text=display_text or "[IMAGE]",
                index=chunk_index,
                total_chunks=0,
                is_image=True,
                image_bytes=block.image_bytes,
                image_mime=block.image_mime,
                neighbour_text=neighbour,
                location=block.location,
            ))
            chunk_index += 1
        else:
            if block.text.strip():
                text_buffer.append(block)
                previous_text = block.text.strip()

    # Flush any trailing text.
    _flush_text_buffer()

    total = len(chunks)
    for c in chunks:
        c.total_chunks = total

    logger.debug(
        f"chunk_blocks produced {total} chunks for {doc_id} "
        f"({sum(1 for c in chunks if c.is_image)} image chunks)"
    )
    return chunks
