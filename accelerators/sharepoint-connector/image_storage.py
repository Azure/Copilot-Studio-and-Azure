"""
Persists image crops extracted by Document Intelligence into blob storage,
so that Copilot Studio (or any search client) can render them as citation
thumbnails.

Container is configurable via the `IMAGES_CONTAINER` env var (default
`images`). The function's managed identity needs `Storage Blob Data Owner`
on the account — already granted by the Bicep template.
"""

from __future__ import annotations

import hashlib
import logging
import os
from dataclasses import dataclass

from azure.core.exceptions import ResourceExistsError
from azure.identity import DefaultAzureCredential
from azure.storage.blob import BlobServiceClient, ContentSettings

logger = logging.getLogger(__name__)

_DEFAULT_CONTAINER = os.getenv("IMAGES_CONTAINER", "images")


@dataclass
class UploadedImage:
    blob_url: str
    relative_path: str


class ImageStore:
    """Uploads extracted image crops to blob storage."""

    def __init__(self, account_url: str | None = None, container: str | None = None):
        storage_account = os.getenv("AzureWebJobsStorage__accountName")
        if not storage_account:
            raise EnvironmentError("AzureWebJobsStorage__accountName must be set to use ImageStore")

        self._credential = DefaultAzureCredential()
        self._account_url = account_url or f"https://{storage_account}.blob.core.windows.net"
        self._container_name = container or _DEFAULT_CONTAINER

        self._svc = BlobServiceClient(account_url=self._account_url, credential=self._credential)
        self._container = self._svc.get_container_client(self._container_name)
        try:
            self._container.create_container()
        except ResourceExistsError:
            pass
        except Exception as e:  # noqa: BLE001
            logger.warning(f"Could not ensure container {self._container_name}: {e}")

    def upload_image(
        self,
        parent_id: str,
        chunk_id: str,
        image_bytes: bytes,
        mime: str = "image/png",
    ) -> UploadedImage | None:
        """Upload one image, return its blob URL + relative path.

        Idempotent: the blob name is derived from parent_id + content hash so
        reprocessing the same file doesn't create duplicate blobs.
        """
        if not image_bytes:
            return None

        digest = hashlib.sha256(image_bytes).hexdigest()[:16]
        ext = _ext_for_mime(mime)
        # parent_id / {chunk_id}-{digest}{ext}
        rel = f"{parent_id}/{chunk_id}-{digest}{ext}"
        blob = self._container.get_blob_client(rel)
        try:
            blob.upload_blob(
                image_bytes,
                overwrite=True,
                content_settings=ContentSettings(content_type=mime),
            )
        except Exception as e:  # noqa: BLE001
            logger.warning(f"Image upload failed for {rel}: {e}")
            return None

        return UploadedImage(
            blob_url=f"{self._account_url}/{self._container_name}/{rel}",
            relative_path=f"{self._container_name}/{rel}",
        )

    def close(self) -> None:
        try:
            self._svc.close()
        except Exception:  # noqa: BLE001
            pass


def _ext_for_mime(mime: str) -> str:
    return {
        "image/png": ".png",
        "image/jpeg": ".jpg",
        "image/tiff": ".tiff",
        "image/bmp": ".bmp",
        "image/heif": ".heif",
    }.get((mime or "").lower(), ".bin")
