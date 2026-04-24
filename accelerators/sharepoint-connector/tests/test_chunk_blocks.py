"""Tests for the block-aware chunker (chunk_blocks)."""

from __future__ import annotations

from blocks import Block, BlockKind, LocationMetadata
from chunker import chunk_blocks


def _text_block(text: str, order: int, page: int = 1) -> Block:
    return Block(
        kind=BlockKind.TEXT,
        order=order,
        text=text,
        location=LocationMetadata(page_number=page, bounding_polygons=""),
    )


def _image_block(order: int, page: int = 1, caption: str = "", image_bytes: bytes = b"\x89PNG") -> Block:
    return Block(
        kind=BlockKind.IMAGE,
        order=order,
        text=caption,
        image_bytes=image_bytes,
        image_mime="image/png",
        location=LocationMetadata(page_number=page, bounding_polygons=""),
    )


class TestChunkBlocks:
    def test_empty_blocks(self):
        assert chunk_blocks([], doc_id="doc1") == []

    def test_single_text_block_becomes_one_chunk(self):
        chunks = chunk_blocks([_text_block("hello world", 0)], doc_id="doc1")
        assert len(chunks) == 1
        assert chunks[0].text == "hello world"
        assert chunks[0].is_image is False
        assert chunks[0].image_bytes is None

    def test_image_block_becomes_own_chunk(self):
        chunks = chunk_blocks([_image_block(0, caption="Q3 chart")], doc_id="doc1")
        assert len(chunks) == 1
        assert chunks[0].is_image is True
        assert chunks[0].image_bytes == b"\x89PNG"
        assert "Q3 chart" in chunks[0].text

    def test_image_gets_neighbour_text_from_preceding_paragraph(self):
        blocks = [
            _text_block("Revenue grew 35% in Q3.", 0),
            _image_block(1, caption="chart"),
            _text_block("Key drivers were …", 2),
        ]
        chunks = chunk_blocks(blocks, doc_id="doc1")
        # Expect 3 chunks: text, image, text — reading order preserved.
        assert [c.is_image for c in chunks] == [False, True, False]
        image_chunk = chunks[1]
        # Neighbour text should include both the preceding paragraph AND
        # the following paragraph (both sides of the image).
        assert "Revenue grew 35% in Q3." in image_chunk.neighbour_text
        assert "Key drivers were" in image_chunk.neighbour_text
        # Caption + neighbour appear in the chunk text so keyword search finds it.
        assert "Revenue grew 35% in Q3." in image_chunk.text
        assert "chart" in image_chunk.text

    def test_image_without_caption_still_produces_chunk(self):
        chunks = chunk_blocks([_image_block(0)], doc_id="doc1")
        assert len(chunks) == 1
        assert chunks[0].is_image is True
        assert chunks[0].text  # non-empty placeholder or "[IMAGE]"

    def test_consecutive_text_blocks_merged_then_split(self):
        # A long run of text should be split by chunk_text's boundaries.
        blocks = [
            _text_block("alpha. " * 200, 0),
            _text_block("beta. " * 200, 1),
        ]
        chunks = chunk_blocks(blocks, doc_id="doc1", chunk_size=500, chunk_overlap=50)
        # At minimum, more than one chunk since we exceeded chunk_size.
        assert len(chunks) > 1
        assert all(not c.is_image for c in chunks)

    def test_location_metadata_propagates_to_image_chunk(self):
        blocks = [_image_block(0, page=7)]
        chunks = chunk_blocks(blocks, doc_id="doc1")
        assert chunks[0].location.page_number == 7

    def test_total_chunks_patched_on_every_chunk(self):
        blocks = [
            _text_block("a", 0),
            _image_block(1),
            _text_block("b", 2),
        ]
        chunks = chunk_blocks(blocks, doc_id="doc1")
        assert all(c.total_chunks == len(chunks) for c in chunks)

    def test_chunk_ids_are_sequential_and_unique(self):
        blocks = [
            _text_block("a", 0),
            _image_block(1),
            _text_block("b", 2),
            _image_block(3),
        ]
        chunks = chunk_blocks(blocks, doc_id="doc1")
        ids = [c.chunk_id for c in chunks]
        assert ids == sorted(ids)
        assert len(set(ids)) == len(ids)
