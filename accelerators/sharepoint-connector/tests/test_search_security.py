"""Tests for per-user security trimming: filter builder, identity cache, token validation."""

from __future__ import annotations

import datetime as dt
import os
import time
from unittest.mock import MagicMock, patch

import pytest


# ---------------------------------------------------------------------------
# build_permission_filter
# ---------------------------------------------------------------------------


class TestBuildPermissionFilter:
    def test_single_identity(self):
        from search_security import build_permission_filter
        assert build_permission_filter(["abc"]) == "permission_ids/any(p: p eq 'abc')"

    def test_multiple_identities(self):
        from search_security import build_permission_filter
        got = build_permission_filter(["a", "b", "c"])
        assert "permission_ids/any(p: p eq 'a')" in got
        assert "permission_ids/any(p: p eq 'b')" in got
        assert "permission_ids/any(p: p eq 'c')" in got
        assert got.count(" or ") == 2

    def test_empty_list_matches_nothing(self):
        """Secure default — an unauthenticated caller sees no files."""
        from search_security import build_permission_filter
        got = build_permission_filter([])
        # Must contain a sentinel that cannot match any real object ID.
        assert "__no_identity__" in got

    def test_single_quote_in_id_is_escaped(self):
        """OData literals escape single quotes by doubling them."""
        from search_security import build_permission_filter
        got = build_permission_filter(["o'malley"])
        # Raw quote becomes '' in the OData literal
        assert "o''malley" in got


# ---------------------------------------------------------------------------
# GraphIdentityResolver — caching + error handling
# ---------------------------------------------------------------------------


class TestGraphIdentityResolver:
    def _make_resolver(self, http_client):
        """Build a resolver with injected httpx client + stubbed credential."""
        from search_security import GraphIdentityResolver
        r = GraphIdentityResolver(credential=MagicMock())
        r._http = http_client
        r._token = "fake-token"
        r._token_expires_on = time.time() + 3600
        # Clear any module-level state left over from other tests
        r._cache.clear()
        return r

    def test_returns_user_oid_plus_groups(self):
        http = MagicMock()
        resp = MagicMock()
        resp.status_code = 200
        resp.json.return_value = {
            "value": [{"id": "group-a"}, {"id": "group-b"}],
        }
        http.get.return_value = resp

        r = self._make_resolver(http)
        ids = r.get_identity_ids("user-1")
        assert ids == ["user-1", "group-a", "group-b"]

    def test_user_not_found_returns_oid_only(self):
        http = MagicMock()
        resp = MagicMock()
        resp.status_code = 404
        http.get.return_value = resp

        r = self._make_resolver(http)
        ids = r.get_identity_ids("unknown-user")
        assert ids == ["unknown-user"]

    def test_graph_error_degrades_gracefully(self):
        http = MagicMock()
        http.get.side_effect = RuntimeError("graph is down")

        r = self._make_resolver(http)
        # Must not raise — degraded mode returns just the user oid.
        ids = r.get_identity_ids("user-x")
        assert ids == ["user-x"]

    def test_results_cached_within_ttl(self):
        http = MagicMock()
        resp = MagicMock()
        resp.status_code = 200
        resp.json.return_value = {"value": [{"id": "g1"}]}
        http.get.return_value = resp

        r = self._make_resolver(http)
        r.get_identity_ids("user-c")
        r.get_identity_ids("user-c")
        r.get_identity_ids("user-c")
        # Only the first call should hit Graph.
        assert http.get.call_count == 1

    def test_always_allowed_ids_are_merged_in(self):
        """The ALWAYS_ALLOWED_IDS env var seeds every resolution."""
        http = MagicMock()
        resp = MagicMock()
        resp.status_code = 200
        resp.json.return_value = {"value": [{"id": "g1"}]}
        http.get.return_value = resp

        with patch.dict(os.environ, {"ALWAYS_ALLOWED_IDS": "tenant-wide,extra-group"}):
            # Force reload of the module-level constant.
            import importlib
            import search_security
            importlib.reload(search_security)

            r = search_security.GraphIdentityResolver(credential=MagicMock())
            r._http = http
            r._token = "fake-token"
            r._token_expires_on = time.time() + 3600
            ids = r.get_identity_ids("user-d")
            assert "tenant-wide" in ids
            assert "extra-group" in ids
            assert "user-d" in ids
            assert "g1" in ids


# ---------------------------------------------------------------------------
# validate_user_token — error paths only (real JWT signing is overkill here)
# ---------------------------------------------------------------------------


class TestValidateUserToken:
    def test_empty_token_rejected(self):
        from search_security import TokenValidationError, validate_user_token
        with pytest.raises(TokenValidationError, match="Missing"):
            validate_user_token("", audience="api://xyz", tenant_id="t")

    def test_malformed_token_rejected(self):
        from search_security import TokenValidationError, validate_user_token
        with pytest.raises(TokenValidationError):
            validate_user_token("not-a-jwt", audience="api://xyz", tenant_id="t")

    def test_bearer_prefix_is_stripped(self):
        """validate_user_token accepts `Bearer <jwt>` or the raw jwt."""
        from search_security import TokenValidationError, validate_user_token
        # Bearer prefix handled; the JWT itself is still invalid so we get
        # a TokenValidationError — but not a 'Missing bearer token' one.
        with pytest.raises(TokenValidationError) as exc_info:
            validate_user_token("Bearer not-a-jwt", audience="api://xyz", tenant_id="t")
        assert "Missing" not in str(exc_info.value)


# ---------------------------------------------------------------------------
# SearchPushClient.search_with_trimming — filter construction
# ---------------------------------------------------------------------------


class TestSearchWithTrimming:
    def test_filter_is_passed_to_search(self):
        """The built OData filter reaches azure-search-documents unchanged."""
        from search_client import SearchPushClient

        client = SearchPushClient.__new__(SearchPushClient)
        client._config = MagicMock(endpoint="https://example.search.windows.net", index_name="idx")
        client._multimodal = MagicMock(endpoint="", model_version="2023-04-15")

        inner = MagicMock()
        inner.search.return_value = iter([])
        client._get_search_client = lambda: inner

        client.search_with_trimming("hello", ["u1", "g1"], top=5)

        inner.search.assert_called_once()
        kwargs = inner.search.call_args.kwargs
        assert kwargs["top"] == 5
        assert "permission_ids/any(p: p eq 'u1')" in kwargs["filter"]
        assert "permission_ids/any(p: p eq 'g1')" in kwargs["filter"]

    def test_empty_identity_list_still_filters(self):
        """Zero identities must filter to zero docs, never return everything."""
        from search_client import SearchPushClient

        client = SearchPushClient.__new__(SearchPushClient)
        client._config = MagicMock(endpoint="https://example.search.windows.net", index_name="idx")
        client._multimodal = MagicMock(endpoint="", model_version="2023-04-15")

        inner = MagicMock()
        inner.search.return_value = iter([])
        client._get_search_client = lambda: inner

        client.search_with_trimming("hello", [], top=5)

        kwargs = inner.search.call_args.kwargs
        assert "__no_identity__" in kwargs["filter"]
