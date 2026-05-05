"""
Azure AI Vision multimodal embeddings (Florence) client.

Produces 1024-dimensional vectors for either text or images. Text vectors and
image vectors share the same space, so cross-modal retrieval works natively —
a text query can retrieve both text chunks and image chunks.

REST API (via Microsoft Foundry / Azure AI Services endpoint):
  POST {endpoint}/computervision/retrieval:vectorizeText?api-version=2024-02-01&model-version=2023-04-15
  POST {endpoint}/computervision/retrieval:vectorizeImage?api-version=2024-02-01&model-version=2023-04-15

Auth: DefaultAzureCredential → bearer token for scope
https://cognitiveservices.azure.com/.default (Cognitive Services User RBAC role).

Concurrency model:
  * A module-level Semaphore bounds the number of in-flight Vision requests
    per function instance. Callers can submit as many `vectorize_*` calls as
    they like (e.g. via ThreadPoolExecutor); excess calls block on the
    semaphore until slots open up.
  * 429 responses respect the Retry-After header AND set a soft global
    cool-off that other threads check before firing new requests — so a
    rate-limit event affects all workers immediately rather than each
    rediscovering it independently.
"""

from __future__ import annotations

import logging
import os
import threading
import time

import httpx
from azure.identity import DefaultAzureCredential

logger = logging.getLogger(__name__)

_SCOPE = "https://cognitiveservices.azure.com/.default"
_API_VERSION = "2024-02-01"
_DEFAULT_MODEL_VERSION = "2023-04-15"

MULTIMODAL_DIM = 1024


class MultimodalEmbeddingsClient:
    """Calls Azure AI Vision multimodal embeddings endpoints with bounded
    concurrency and rate-limit awareness."""

    def __init__(
        self,
        endpoint: str,
        model_version: str = _DEFAULT_MODEL_VERSION,
        credential: DefaultAzureCredential | None = None,
        max_concurrency: int | None = None,
    ):
        if not endpoint:
            raise ValueError("MultimodalEmbeddingsClient requires an endpoint")
        self._endpoint = endpoint.rstrip("/")
        self._model_version = model_version
        self._credential = credential or DefaultAzureCredential()
        self._http = httpx.Client(timeout=30.0)
        self._token: str | None = None
        self._token_expires_on: float = 0.0

        # Bound in-flight requests so callers can parallelise freely without
        # overrunning the Vision endpoint's rate limit. Default 8 is safe for
        # the S1 tier (~10 TPS documented, credit-bucket in practice).
        if max_concurrency is None:
            max_concurrency = int(os.getenv("MULTIMODAL_MAX_IN_FLIGHT", "8"))
        self._semaphore = threading.BoundedSemaphore(max_concurrency)

        # Global cool-off timestamp (monotonic). When a 429 is observed, all
        # threads sleep until this time before firing their next request.
        # Enforced at semaphore-acquire time so the entire client throttles.
        self._cool_off_until_lock = threading.Lock()
        self._cool_off_until = 0.0

    # ------------------------------------------------------------------ #
    # Auth
    # ------------------------------------------------------------------ #

    def _bearer(self) -> str:
        now = time.time()
        if self._token and now < self._token_expires_on - 60:
            return self._token
        token = self._credential.get_token(_SCOPE)
        self._token = token.token
        self._token_expires_on = float(token.expires_on)
        return self._token

    def _headers(self, content_type: str) -> dict[str, str]:
        return {
            "Authorization": f"Bearer {self._bearer()}",
            "Content-Type": content_type,
        }

    def _url(self, op: str) -> str:
        return (
            f"{self._endpoint}/computervision/retrieval:{op}"
            f"?api-version={_API_VERSION}"
            f"&model-version={self._model_version}"
        )

    # ------------------------------------------------------------------ #
    # Rate-limit cool-off
    # ------------------------------------------------------------------ #

    def _wait_for_cool_off(self) -> None:
        """Sleep until any global cool-off window set by a prior 429 expires."""
        with self._cool_off_until_lock:
            deadline = self._cool_off_until
        now = time.monotonic()
        if deadline > now:
            time.sleep(deadline - now)

    def _set_cool_off(self, seconds: float) -> None:
        """Extend the global cool-off window so concurrent workers back off too."""
        seconds = max(1.0, min(seconds, 120.0))
        with self._cool_off_until_lock:
            proposed = time.monotonic() + seconds
            if proposed > self._cool_off_until:
                self._cool_off_until = proposed

    # ------------------------------------------------------------------ #
    # Public API
    # ------------------------------------------------------------------ #

    def vectorize_text(self, text: str) -> list[float] | None:
        if not text:
            return None
        return self._post(self._url("vectorizeText"), {"text": text}, "application/json")

    def vectorize_image(self, image_bytes: bytes, mime: str = "image/png") -> list[float] | None:
        if not image_bytes:
            return None
        return self._post(self._url("vectorizeImage"), image_bytes, mime)

    # ------------------------------------------------------------------ #
    # Transport
    # ------------------------------------------------------------------ #

    def _post(
        self,
        url: str,
        body,
        content_type: str,
        max_retries: int = 5,
    ) -> list[float] | None:
        with self._semaphore:
            for attempt in range(max_retries):
                self._wait_for_cool_off()

                try:
                    if content_type == "application/json":
                        resp = self._http.post(url, headers=self._headers(content_type), json=body)
                    else:
                        resp = self._http.post(url, headers=self._headers(content_type), content=body)
                except httpx.HTTPError as e:
                    wait = min(2 ** attempt, 30)
                    logger.warning(f"Vision transient error: {e}. Retrying in {wait}s")
                    time.sleep(wait)
                    continue

                if resp.status_code == 429:
                    retry_after = float(resp.headers.get("Retry-After", "5"))
                    # Propagate the back-off to every other in-flight worker.
                    self._set_cool_off(retry_after)
                    logger.warning(
                        f"Vision rate-limited (429); global cool-off {retry_after:.1f}s "
                        f"(attempt {attempt + 1}/{max_retries})"
                    )
                    continue
                if resp.status_code >= 500:
                    wait = min(2 ** attempt, 30)
                    logger.warning(f"Vision server error {resp.status_code}; retrying in {wait}s")
                    time.sleep(wait)
                    continue
                if resp.status_code >= 400:
                    logger.error(f"Vision error {resp.status_code}: {resp.text[:500]}")
                    return None

                data = resp.json()
                vector = data.get("vector")
                if isinstance(vector, list):
                    return vector
                logger.warning(f"Vision response missing `vector` field: {data}")
                return None

        logger.error(f"Vision request exhausted retries: {url}")
        return None

    def close(self) -> None:
        self._http.close()
