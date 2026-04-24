"""
Azure AI Search push client — Pattern A (unified multimodal).

Single vector field `content_embedding` (1024d, Azure AI Vision multimodal).
Text chunks embed via `vectorizeText`; image chunks embed via `vectorizeImage`.
Both live in the same vector space, so one hybrid query retrieves both.

A query-time vectorizer is registered on the index against the same Azure AI
Vision endpoint, so Copilot Studio's built-in AI Search integration can call
the index directly without any custom embedding code on the client side.
"""

from __future__ import annotations

import logging
import time
from typing import Any

from azure.core.exceptions import HttpResponseError, ResourceNotFoundError
from azure.identity import DefaultAzureCredential
from azure.search.documents import SearchClient
from azure.search.documents.indexes import SearchIndexClient
from azure.search.documents.indexes.models import (
    ComplexField,
    HnswAlgorithmConfiguration,
    SearchableField,
    SearchField,
    SearchFieldDataType,
    SearchIndex,
    SemanticConfiguration,
    SemanticField,
    SemanticPrioritizedFields,
    SemanticSearch,
    SimpleField,
    VectorSearch,
    VectorSearchProfile,
)

# AIServicesVisionVectorizer landed in azure-search-documents 11.6+. Import
# lazily so the module still loads on older SDK versions (pre-computed query
# vectors still work without a registered vectorizer).
try:
    from azure.search.documents.indexes.models import (
        AIServicesVisionParameters,
        AIServicesVisionVectorizer,
    )
    _HAS_VISION_VECTORIZER = True
except ImportError:  # pragma: no cover
    AIServicesVisionParameters = None  # type: ignore[assignment]
    AIServicesVisionVectorizer = None  # type: ignore[assignment]
    _HAS_VISION_VECTORIZER = False

from config import MultimodalConfig, SearchConfig

logger = logging.getLogger(__name__)


MULTIMODAL_DIM = 1024

_VEC_PROFILE = "sp-vector-profile"
_VEC_ALGO = "sp-hnsw"
_VEC_VECTORIZER = "sp-aivision-vectorizer"
SEMANTIC_CONFIG_NAME = "sp-semantic-config"


# ------------------------------------------------------------------ #
# Index schema
# ------------------------------------------------------------------ #

def _build_index(name: str, multimodal: MultimodalConfig) -> SearchIndex:
    fields: list[Any] = [
        SimpleField(name="chunk_id", type=SearchFieldDataType.String, key=True, filterable=True),
        SimpleField(name="parent_id", type=SearchFieldDataType.String, filterable=True),

        SearchableField(name="content_text", type=SearchFieldDataType.String),
        SearchableField(name="title", type=SearchFieldDataType.String, filterable=True, sortable=True),

        SimpleField(name="source_url", type=SearchFieldDataType.String, filterable=False),
        SimpleField(name="last_modified", type=SearchFieldDataType.DateTimeOffset, filterable=True, sortable=True),
        SimpleField(name="content_type", type=SearchFieldDataType.String, filterable=True),
        SimpleField(name="file_size", type=SearchFieldDataType.Int64, filterable=True),
        SimpleField(name="created_by", type=SearchFieldDataType.String, filterable=True),
        SimpleField(name="modified_by", type=SearchFieldDataType.String, filterable=True),
        SimpleField(name="drive_name", type=SearchFieldDataType.String, filterable=True),

        # Security trimming.
        SimpleField(
            name="permission_ids",
            type=SearchFieldDataType.Collection(SearchFieldDataType.String),
            filterable=True,
        ),

        # Multimodal metadata.
        SimpleField(name="has_image", type=SearchFieldDataType.Boolean, filterable=True),
        SimpleField(name="content_path", type=SearchFieldDataType.String, filterable=False),
        ComplexField(
            name="location_metadata",
            fields=[
                SimpleField(name="page_number", type=SearchFieldDataType.Int32, filterable=True),
                SimpleField(name="bounding_polygons", type=SearchFieldDataType.String, filterable=False),
            ],
        ),

        # Single vector field (1024d, Azure AI Vision multimodal).
        SearchField(
            name="content_embedding",
            type=SearchFieldDataType.Collection(SearchFieldDataType.Single),
            searchable=True,
            vector_search_dimensions=MULTIMODAL_DIM,
            vector_search_profile_name=_VEC_PROFILE,
        ),
    ]

    # Register Azure AI Vision as the query-time vectorizer so Copilot Studio's
    # built-in AI Search integration (and /api/search with no query_vector)
    # can turn a text query into a 1024d vector server-side. Falls back to
    # no-vectorizer when the SDK version doesn't support this model — callers
    # can still pre-compute and pass `query_vector` explicitly.
    vectorizers: list[Any] = []
    if multimodal.endpoint and _HAS_VISION_VECTORIZER:
        try:
            vectorizers.append(
                AIServicesVisionVectorizer(
                    vectorizer_name=_VEC_VECTORIZER,
                    kind="aiServicesVision",
                    ai_services_vision_parameters=AIServicesVisionParameters(
                        resource_uri=multimodal.endpoint,
                        model_version=multimodal.model_version,
                    ),
                )
            )
        except Exception as e:  # noqa: BLE001
            logger.warning(f"Could not build AI Services Vision vectorizer: {e}")

    vector_search = VectorSearch(
        algorithms=[HnswAlgorithmConfiguration(name=_VEC_ALGO)],
        profiles=[
            VectorSearchProfile(
                name=_VEC_PROFILE,
                algorithm_configuration_name=_VEC_ALGO,
                vectorizer_name=_VEC_VECTORIZER if vectorizers else None,
            ),
        ],
        vectorizers=vectorizers,
    )

    semantic = SemanticSearch(
        default_configuration_name=SEMANTIC_CONFIG_NAME,
        configurations=[
            SemanticConfiguration(
                name=SEMANTIC_CONFIG_NAME,
                prioritized_fields=SemanticPrioritizedFields(
                    title_field=SemanticField(field_name="title"),
                    content_fields=[SemanticField(field_name="content_text")],
                ),
            ),
        ],
    )

    return SearchIndex(
        name=name,
        fields=fields,
        vector_search=vector_search,
        semantic_search=semantic,
    )


