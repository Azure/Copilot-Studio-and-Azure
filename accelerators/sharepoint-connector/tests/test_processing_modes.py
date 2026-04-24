"""Tests for processing mode resolution (full / since-date / since-last-run)."""

import os
from datetime import datetime, timezone
from unittest.mock import patch, MagicMock

import pytest

from config import FunctionProcessingMode, ProcessingMode, load_config

_REQUIRED_ENV = {
    "TENANT_ID": "test-tenant-id",
    "SHAREPOINT_SITE_URL": "https://contoso.sharepoint.com/sites/TestSite",
    "SEARCH_ENDPOINT": "https://my-search.search.windows.net",
    "MULTIMODAL_ENDPOINT": "https://my-foundry.cognitiveservices.azure.com",
}


class TestProcessingModeEnvParsing:

    def test_default_is_since_last_run(self):
        with patch.dict(os.environ, _REQUIRED_ENV, clear=True):
            cfg = load_config()
        assert cfg.indexer.processing_mode == ProcessingMode.SINCE_LAST_RUN
        assert cfg.indexer.start_date is None

    def test_full_mode(self):
        env = {**_REQUIRED_ENV, "PROCESSING_MODE": "full"}
        with patch.dict(os.environ, env, clear=True):
            cfg = load_config()
        assert cfg.indexer.processing_mode == ProcessingMode.FULL

    def test_since_date_mode_requires_start_date(self):
        env = {**_REQUIRED_ENV, "PROCESSING_MODE": "since-date"}
        with patch.dict(os.environ, env, clear=True):
            with pytest.raises(EnvironmentError, match="START_DATE"):
                load_config()

    def test_since_date_mode_with_valid_date(self):
        env = {
            **_REQUIRED_ENV,
            "PROCESSING_MODE": "since-date",
            "START_DATE": "2026-01-15T00:00:00Z",
        }
        with patch.dict(os.environ, env, clear=True):
            cfg = load_config()
        assert cfg.indexer.processing_mode == ProcessingMode.SINCE_DATE
        assert cfg.indexer.start_date == datetime(2026, 1, 15, tzinfo=timezone.utc)

    def test_since_date_mode_rejects_bad_date(self):
        env = {
            **_REQUIRED_ENV,
            "PROCESSING_MODE": "since-date",
            "START_DATE": "not-a-date",
        }
        with patch.dict(os.environ, env, clear=True):
            with pytest.raises(EnvironmentError, match="ISO-8601"):
                load_config()

    def test_unknown_mode_raises(self):
        env = {**_REQUIRED_ENV, "PROCESSING_MODE": "whatever"}
        with patch.dict(os.environ, env, clear=True):
            with pytest.raises(EnvironmentError, match="PROCESSING_MODE"):
                load_config()

    def test_legacy_incremental_minutes_zero_maps_to_full(self):
        env = {**_REQUIRED_ENV, "INCREMENTAL_MINUTES": "0"}
        with patch.dict(os.environ, env, clear=True):
            cfg = load_config()
        assert cfg.indexer.processing_mode == ProcessingMode.FULL

    def test_legacy_incremental_minutes_non_zero_maps_to_since_last_run(self):
        env = {**_REQUIRED_ENV, "INCREMENTAL_MINUTES": "65"}
        with patch.dict(os.environ, env, clear=True):
            cfg = load_config()
        assert cfg.indexer.processing_mode == ProcessingMode.SINCE_LAST_RUN

    def test_explicit_mode_wins_over_legacy(self):
        env = {
            **_REQUIRED_ENV,
            "PROCESSING_MODE": "full",
            "INCREMENTAL_MINUTES": "65",
        }
        with patch.dict(os.environ, env, clear=True):
            cfg = load_config()
        assert cfg.indexer.processing_mode == ProcessingMode.FULL


class TestFunctionProcessingMode:

    def test_default_is_queue(self):
        with patch.dict(os.environ, _REQUIRED_ENV, clear=True):
            cfg = load_config()
        assert cfg.indexer.function_processing_mode == FunctionProcessingMode.QUEUE

    def test_inline_override(self):
        env = {**_REQUIRED_ENV, "FUNCTION_PROCESSING_MODE": "inline"}
        with patch.dict(os.environ, env, clear=True):
            cfg = load_config()
        assert cfg.indexer.function_processing_mode == FunctionProcessingMode.INLINE


class TestResolveModifiedSince:
    """_resolve_modified_since in indexer.py wires the mode → timestamp decision."""

    def _load_cfg(self, env_overrides: dict):
        env = {**_REQUIRED_ENV, **env_overrides}
        with patch.dict(os.environ, env, clear=True):
            return load_config()

    def test_full_returns_none(self):
        from indexer import _resolve_modified_since
        cfg = self._load_cfg({"PROCESSING_MODE": "full"})
        assert _resolve_modified_since(cfg, datetime.now(timezone.utc)) is None

    def test_since_date_returns_configured(self):
        from indexer import _resolve_modified_since
        cfg = self._load_cfg({
            "PROCESSING_MODE": "since-date",
            "START_DATE": "2026-01-15T00:00:00Z",
        })
        ts = _resolve_modified_since(cfg, datetime.now(timezone.utc))
        assert ts == datetime(2026, 1, 15, tzinfo=timezone.utc)

    def test_since_last_run_reads_watermark(self):
        from indexer import _resolve_modified_since
        cfg = self._load_cfg({"PROCESSING_MODE": "since-last-run"})
        fake_watermark = datetime(2026, 3, 1, tzinfo=timezone.utc)

        with patch("indexer.get_store") as mock_get_store:
            mock_store = MagicMock()
            mock_store.read_watermark.return_value = fake_watermark
            mock_get_store.return_value = mock_store
            ts = _resolve_modified_since(cfg, datetime.now(timezone.utc))

        assert ts == fake_watermark

    def test_since_last_run_first_run_returns_none(self):
        from indexer import _resolve_modified_since
        cfg = self._load_cfg({"PROCESSING_MODE": "since-last-run"})

        with patch("indexer.get_store") as mock_get_store:
            mock_store = MagicMock()
            mock_store.read_watermark.return_value = None
            mock_get_store.return_value = mock_store
            ts = _resolve_modified_since(cfg, datetime.now(timezone.utc))

        assert ts is None
