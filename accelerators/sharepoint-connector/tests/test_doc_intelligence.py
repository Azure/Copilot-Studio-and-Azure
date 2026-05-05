"""Tests for DocIntelligenceClient — covers the Layout-result → Block mapping.

The real Azure SDK poller is mocked; we verify that paragraphs, tables, and
figures flow through to `blocks.Block` with correct kinds, ordering, and
bounding-polygon JSON encoding.
"""

from __future__ import annotations

import tempfile
from types import SimpleNamespace
from unittest.mock import MagicMock, patch

import pytest

from blocks import BlockKind
from config import DocIntelConfig
from doc_intelligence_client import DocIntelligenceClient, LAYOUT_SUPPORTED_EXTS


def _make_client(enabled: bool = True) -> DocIntelligenceClient:
    cfg = DocIntelConfig(
        endpoint=("https://docintel.example.com" if enabled else ""),
    )
    client = DocIntelligenceClient.__new__(DocIntelligenceClient)
    client._cfg = cfg
    client._credential = MagicMock()
    client._client = None
    return client


def _region(page: int = 1, polygon: list[float] | None = None):
    return SimpleNamespace(page_number=page, polygon=polygon or [0, 0, 10, 0, 10, 10, 0, 10])


def _paragraph(content: str, page: int = 1):
    return SimpleNamespace(content=content, bounding_regions=[_region(page)])


def _table(rows: list[list[str]], page: int = 1):
    cells = []
    for ri, row in enumerate(rows):
        for ci, cell in enumerate(row):
            cells.append(SimpleNamespace(row_index=ri, column_index=ci, content=cell))
    return SimpleNamespace(
        row_count=len(rows),
        column_count=len(rows[0]) if rows else 0,
        cells=cells,
        bounding_regions=[_region(page)],
    )


def _figure(figure_id: str = "fig1", page: int = 1, caption_text: str = ""):
    caption = SimpleNamespace(content=caption_text) if caption_text else None
    return SimpleNamespace(id=figure_id, bounding_regions=[_region(page)], caption=caption)


class TestSupportedExtensions:
    def test_includes_pdf_office_images(self):
        assert ".pdf" in LAYOUT_SUPPORTED_EXTS
        assert ".docx" in LAYOUT_SUPPORTED_EXTS
        assert ".pptx" in LAYOUT_SUPPORTED_EXTS
        assert ".xlsx" in LAYOUT_SUPPORTED_EXTS
        assert ".png" in LAYOUT_SUPPORTED_EXTS
        assert ".jpg" in LAYOUT_SUPPORTED_EXTS

    def test_excludes_plain_text_formats(self):
        # DocIntel adds no value for these; plain-text path should handle them.
        assert ".txt" not in LAYOUT_SUPPORTED_EXTS
        assert ".md" not in LAYOUT_SUPPORTED_EXTS
        assert ".csv" not in LAYOUT_SUPPORTED_EXTS


class TestEnabledGuard:
    def test_disabled_when_endpoint_empty(self):
        c = _make_client(enabled=False)
        assert c.enabled is False
        assert c.extract_blocks("nothing.pdf", ".pdf") == []

    def test_unsupported_ext_returns_empty(self):
        c = _make_client(enabled=True)
        assert c.extract_blocks("readme.txt", ".txt") == []


class TestExtractionMapping:
    def _run(self, fake_result) -> list:
        c = _make_client()
        poller = MagicMock()
        poller.result.return_value = fake_result
        inner = MagicMock()
        inner.begin_analyze_document.return_value = poller
        # get_analyze_result_figure returns an iterable of bytes chunks.
        inner.get_analyze_result_figure.return_value = iter([b"\x89PNG"])
        c._client = inner

        # Write a small file so `open(path, 'rb')` works inside extract_blocks.
        with tempfile.NamedTemporaryFile(delete=False, suffix=".pdf") as tf:
            tf.write(b"fake-pdf-bytes")
            path = tf.name
        return c.extract_blocks(path, ".pdf")

    def test_paragraphs_become_text_blocks(self):
        fake = SimpleNamespace(
            paragraphs=[_paragraph("Para 1"), _paragraph("Para 2")],
            tables=None,
            figures=None,
        )
        blocks = self._run(fake)
        assert [b.kind for b in blocks] == [BlockKind.TEXT, BlockKind.TEXT]
        assert blocks[0].text == "Para 1"
        assert blocks[1].text == "Para 2"
        # Order numbers are assigned sequentially.
        assert blocks[0].order == 0
        assert blocks[1].order == 1

    def test_table_serialised_as_tab_separated_text(self):
        fake = SimpleNamespace(
            paragraphs=[],
            tables=[_table([["A", "B"], ["1", "2"]])],
            figures=None,
        )
        blocks = self._run(fake)
        assert len(blocks) == 1
        assert blocks[0].kind == BlockKind.TEXT
        assert blocks[0].text.startswith("[TABLE]")
        assert "A\tB" in blocks[0].text
        assert "1\t2" in blocks[0].text

    def test_figures_become_image_blocks_with_crops(self):
        fake = SimpleNamespace(
            paragraphs=[],
            tables=None,
            figures=[_figure("fig1", caption_text="Sales chart")],
        )
        blocks = self._run(fake)
        assert len(blocks) == 1
        assert blocks[0].kind == BlockKind.IMAGE
        assert blocks[0].text == "Sales chart"       # caption
        assert blocks[0].image_bytes == b"\x89PNG"   # fetched crop
        assert blocks[0].location.page_number == 1

    def test_bounding_polygon_json_encoded(self):
        fake = SimpleNamespace(
            paragraphs=[_paragraph("Hi")],
            tables=None,
            figures=None,
        )
        blocks = self._run(fake)
        # Polygon pairs re-emitted as JSON list-of-lists.
        assert blocks[0].location.bounding_polygons.startswith("[[")

    def test_service_error_returns_empty(self):
        c = _make_client()
        inner = MagicMock()
        inner.begin_analyze_document.side_effect = RuntimeError("DocIntel down")
        c._client = inner
        with tempfile.NamedTemporaryFile(delete=False, suffix=".pdf") as tf:
            tf.write(b"fake")
            path = tf.name
        assert c.extract_blocks(path, ".pdf") == []