# ------------------------------------------------------------------ #
# Search push client
# ------------------------------------------------------------------ #

class SearchPushClient:
    """Client that pushes document chunks directly to Azure AI Search."""

    def __init__(self, config: SearchConfig, multimodal: MultimodalConfig):
        self._config = config
        self._multimodal = multimodal
        self._credential = DefaultAzureCredential()
        logger.info("Search client: using DefaultAzureCredential (managed identity)")

        self._index_client = SearchIndexClient(endpoint=config.endpoint, credential=self._credential)
        self._search_client: SearchClient | None = None

    def _get_search_client(self) -> SearchClient:
        if self._search_client is None:
            self._search_client = SearchClient(
                endpoint=self._config.endpoint,
                index_name=self._config.index_name,
                credential=self._credential,
            )
        return self._search_client

    # -------------------------------------------------------------- #
    # Index management
    # -------------------------------------------------------------- #

    def ensure_index(self, force_recreate: bool = False) -> None:
        name = self._config.index_name
        if force_recreate:
            try:
                self._index_client.delete_index(name)
                logger.warning(f"Deleted existing index '{name}' (force_recreate=True)")
            except ResourceNotFoundError:
                pass
            except HttpResponseError as e:
                logger.warning(f"Could not delete index '{name}': {e.message}")

        index = _build_index(name, self._multimodal)
        try:
            self._index_client.create_or_update_index(index)
            logger.info(f"Index '{name}' ready (content_embedding={MULTIMODAL_DIM}d)")
        except HttpResponseError as e:
            logger.error(f"Failed to create/update index: {e.message}")
            raise

    # -------------------------------------------------------------- #
    # Document operations
    # -------------------------------------------------------------- #

    def upload_documents(self, documents: list[dict[str, Any]], batch_size: int = 500) -> int:
        client = self._get_search_client()
        total_uploaded = 0

        for i in range(0, len(documents), batch_size):
            batch = documents[i: i + batch_size]
            result = self._upload_batch_with_retry(client, batch)
            succeeded = sum(1 for r in result if r.succeeded)
            failed = sum(1 for r in result if not r.succeeded)
            total_uploaded += succeeded

            if failed:
                for r in result:
                    if not r.succeeded:
                        logger.error(f"Failed to upload {r.key}: {r.error_message}")

            logger.info(
                f"Batch {i // batch_size + 1}: {succeeded} uploaded, {failed} failed "
                f"({total_uploaded} total so far)"
            )

        return total_uploaded

    def _upload_batch_with_retry(self, client: SearchClient, batch: list[dict], max_retries: int = 5) -> list:
        for attempt in range(max_retries):
            try:
                return client.upload_documents(documents=batch)
            except HttpResponseError as e:
                if e.status_code == 429 or (e.status_code and e.status_code >= 500):
                    wait = min(2 ** attempt, 30)
                    logger.warning(f"Search upload error {e.status_code}. Retrying in {wait}s (attempt {attempt + 1})")
                    time.sleep(wait)
                else:
                    raise
        raise RuntimeError(f"Failed to upload batch after {max_retries} retries")

    def delete_documents_by_parent(self, parent_id: str) -> None:
        client = self._get_search_client()
        results = client.search(
            search_text="*",
            filter=f"parent_id eq '{parent_id}'",
            select=["chunk_id"],
        )
        chunk_ids = [doc["chunk_id"] for doc in results]
        if chunk_ids:
            docs_to_delete = [{"chunk_id": cid} for cid in chunk_ids]
            client.delete_documents(documents=docs_to_delete)
            logger.info(f"Deleted {len(chunk_ids)} chunks for parent '{parent_id}'")

    def check_freshness(self, parent_id: str) -> str | None:
        client = self._get_search_client()
        try:
            results = client.search(
                search_text="*",
                filter=f"parent_id eq '{parent_id}'",
                select=["chunk_id", "last_modified"],
                top=1,
            )
            for doc in results:
                return doc.get("last_modified")
        except HttpResponseError as e:
            logger.warning(f"Freshness check failed for {parent_id}: {e.message}")
        except Exception as e:  # noqa: BLE001
            logger.warning(f"Freshness check failed for {parent_id}: {e}")
        return None

    def get_all_parent_ids(self) -> set[str]:
        client = self._get_search_client()
        parent_ids: set[str] = set()
        try:
            results = client.search(search_text="*", select=["parent_id"])
            for doc in results:
                pid = doc.get("parent_id")
                if pid:
                    parent_ids.add(pid)
        except Exception as e:  # noqa: BLE001
            logger.warning(f"Could not retrieve parent IDs for reconciliation: {e}")
        return parent_ids

    # -------------------------------------------------------------- #
    # Per-user security trimming — single-vector hybrid query
    # -------------------------------------------------------------- #

    def search_with_trimming(
        self,
        query: str,
        identity_ids: list[str],
        top: int = 10,
        extra_filter: str | None = None,
        query_vector: list[float] | None = None,
    ) -> list[dict[str, Any]]:
        """Semantic + hybrid search with permission trimming.

        When `query_vector` is provided, it's used directly (skip client-side
        call to Azure AI Vision). When omitted, AI Search's registered
        AI-Services-Vision vectorizer handles the text → vector conversion.
        """
        from search_security import build_permission_filter

        perm_filter = build_permission_filter(identity_ids)
        full_filter = f"({perm_filter})"
        if extra_filter:
            full_filter = f"{full_filter} and ({extra_filter})"

        from azure.search.documents.models import VectorizableTextQuery, VectorizedQuery

        if query_vector:
            vec_query = VectorizedQuery(
                vector=query_vector, k_nearest_neighbors=top, fields="content_embedding"
            )
        else:
            vec_query = VectorizableTextQuery(
                text=query, k_nearest_neighbors=top, fields="content_embedding"
            )

        client = self._get_search_client()
        select_fields = [
            "chunk_id", "parent_id", "content_text", "title", "source_url",
            "last_modified", "has_image", "content_path", "location_metadata",
        ]
        try:
            results = client.search(
                search_text=query,
                filter=full_filter,
                vector_queries=[vec_query],
                query_type="semantic",
                semantic_configuration_name=SEMANTIC_CONFIG_NAME,
                select=select_fields,
                top=top,
            )
        except HttpResponseError as e:
            logger.warning(f"Semantic search failed, falling back: {e.message}")
            results = client.search(
                search_text=query,
                filter=full_filter,
                vector_queries=[vec_query],
                select=select_fields,
                top=top,
            )

        citations: list[dict[str, Any]] = []
        for doc in results:
            citations.append({
                "chunk_id": doc.get("chunk_id"),
                "parent_id": doc.get("parent_id"),
                "title": doc.get("title"),
                "url": doc.get("source_url"),
                "chunk": doc.get("content_text"),
                "last_modified": doc.get("last_modified"),
                "has_image": bool(doc.get("has_image")),
                "content_path": doc.get("content_path"),
                "location_metadata": doc.get("location_metadata"),
                "score": doc.get("@search.score"),
                "reranker_score": doc.get("@search.reranker_score"),
            })
        return citations

    def close(self) -> None:
        if self._search_client:
            self._search_client.close()
        self._index_client.close()
