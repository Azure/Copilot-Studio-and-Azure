"""
Per-user security trimming for AI Search queries.

Responsibilities:
  1. Validate an Entra ID bearer token (JWKS lookup, audience + issuer + expiry).
  2. Resolve the caller's transitive group memberships via Microsoft Graph
     (using the Function App's managed identity — the app needs the
     GroupMember.Read.All application permission).
  3. Build an OData filter against the index's `permission_ids` collection.
  4. A small TTL cache avoids hammering Graph for a single user within a
     short-lived conversation.

Called from the `/api/search` HTTP endpoint in function_app.py.
"""

from __future__ import annotations

import logging
import os
import time
from dataclasses import dataclass
from threading import RLock
from typing import Any

import httpx
from azure.identity import DefaultAzureCredential

logger = logging.getLogger(__name__)

GRAPH_BASE = "https://graph.microsoft.com/v1.0"
GRAPH_SCOPE = "https://graph.microsoft.com/.default"

# How long (seconds) to cache resolved group memberships per user.
_IDENTITY_CACHE_TTL = int(os.getenv("IDENTITY_CACHE_TTL_SECONDS", "300"))

# Optional: comma-separated object IDs that should be implicitly included in
# every query's identity list (e.g. a tenant-wide "everyone" group, or a
# fallback for files granted via SharePoint-only mechanisms). Read from env.
_ALWAYS_ALLOWED_IDS = [
    x.strip() for x in os.getenv("ALWAYS_ALLOWED_IDS", "").split(",") if x.strip()
]


# ---------------------------------------------------------------------------
# Errors
# ---------------------------------------------------------------------------


class TokenValidationError(Exception):
    """Raised when a caller's bearer token cannot be validated."""


# ---------------------------------------------------------------------------
# JWT validation
# ---------------------------------------------------------------------------


@dataclass
class ValidatedUser:
    oid: str                       # user's Entra object ID
    tid: str                       # tenant ID
    upn: str | None                # optional UPN / preferred_username
    raw_claims: dict[str, Any]


def _issuers(tenant_id: str) -> list[str]:
    return [
        f"https://login.microsoftonline.com/{tenant_id}/v2.0",
        f"https://sts.windows.net/{tenant_id}/",
    ]


def validate_user_token(
    bearer: str,
    audience: str,
    tenant_id: str,
) -> ValidatedUser:
    """
    Validate an Entra bearer token. Raises TokenValidationError on failure.

    - Signature checked against Entra's JWKS for the given tenant.
    - Audience must match the configured API app registration.
    - Issuer must be Entra v1 or v2 for this tenant.
    - Token must not be expired (PyJWT enforces this by default).
    """
    if not bearer:
        raise TokenValidationError("Missing bearer token")
    if bearer.lower().startswith("bearer "):
        bearer = bearer.split(" ", 1)[1]

    try:
        import jwt  # type: ignore
        from jwt import PyJWKClient  # type: ignore
    except ImportError as e:  # pragma: no cover
        raise TokenValidationError("PyJWT with crypto extra not installed") from e

    try:
        jwks_url = f"https://login.microsoftonline.com/{tenant_id}/discovery/v2.0/keys"
        jwks_client = _get_jwks_client(jwks_url)
        signing_key = jwks_client.get_signing_key_from_jwt(bearer).key

        claims = jwt.decode(
            bearer,
            signing_key,
            algorithms=["RS256"],
            audience=audience,
            issuer=_issuers(tenant_id),
            options={"require": ["exp", "iss", "aud", "oid", "tid"]},
        )
    except Exception as e:  # noqa: BLE001
        raise TokenValidationError(f"Token validation failed: {e}") from e

    oid = claims.get("oid")
    tid = claims.get("tid")
    if not oid or not tid:
        raise TokenValidationError("Token is missing required oid/tid claims")
    if tid != tenant_id:
        raise TokenValidationError(f"Token tenant {tid} does not match expected {tenant_id}")

    return ValidatedUser(
        oid=oid,
        tid=tid,
        upn=claims.get("upn") or claims.get("preferred_username"),
        raw_claims=claims,
    )


