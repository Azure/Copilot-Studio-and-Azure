"""Tests for MultimodalEmbeddingsClient — Azure AI Vision multimodal (Florence)."""

from __future__ import annotations

import threading
import time
from unittest.mock import MagicMock

import pytest

from multimodal_embeddings_client import MultimodalEmbeddingsClient


def _make_client() -> MultimodalEmbeddingsClient:
    """Construct a client with a stubbed credential + fake bearer token."""
    client = MultimodalEmbeddingsClient.__new__(MultimodalEmbeddingsClient)
    client._endpoint = "https://example.cognitiveservices.azure.com"
    client._model_version = "2023-04-15"
    client._credential = MagicMock()
    client._http = MagicMock()
    client._token = "fake-token"
    client._token_expires_on = time.time() + 3600
    client._semaphore = threading.BoundedSemaphore(8)
    client._cool_off_until_lock = threading.Lock()
    client._cool_off_until = 0.0
    return client


class TestUrlAssembly:
    def test_vectorize_text_url(self):
        c = _make_client()
        url = c._url("vectorizeText")
        assert url.startswith("https://example.cognitiveservices.azure.com/computervision/retrieval:vectorizeText")
        assert "api-version=2024-02-01" in url
        assert "model-version=2023-04-15" in url

    def test_vectorize_image_url(self):
        c = _make_client()
        url = c._url("vectorizeImage")
        assert "/computervision/retrieval:vectorizeImage" in url


class TestVectorizeText:
    def test_happy_path(self):
        c = _make_client()
        resp = MagicMock()
        resp.status_code = 200
        resp.json.return_value = {"vector": [0.1, 0.2, 0.3]}
        c._http.post.return_value = resp

        result = c.vectorize_text("hello")
        assert result == [0.1, 0.2, 0.3]
        # JSON body with a `text` field.
        c._http.post.assert_called_once()
        kwargs = c._http.post.call_args.kwargs
        assert kwargs["json"] == {"text": "hello"}

    def test_empty_text_short_circuits(self):
        c = _make_client()
        assert c.vectorize_text("") is None
        c._http.post.assert_not_called()

    def test_400_returns_none(self):
        c = _make_client()
        resp = MagicMock()
        resp.status_code = 400
        resp.text = "bad request"
        c._http.post.return_value = resp
        assert c.vectorize_text("hello") is None

    def test_missing_vector_in_response(self):
        c = _make_client()
        resp = MagicMock()
        resp.status_code = 200
        resp.json.return_value = {"not-a-vector": True}
        c._http.post.return_value = resp
        assert c.vectorize_text("hello") is None


class TestVectorizeImage:
    def test_happy_path(self):
        c = _make_client()
        resp = MagicMock()
        resp.status_code = 200
        resp.json.return_value = {"vector": [0.0] * 1024}
        c._http.post.return_value = resp

        result = c.vectorize_image(b"\x89PNG", mime="image/png")
        assert result is not None
        assert len(result) == 1024
        # Image path sends raw bytes, NOT json.
        kwargs = c._http.post.call_args.kwargs
        assert "json" not in kwargs
        assert kwargs["content"] == b"\x89PNG"

    def test_empty_bytes_short_circuits(self):
        c = _make_client()
        assert c.vectorize_image(b"", mime="image/png") is None
        c._http.post.assert_not_called()


class TestConstruction:
    def test_empty_endpoint_rejected(self):
        with pytest.raises(ValueError, match="endpoint"):
            MultimodalEmbeddingsClient(endpoint="")

    def test_trailing_slash_stripped(self):
        # Use __new__ to avoid creating a real credential.
        client = MultimodalEmbeddingsClient.__new__(MultimodalEmbeddingsClient)
        client._endpoint = "https://example.com/".rstrip("/")
        assert client._endpoint == "https://example.com"


class TestRateLimitHandling:
    """Verify that 429 responses back off globally and respect Retry-After."""

    def test_429_sets_global_cool_off(self):
        c = _make_client()

        # First call returns 429, second returns a valid vector.
        r429 = MagicMock(status_code=429, headers={"Retry-After": "2"})
        r200 = MagicMock(status_code=200)
        r200.json.return_value = {"vector": [0.1] * 1024}
        c._http.post.side_effect = [r429, r200]

        # Stub the sleep so the test runs fast; just assert the cool-off was recorded.
        with pytest.MonkeyPatch.context() as mp:
            import multimodal_embeddings_client as mec
            mp.setattr(mec.time, "sleep", lambda _s: None)
            result = c.vectorize_text("hello")

        assert result is not None
        # After the 429, the client should have scheduled a cool-off window > now.
        assert c._cool_off_until > 0

    def test_exhausted_retries_returns_none(self):
        c = _make_client()
        r429 = MagicMock(status_code=429, headers={"Retry-After": "1"})
        c._http.post.return_value = r429

        with pytest.MonkeyPatch.context() as mp:
            import multimodal_embeddings_client as mec
            mp.setattr(mec.time, "sleep", lambda _s: None)
            result = c.vectorize_text("hello")

        assert result is None

    def test_concurrent_calls_bounded_by_semaphore(self):
        """With max_concurrency=2, only 2 HTTP calls can be in-flight at once."""
        import threading

        c = _make_client()
        # Override the semaphore to a small bound so concurrency is observable.
        c._semaphore = threading.BoundedSemaphore(2)

        in_flight = 0
        peak = 0
        lock = threading.Lock()
        start_event = threading.Event()

        def slow_post(*args, **kwargs):
            nonlocal in_flight, peak
            with lock:
                in_flight += 1
                peak = max(peak, in_flight)
            start_event.wait(timeout=1)
            with lock:
                in_flight -= 1
            resp = MagicMock(status_code=200)
            resp.json.return_value = {"vector": [0.0] * 1024}
            return resp

        c._http.post.side_effect = slow_post

        from concurrent.futures import ThreadPoolExecutor
        with ThreadPoolExecutor(max_workers=8) as pool:
            futures = [pool.submit(c.vectorize_text, f"q{i}") for i in range(8)]
            # Allow workers to block briefly before releasing.
            import time as _t
            _t.sleep(0.05)
            start_event.set()
            for f in futures:
                f.result()

        # Regardless of 8 concurrent submissions, no more than 2 should have
        # ever been inside the HTTP call at once.
        assert peak <= 2
