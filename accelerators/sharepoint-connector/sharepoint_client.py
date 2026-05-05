"""
SharePoint client using Microsoft Graph API.
Handles authentication via DefaultAzureCredential (managed identity)
or MSAL client-credentials (fallback when CLIENT_SECRET is set).

Provides methods to:
- Discover site and drive IDs
- List files in document libraries
- Download file content
- Retrieve per-item permissions for security trimming
"""

import logging
import time
from datetime import datetime, timedelta, timezone
from dataclasses import dataclass
from typing import Any

import httpx
from azure.identity import DefaultAzureCredential, ClientSecretCredential
from azure.core.credentials import TokenCredential

from config import EntraConfig, SharePointConfig

logger = logging.getLogger(__name__)

GRAPH_BASE = "https://graph.microsoft.com/v1.0"
GRAPH_BETA = "https://graph.microsoft.com/beta"
GRAPH_SCOPE = "https://graph.microsoft.com/.default"


@dataclass
class SharePointFile:
    """Represents a file retrieved from SharePoint."""
    id: str
    name: str
    size: int
    web_url: str
    drive_id: str
    last_modified: datetime
    created_by: str
    modified_by: str
    content_type: str
    drive_name: str = ""
    content: bytes | None = None
    permissions: list[str] | None = None