# The PyJWKClient caches keys itself but instances aren't thread-safe at init.
_jwks_lock = RLock()
_jwks_clients: dict[str, Any] = {}


def _get_jwks_client(url: str):
    import jwt  # type: ignore
    from jwt import PyJWKClient  # type: ignore  # noqa: F811
    with _jwks_lock:
        if url not in _jwks_clients:
            _jwks_clients[url] = PyJWKClient(url, cache_keys=True, lifespan=3600)
        return _jwks_clients[url]


# ---------------------------------------------------------------------------
# Graph identity resolution (managed-identity-backed)
# ---------------------------------------------------------------------------


@dataclass
class _IdentityCacheEntry:
    ids: list[str]
    expires_at: float


class GraphIdentityResolver:
    """Resolves a user's oid → [oid, group_oid_1, group_oid_2, …] via Graph.

    Uses the function's managed identity (application permission
    GroupMember.Read.All). Results are cached in-process for
    IDENTITY_CACHE_TTL_SECONDS.
    """

    def __init__(self, credential: DefaultAzureCredential | None = None):
        self._credential = credential or DefaultAzureCredential()
        self._token: str | None = None
        self._token_expires_on: float = 0.0
        self._http = httpx.Client(timeout=20.0)
        self._cache: dict[str, _IdentityCacheEntry] = {}
        self._cache_lock = RLock()

    # ------------------------------------------------------------------ #

    def _get_app_token(self) -> str:
        now = time.time()
        if self._token and now < self._token_expires_on - 60:
            return self._token
        token = self._credential.get_token(GRAPH_SCOPE)
        self._token = token.token
        self._token_expires_on = float(token.expires_on)
        return self._token

    def get_identity_ids(self, user_oid: str) -> list[str]:
        """Return [user_oid] + transitive group oids for the user."""
        with self._cache_lock:
            hit = self._cache.get(user_oid)
            if hit and hit.expires_at > time.time():
                return list(hit.ids)

        ids = [user_oid]
        try:
            token = self._get_app_token()
            headers = {"Authorization": f"Bearer {token}"}
            url = f"{GRAPH_BASE}/users/{user_oid}/transitiveMemberOf?$select=id&$top=999"
            while url:
                resp = self._http.get(url, headers=headers)
                if resp.status_code == 404:
                    logger.warning(f"User {user_oid} not found in Graph; no groups resolved")
                    break
                resp.raise_for_status()
                data = resp.json()
                for entry in data.get("value", []):
                    gid = entry.get("id")
                    if gid and gid != user_oid:
                        ids.append(gid)
                url = data.get("@odata.nextLink")
        except Exception as e:  # noqa: BLE001
            # Degrade gracefully: if Graph fails, still return [user_oid].
            # The search will still filter to docs shared directly to this user.
            logger.warning(f"Could not resolve groups for {user_oid}: {e}")

        # Always append the configured fallback IDs (e.g. tenant-wide share).
        for always in _ALWAYS_ALLOWED_IDS:
            if always not in ids:
                ids.append(always)

        dedup = list(dict.fromkeys(ids))  # preserve order, unique
        with self._cache_lock:
            self._cache[user_oid] = _IdentityCacheEntry(
                ids=dedup,
                expires_at=time.time() + _IDENTITY_CACHE_TTL,
            )
        return dedup

    def close(self) -> None:
        self._http.close()


# ---------------------------------------------------------------------------
# OData filter builder
# ---------------------------------------------------------------------------


def _escape_odata_literal(value: str) -> str:
    """Escape single quotes in an OData string literal."""
    return value.replace("'", "''")


def build_permission_filter(identity_ids: list[str]) -> str:
    """Construct an OData filter that matches any of the given identities.

    Example:
        build_permission_filter(["a", "b"]) =>
        "permission_ids/any(p: p eq 'a') or permission_ids/any(p: p eq 'b')"

    An empty list returns a filter that matches nothing — this is deliberate:
    an unauthenticated caller should never see any files.
    """
    if not identity_ids:
        return "permission_ids/any(p: p eq '__no_identity__')"
    clauses = [f"permission_ids/any(p: p eq '{_escape_odata_literal(i)}')" for i in identity_ids]
    return " or ".join(clauses)