class SharePointClient:
    """Client for accessing SharePoint via Microsoft Graph API."""

    def __init__(self, entra: EntraConfig, sharepoint: SharePointConfig):
        self._entra = entra
        self._sp = sharepoint

        # Build credential: client secret → ClientSecretCredential, else DefaultAzureCredential
        if entra.client_secret:
            logger.info("SharePoint client: using client-secret credential")
            self._credential: TokenCredential = ClientSecretCredential(
                tenant_id=entra.tenant_id,
                client_id=entra.client_id,
                client_secret=entra.client_secret,
            )
        else:
            logger.info("SharePoint client: using DefaultAzureCredential (managed identity)")
            self._credential = DefaultAzureCredential()

        self._token: str | None = None
        self._token_expiry: datetime | None = None
        self._site_id: str | None = None
        self._http = httpx.Client(timeout=120.0)

    def _get_token(self) -> str:
        """Acquire or refresh the access token via azure-identity."""
        now = datetime.now(timezone.utc)
        if self._token and self._token_expiry and now < self._token_expiry:
            return self._token

        token = self._credential.get_token(GRAPH_SCOPE)
        self._token = token.token
        # expires_on is a UTC epoch timestamp
        self._token_expiry = datetime.fromtimestamp(token.expires_on, tz=timezone.utc) - timedelta(seconds=60)
        logger.info("Acquired new Graph API access token")
        return self._token

    def _headers(self) -> dict[str, str]:
        return {
            "Authorization": f"Bearer {self._get_token()}",
            "Content-Type": "application/json",
        }

    def _get(self, url: str, params: dict | None = None) -> dict[str, Any]:
        """Make a GET request to Graph API with retry on 429/5xx."""
        max_retries = 5
        for attempt in range(max_retries):
            resp = self._http.get(url, headers=self._headers(), params=params)
            if resp.status_code == 429:
                retry_after = int(resp.headers.get("Retry-After", 5))
                logger.warning(f"Rate limited (429). Retrying in {retry_after}s (attempt {attempt + 1}/{max_retries})")
                time.sleep(retry_after)
                continue
            if resp.status_code >= 500:
                logger.warning(f"Server error {resp.status_code}. Retrying (attempt {attempt + 1}/{max_retries})")
                time.sleep(2 ** attempt)
                continue
            resp.raise_for_status()
            return resp.json()
        raise RuntimeError(f"Graph API request failed after {max_retries} retries: {url}")

    def _get_all_pages(self, url: str, params: dict | None = None) -> list[dict]:
        """Follow @odata.nextLink to get all pages of results."""
        all_items: list[dict] = []
        while url:
            data = self._get(url, params)
            all_items.extend(data.get("value", []))
            url = data.get("@odata.nextLink")
            params = None  # nextLink includes params already
        return all_items

    # ------------------------------------------------------------------
    # Site discovery
    # ------------------------------------------------------------------

    def get_site_id(self) -> str:
        """Resolve the SharePoint site URL to a Graph site ID."""
        if self._site_id:
            return self._site_id

        hostname = self._sp.hostname
        site_path = self._sp.site_path

        url = f"{GRAPH_BASE}/sites/{hostname}:{site_path}"
        data = self._get(url)
        self._site_id = data["id"]
        logger.info(f"Resolved site ID: {self._site_id}")
        return self._site_id

    # ------------------------------------------------------------------
    # Drive / library discovery
    # ------------------------------------------------------------------

    def get_drives(self) -> list[dict]:
        """List all document libraries (drives) in the site."""
        site_id = self.get_site_id()
        url = f"{GRAPH_BASE}/sites/{site_id}/drives"
        drives = self._get_all_pages(url)
        logger.info(f"Found {len(drives)} document libraries")
        return drives

    def get_target_drives(self) -> list[dict]:
        """Get drives to index based on config. Returns all if no filter specified."""
        all_drives = self.get_drives()
        if not self._sp.libraries:
            return all_drives

        target_names = {lib.lower() for lib in self._sp.libraries}
        filtered = [d for d in all_drives if d.get("name", "").lower() in target_names]
        logger.info(f"Filtered to {len(filtered)} target libraries: {[d['name'] for d in filtered]}")
        return filtered

    # ------------------------------------------------------------------
    # File listing
    # ------------------------------------------------------------------

    def list_files(
        self,
        drive_id: str,
        folder_path: str = "root",
        modified_since: datetime | None = None,
        extensions: list[str] | None = None,
    ) -> list[dict]:
        """
        Recursively list all files in a drive/folder.
        Optionally filter by last modified date and file extension.
        """
        url = f"{GRAPH_BASE}/drives/{drive_id}/root/children"
        if folder_path and folder_path != "root":
            url = f"{GRAPH_BASE}/drives/{drive_id}/root:/{folder_path}:/children"

        all_items = self._get_all_pages(url)
        files: list[dict] = []

        for item in all_items:
            if "folder" in item:
                # Recurse into subfolders
                subfolder = item.get("parentReference", {}).get("path", "").split("root:")[-1].lstrip("/")
                subfolder_path = f"{subfolder}/{item['name']}" if subfolder else item["name"]
                files.extend(self.list_files(drive_id, subfolder_path, modified_since, extensions))
            elif "file" in item:
                # Filter by extension
                name = item.get("name", "")
                if extensions:
                    ext = "." + name.rsplit(".", 1)[-1].lower() if "." in name else ""
                    if ext not in extensions:
                        continue

                # Filter by modification time
                if modified_since:
                    last_mod_str = item.get("lastModifiedDateTime", "")
                    if last_mod_str:
                        last_mod = datetime.fromisoformat(last_mod_str.replace("Z", "+00:00"))
                        if last_mod < modified_since:
                            continue

                files.append(item)

        return files

    def list_all_files(
        self,
        modified_since: datetime | None = None,
        extensions: list[str] | None = None,
        root_paths: list[str] | None = None,
    ) -> list[dict]:
        """List files across all target drives.

        When `root_paths` is empty, every target drive is scanned from its
        root. When it contains folder paths (relative to drive root), each
        drive is scanned only under those folders — useful for scoping the
        indexer to a subset of the library.
        """
        drives = self.get_target_drives()
        all_files: list[dict] = []
        folders = root_paths or ["root"]

        for drive in drives:
            drive_id = drive["id"]
            drive_name = drive.get("name", drive_id)
            for folder in folders:
                files = self.list_files(drive_id, folder, modified_since, extensions)
                logger.info(
                    f"Drive '{drive_name}' folder '{folder}': found {len(files)} files"
                )
                for f in files:
                    f["_drive_id"] = drive_id
                    f["_drive_name"] = drive_name
                all_files.extend(files)

        logger.info(f"Total files to index: {len(all_files)}")
        return all_files

    # ------------------------------------------------------------------ #
    # Delta-query listing — captures additions, modifications AND deletions
    # ------------------------------------------------------------------ #

    def list_changes_via_delta(
        self,
        drive_id: str,
        delta_token: str | None,
        extensions: list[str] | None = None,
    ) -> tuple[list[dict], list[str], str | None]:
        """Enumerate changes on a drive via the Graph delta query.

        Args:
            drive_id: Drive to monitor.
            delta_token: Previous delta token (use the full @odata.deltaLink URL
                OR just the token). Pass None on first run to get all items.
            extensions: Optional extension filter (applied client-side).

        Returns:
            (modified_items, deleted_item_ids, next_delta_token)

            * modified_items: new/modified file dicts with `_drive_id` added.
            * deleted_item_ids: SharePoint item IDs that have been deleted.
            * next_delta_token: the full @odata.deltaLink URL to persist for
              the next run. None if the server didn't return one (rare; treat
              as "retry full listing next time").
        """
        if delta_token:
            url = delta_token if delta_token.startswith("http") else (
                f"{GRAPH_BASE}/drives/{drive_id}/root/delta?token={delta_token}"
            )
        else:
            url = f"{GRAPH_BASE}/drives/{drive_id}/root/delta"

        modified: list[dict] = []
        deleted: list[str] = []
        next_token: str | None = None

        while url:
            data = self._get(url)
            for item in data.get("value", []):
                # Folders show up in delta too; skip them for indexing purposes.
                if "folder" in item:
                    continue

                if "deleted" in item:
                    # Soft or hard delete — either way the item is gone from
                    # SharePoint's perspective.
                    deleted.append(item["id"])
                    continue

                if "file" not in item:
                    continue

                name = item.get("name", "")
                if extensions:
                    ext = "." + name.rsplit(".", 1)[-1].lower() if "." in name else ""
                    if ext not in extensions:
                        continue

                item["_drive_id"] = drive_id
                modified.append(item)

            # Pagination or end-of-stream
            if "@odata.nextLink" in data:
                url = data["@odata.nextLink"]
            elif "@odata.deltaLink" in data:
                next_token = data["@odata.deltaLink"]
                url = None
            else:
                url = None

        return modified, deleted, next_token

    def list_changes_all_drives(
        self,
        delta_tokens: dict[str, str] | None = None,
        extensions: list[str] | None = None,
    ) -> tuple[list[dict], list[str], dict[str, str]]:
        """Run `list_changes_via_delta` across every target drive.

        Returns:
            (all_modified, all_deleted_item_ids, new_delta_tokens_by_drive)
        """
        delta_tokens = delta_tokens or {}
        drives = self.get_target_drives()
        all_modified: list[dict] = []
        all_deleted: list[str] = []
        new_tokens: dict[str, str] = {}

        for drive in drives:
            drive_id = drive["id"]
            drive_name = drive.get("name", drive_id)
            token = delta_tokens.get(drive_id)
            try:
                modified, deleted, next_token = self.list_changes_via_delta(
                    drive_id, token, extensions
                )
            except Exception as e:  # noqa: BLE001
                logger.warning(f"Delta query failed for drive '{drive_name}': {e}")
                continue

            # Propagate drive_name metadata for UI / logging.
            for f in modified:
                f["_drive_name"] = drive_name

            logger.info(
                f"Drive '{drive_name}' delta: {len(modified)} modified, "
                f"{len(deleted)} deleted"
            )
            all_modified.extend(modified)
            all_deleted.extend(deleted)
            if next_token:
                new_tokens[drive_id] = next_token

        return all_modified, all_deleted, new_tokens

    # ------------------------------------------------------------------
    # File download
    # ------------------------------------------------------------------

    def download_file(self, drive_id: str, item_id: str) -> bytes:
        """Download file content fully into memory. Use download_file_to_path for large files."""
        url = f"{GRAPH_BASE}/drives/{drive_id}/items/{item_id}/content"
        max_retries = 5
        for attempt in range(max_retries):
            resp = self._http.get(url, headers=self._headers(), follow_redirects=True)
            if resp.status_code == 429:
                retry_after = int(resp.headers.get("Retry-After", 5))
                logger.warning(f"Download rate limited (429). Retrying in {retry_after}s")
                time.sleep(retry_after)
                continue
            if resp.status_code >= 500:
                wait = min(2 ** attempt, 30)
                logger.warning(f"Download server error {resp.status_code}. Retrying in {wait}s")
                time.sleep(wait)
                continue
            resp.raise_for_status()
            return resp.content
        raise RuntimeError(f"Download failed after {max_retries} retries: {item_id}")

    def download_file_to_path(
        self,
        drive_id: str,
        item_id: str,
        dest_path: str,
        chunk_size: int = 4 * 1024 * 1024,
    ) -> int:
        """
        Stream file content from SharePoint directly to a local path.
        Memory-bounded regardless of file size.

        Returns the number of bytes written.
        """
        url = f"{GRAPH_BASE}/drives/{drive_id}/items/{item_id}/content"
        max_retries = 5
        for attempt in range(max_retries):
            try:
                with self._http.stream(
                    "GET", url, headers=self._headers(), follow_redirects=True
                ) as resp:
                    if resp.status_code == 429:
                        retry_after = int(resp.headers.get("Retry-After", 5))
                        logger.warning(f"Download rate limited (429). Retrying in {retry_after}s")
                        time.sleep(retry_after)
                        continue
                    if resp.status_code >= 500:
                        wait = min(2 ** attempt, 30)
                        logger.warning(f"Download server error {resp.status_code}. Retrying in {wait}s")
                        time.sleep(wait)
                        continue
                    resp.raise_for_status()
                    total = 0
                    with open(dest_path, "wb") as f:
                        for chunk in resp.iter_bytes(chunk_size=chunk_size):
                            f.write(chunk)
                            total += len(chunk)
                    return total
            except httpx.HTTPError as e:
                wait = min(2 ** attempt, 30)
                logger.warning(f"Download transient error: {e}. Retrying in {wait}s")
                time.sleep(wait)
        raise RuntimeError(f"Streaming download failed after {max_retries} retries: {item_id}")

    # ------------------------------------------------------------------
    # Permissions (for security trimming)
    # ------------------------------------------------------------------

    def get_item_permissions(self, drive_id: str, item_id: str) -> list[str]:
        """
        Retrieve permission identity IDs for a file.
        Returns a list of Entra object IDs (users/groups) that have access.
        """
        url = f"{GRAPH_BETA}/drives/{drive_id}/items/{item_id}/permissions"
        try:
            permissions = self._get_all_pages(url)
        except Exception as e:
            logger.warning(f"Could not retrieve permissions for {item_id}: {e}")
            return []

        identity_ids: list[str] = []
        for perm in permissions:
            granted = perm.get("grantedToV2") or perm.get("grantedTo") or {}
            for identity_type in ("user", "group", "application"):
                identity = granted.get(identity_type)
                if identity and identity.get("id"):
                    identity_ids.append(identity["id"])

            # Also check grantedToIdentitiesV2 for link-shared items
            for identity_set in perm.get("grantedToIdentitiesV2", perm.get("grantedToIdentities", [])):
                for identity_type in ("user", "group", "application"):
                    identity = identity_set.get(identity_type)
                    if identity and identity.get("id"):
                        identity_ids.append(identity["id"])

        return list(set(identity_ids))

    # ------------------------------------------------------------------
    # Build SharePointFile objects
    # ------------------------------------------------------------------

    def build_file_record(
        self,
        item: dict,
        include_content: bool = True,
        include_permissions: bool = True,
        drive_name: str = "",
        max_file_size: int = 500 * 1024 * 1024,  # 500 MB (was 100 MB)
    ) -> SharePointFile:
        """Convert a Graph API item dict into a SharePointFile with optional content and permissions."""
        drive_id = item.get("_drive_id", "")
        item_id = item["id"]
        file_size = item.get("size", 0)

        last_mod_str = item.get("lastModifiedDateTime", "")
        last_mod = datetime.fromisoformat(last_mod_str.replace("Z", "+00:00")) if last_mod_str else datetime.now(timezone.utc)

        content = None
        if include_content:
            if file_size > max_file_size:
                logger.warning(
                    f"Skipping download of {item.get('name', '')} — "
                    f"{file_size / (1024*1024):.1f} MB exceeds {max_file_size / (1024*1024):.0f} MB limit"
                )
            else:
                try:
                    content = self.download_file(drive_id, item_id)
                    logger.debug(f"Downloaded: {item.get('name', '')} ({len(content)} bytes)")
                except Exception as e:
                    logger.error(f"Failed to download {item.get('name', '')}: {e}")

        permissions = None
        if include_permissions:
            permissions = self.get_item_permissions(drive_id, item_id)

        return SharePointFile(
            id=item_id,
            name=item.get("name", ""),
            size=file_size,
            web_url=item.get("webUrl", ""),
            drive_id=drive_id,
            last_modified=last_mod,
            created_by=item.get("createdBy", {}).get("user", {}).get("displayName", ""),
            modified_by=item.get("lastModifiedBy", {}).get("user", {}).get("displayName", ""),
            content_type=item.get("file", {}).get("mimeType", ""),
            drive_name=drive_name,
            content=content,
            permissions=permissions,
        )

    def close(self):
        """Close the HTTP client."""
        self._http.close()
