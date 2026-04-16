# SharePoint → Azure AI Search Connector

A sample implementation showing how to build a custom push connector for Azure AI Search. This example indexes SharePoint Online documents using Microsoft Graph API, running as an Azure Function on a timer — pulling files, extracting text, generating embeddings, and pushing document chunks directly into a search index.

The same pattern can be used as a starting point for your own connector. The document processor is a basic text extraction implementation — for production use with complex documents (e.g. PDFs with tables, scanned images), consider replacing it with Azure Document Intelligence or similar. The chunker and index schema should also be adjusted based on your specific documents and requirements.

> **Why a custom connector?** Azure AI Search has a [preview SharePoint connector](https://learn.microsoft.com/en-us/azure/search/search-howto-index-sharepoint-online), but it has significant limitations (no private endpoint support, no Conditional Access compatibility, no SLA, limited format control). Building your own gives you full control over the pipeline.

---

## Solution Architecture

![SharePoint Connector Architecture](images/sharepoint-connector-architecture.png)

> The draw.io source is available at [`images/sharepoint-connector-architecture.drawio`](images/sharepoint-connector-architecture.drawio).

---

## Deploy to Azure

Infrastructure deployment (Function App, Storage, App Insights, RBAC) can be done with one click. You will need **Azure AI Search** and **Azure OpenAI** already provisioned — the template assigns RBAC roles to them but does not create them.

[![Deploy to Azure](https://aka.ms/deploytoazurebutton)](https://portal.azure.com/#create/Microsoft.Template/uri/https%3A%2F%2Fraw.githubusercontent.com%2FAzure%2FCopilot-Studio-and-Azure%2Fmain%2Faccelerators%2Fsharepoint-connector%2Fdeploy%2Fazuredeploy.json)

After infrastructure is deployed, you still need to:

1. **Deploy the function code** — `func azure functionapp publish <function-app-name> --python`
2. **Grant Graph API permissions** — See [Step 5](#step-5-grant-graph-api-permissions-one-time)
3. **Wait for RBAC propagation** — 2–10 minutes

> If you prefer the full scripted deployment (infrastructure + code in one command), use [`infra/deploy.ps1`](infra/deploy.ps1) instead.

---

## Table of Contents

- [SharePoint → Azure AI Search Connector](#sharepoint--azure-ai-search-connector)
  - [Solution Architecture](#solution-architecture)
  - [Deploy to Azure](#deploy-to-azure)
  - [Table of Contents](#table-of-contents)
  - [How the Pipeline Works](#how-the-pipeline-works)
  - [Project Structure](#project-structure)
    - [Custom Components](#custom-components)
  - [Prerequisites](#prerequisites)
  - [Step-by-Step Deployment](#step-by-step-deployment)
    - [Step 1: Clone and Install](#step-1-clone-and-install)
    - [Step 2: Create Azure Resources (if not existing)](#step-2-create-azure-resources-if-not-existing)
    - [Step 3: Configure Parameters](#step-3-configure-parameters)
    - [Step 4: Deploy](#step-4-deploy)
    - [Step 5: Grant Graph API Permissions (one-time)](#step-5-grant-graph-api-permissions-one-time)
    - [Step 6: Wait for RBAC Propagation](#step-6-wait-for-rbac-propagation)
    - [Step 7: Trigger and Verify](#step-7-trigger-and-verify)
    - [Step 8: Verify Search](#step-8-verify-search)
  - [Configuration Reference](#configuration-reference)
    - [Environment Variables](#environment-variables)
    - [Bicep Parameters](#bicep-parameters)
  - [Authentication Deep Dive](#authentication-deep-dive)
  - [Supported File Formats](#supported-file-formats)
  - [Incremental Sync \& Reconciliation](#incremental-sync--reconciliation)
    - [Incremental Mode (`INCREMENTAL_MINUTES > 0`)](#incremental-mode-incremental_minutes--0)
    - [Full Reindex (`INCREMENTAL_MINUTES=0`)](#full-reindex-incremental_minutes0)
  - [Security Trimming](#security-trimming)
    - [How permissions are collected](#how-permissions-are-collected)
    - [How to use at query time](#how-to-use-at-query-time)
  - [Monitoring](#monitoring)
  - [Running Tests](#running-tests)
  - [Customization Guide](#customization-guide)
    - [Add a new file format](#add-a-new-file-format)
    - [Change the embedding model](#change-the-embedding-model)
    - [Change the search index schema](#change-the-search-index-schema)
    - [Adjust concurrency](#adjust-concurrency)

---


**Key design decisions:**

| Decision | Rationale |
|---|---|
| **Push connector** (not pull) | Full control over what gets indexed and when. No dependency on Azure's preview connector infrastructure. |
| **No Blob intermediary** | Files go straight from SharePoint → memory → index. Simpler architecture, lower cost, no storage to manage. |
| **System-assigned managed identity** | Zero secrets to manage for Azure services. Only Graph API needs special permissions. |
| **Flex Consumption (FC1)** | Scales to zero when idle, only pay for execution time. 2 GB memory, up to 40 instances. |
| **HNSW vector search** | Industry-standard approximate nearest neighbor algorithm. Good balance of speed and recall. |
| **text-embedding-3-large at 1536 dims** | Best quality OpenAI embedding model. 1536 dims is a good quality/cost tradeoff (model supports up to 3072). |

---

## How the Pipeline Works

Each run follows these steps:

1. **Timer fires** — Azure Functions runtime invokes `sharepoint_indexer` (CRON schedule, default: every hour)
2. **Index check** — `SearchPushClient.ensure_index()` creates or updates the search index schema (idempotent)
3. **File discovery** — `SharePointClient.list_all_files()` queries Graph API to list files across configured document libraries. In incremental mode, filters by `lastModifiedDateTime`.
4. **For each file** (in parallel, up to `MAX_CONCURRENCY` workers):
   - **Freshness check** — Query the search index for the `parent_id`. If the indexed `last_modified` matches (±1 second tolerance), skip the file.
   - **Download** — `SharePointClient.download_file()` fetches file bytes via Graph API
   - **Extract text** — `document_processor.extract_text()` dispatches to the correct extractor based on file extension
   - **Chunk** — `chunker.chunk_text()` splits text into overlapping chunks with intelligent boundary detection
   - **Embed** — `EmbeddingsClient.generate_embeddings_batch()` sends chunks to Azure OpenAI in batches of 16
   - **Delete old chunks** — Remove any existing chunks for this `parent_id` (prevents stale data)
   - **Upload new chunks** — Push all chunks with embeddings, metadata, and permissions to the index
5. **Reconciliation** (full reindex only) — Compare `parent_id` values in the index to current SharePoint files. Delete orphaned chunks from files that no longer exist.
6. **Stats** — Log summary: files discovered, processed, skipped (fresh), errors, chunks uploaded
---

## Project Structure

```
sharepoint-connector/
│
│── function_app.py            # Azure Function entry point (timer trigger)
│── indexer.py                 # Main orchestrator — wires everything together
│── config.py                  # Configuration loader (env vars → dataclasses)
│── sharepoint_client.py       # Microsoft Graph API client
│── document_processor.py      # Text extraction (25+ formats)
│── chunker.py                 # Text chunking with overlap
│── embeddings_client.py       # Azure OpenAI embedding generation
│── search_client.py           # Azure AI Search index management + push
│
│── host.json                  # Azure Functions runtime settings
│── pyproject.toml             # Python project config (uv, dependencies)
│── requirements.txt           # Pinned deps for Azure Functions (auto-generated)
│── .env.sample                # Environment variable template
│── .funcignore                # Files excluded from Azure deployment
│── .gitignore                 # Git exclusions
│
├── infra/                     # Infrastructure as Code
│   ├── main.bicep             # Bicep template (all Azure resources + RBAC)
│   ├── main.bicepparam        # Parameter values (⚠️ edit before deploying)
│   └── deploy.ps1             # One-command deployment script
│
└── tests/                     # Unit tests (53 tests)
    ├── test_chunker.py        # Chunking logic tests
    ├── test_document_processor.py  # Text extraction tests
    └── test_config.py         # Configuration loading tests
```

### Custom Components

> The document processor and chunker are **fully custom implementations** that may need to be adjusted depending on your use case, document types, and quality requirements.

| Component | What it does | When to adjust |
|---|---|---|
| `document_processor.py` | Hand-written text extractors for 25+ file formats. | If extraction quality isn't sufficient for your documents (e.g. complex PDFs with tables/images), consider swapping in Azure Document Intelligence or Unstructured.io. |
| `chunker.py` | Fixed-size overlapping chunks with paragraph→sentence boundary detection. | Chunk size and overlap are configurable via env vars. |

---

## Prerequisites

| Requirement | Why |
|---|---|
| **Python 3.11+** | Required by the Azure Functions runtime and type hints used in the code |
| **[uv](https://docs.astral.sh/uv/)** | Package manager — manages dependencies, virtual environment, and `requirements.txt` generation |
| **[Azure CLI](https://learn.microsoft.com/cli/azure/install-azure-cli)** (`az`) | Bicep deployment, RBAC management, manual function triggers |
| **[Azure Functions Core Tools v4](https://learn.microsoft.com/azure/azure-functions/functions-run-tools?tabs=windows)** (`func`) | Code deployment and log streaming |
| **Azure AI Search** (Basic tier+) | Free tier does NOT support vector search. Basic or Standard required. |
| **Azure OpenAI / Foundry** | With a `text-embedding-3-large` deployment (or another embedding model) |
| **Microsoft Entra ID tenant** | For Graph API authentication |
| **SharePoint Online site** | The source document library |

---

## Step-by-Step Deployment

### Step 1: Clone and Install

```bash
git clone <repo-url>
cd sharepoint-connector
uv sync
```

### Step 2: Create Azure Resources (if not existing)

The Bicep template creates the Function App, Storage, and monitoring resources. But it expects these to **already exist**:

- **Azure AI Search service** (Basic tier or higher)
- **Azure OpenAI / Foundry resource** with an embedding model deployed

If you don't have these yet:

```bash
# Create a resource group
az group create --name my-rg --location swedencentral

# Create Azure AI Search (Basic tier)
az search service create --name my-search --resource-group my-rg --sku basic --location swedencentral

# Create Azure OpenAI (if using Azure OpenAI, not Foundry)
az cognitiveservices account create --name my-openai --resource-group my-rg --kind OpenAI --sku S0 --location swedencentral

# Deploy an embedding model
az cognitiveservices account deployment create --name my-openai --resource-group my-rg --deployment-name text-embedding-3-large --model-name text-embedding-3-large --model-version "1" --model-format OpenAI --sku-capacity 120 --sku-name Standard
```

### Step 3: Configure Parameters

Edit `infra/main.bicepparam` with your values:

```bicep
using './main.bicep'

param baseName = 'sp-indexer'                    // Base name for resources
param location = 'swedencentral'                 // Azure region

param tenantId = 'your-tenant-id'                // Entra ID tenant
param sharePointSiteUrl = 'https://company.sharepoint.com/sites/MySite'

// Azure AI Search — endpoint + full resource ID
param searchEndpoint = 'https://my-search.search.windows.net'
param searchResourceId = '/subscriptions/<sub>/resourceGroups/<rg>/providers/Microsoft.Search/searchServices/my-search'

// Azure OpenAI / Foundry — endpoint + full resource ID
param foundryEndpoint = 'https://my-openai.openai.azure.com'
param foundryResourceId = '/subscriptions/<sub>/resourceGroups/<rg>/providers/Microsoft.CognitiveServices/accounts/my-openai'
```

### Step 4: Deploy

```powershell
.\infra\deploy.ps1 -ResourceGroup my-rg
```

This will:
1. Deploy infrastructure via Bicep (2–3 minutes)
2. Generate `requirements.txt`
3. Publish function code (~1 minute)
4. Print the managed identity's object ID

### Step 5: Grant Graph API Permissions (one-time)

The Function App's managed identity needs Microsoft Graph permissions to read SharePoint files. This **cannot** be done via Bicep — it requires admin consent.

**Option A: Azure CLI (recommended)**

```bash
# Get the managed identity's object ID (printed by deploy script)
MSI_OBJECT_ID=<value-from-deploy-output>

# Get the Graph API service principal
GRAPH_SP_ID=$(az ad sp list --filter "appId eq '00000003-0000-0000-c000-000000000000'" --query "[0].id" -o tsv)

# Get the role IDs
SITES_READ_ROLE=$(az ad sp show --id $GRAPH_SP_ID --query "appRoles[?value=='Sites.Read.All'].id" -o tsv)
FILES_READ_ROLE=$(az ad sp show --id $GRAPH_SP_ID --query "appRoles[?value=='Files.Read.All'].id" -o tsv)

# Grant Sites.Read.All
az rest --method POST --uri "https://graph.microsoft.com/v1.0/servicePrincipals/$MSI_OBJECT_ID/appRoleAssignments" --body "{\"principalId\":\"$MSI_OBJECT_ID\",\"resourceId\":\"$GRAPH_SP_ID\",\"appRoleId\":\"$SITES_READ_ROLE\"}"

# Grant Files.Read.All
az rest --method POST --uri "https://graph.microsoft.com/v1.0/servicePrincipals/$MSI_OBJECT_ID/appRoleAssignments" --body "{\"principalId\":\"$MSI_OBJECT_ID\",\"resourceId\":\"$GRAPH_SP_ID\",\"appRoleId\":\"$FILES_READ_ROLE\"}"
```

**Option B: Microsoft Graph PowerShell**

```powershell
Install-Module Microsoft.Graph -Scope CurrentUser
Connect-MgGraph -Scopes "Application.Read.All","AppRoleAssignment.ReadWrite.All"

$graphSp = Get-MgServicePrincipal -Filter "appId eq '00000003-0000-0000-c000-000000000000'"
$msi = Get-MgServicePrincipal -Filter "id eq '<MSI_OBJECT_ID>'"

# Sites.Read.All
$role = $graphSp.AppRoles | Where-Object { $_.Value -eq 'Sites.Read.All' }
New-MgServicePrincipalAppRoleAssignment -ServicePrincipalId $msi.Id `
    -PrincipalId $msi.Id -ResourceId $graphSp.Id -AppRoleId $role.Id

# Files.Read.All
$role = $graphSp.AppRoles | Where-Object { $_.Value -eq 'Files.Read.All' }
New-MgServicePrincipalAppRoleAssignment -ServicePrincipalId $msi.Id `
    -PrincipalId $msi.Id -ResourceId $graphSp.Id -AppRoleId $role.Id
```

> ⚠️ **This requires Global Admin or Privileged Role Administrator.** The deployment script cannot automate this step.

### Step 6: Wait for RBAC Propagation

After deployment, RBAC role assignments (both Azure roles and Graph permissions) need **2–10 minutes** to propagate. During this window, the Function App may return 500 errors or fail to access storage/search/OpenAI.

### Step 7: Trigger and Verify

```powershell
# Force a full reindex
az functionapp config appsettings set --name sp-indexer-func --resource-group my-rg --settings INCREMENTAL_MINUTES=0

# Trigger the function manually
$masterKey = (az functionapp keys list --name sp-indexer-func --resource-group my-rg --query "masterKey" -o tsv)
Invoke-WebRequest -Uri "https://sp-indexer-func.azurewebsites.net/admin/functions/sharepoint_indexer" -Method POST -Headers @{"x-functions-key"=$masterKey; "Content-Type"="application/json"} -Body '{}'

# Check logs
az monitor app-insights query --app sp-indexer-insights --resource-group my-rg --analytics-query "traces | where message contains 'Indexer run complete' | project timestamp, message | take 5"

# Restore incremental mode
az functionapp config appsettings set --name sp-indexer-func --resource-group my-rg --settings INCREMENTAL_MINUTES=65
```

### Step 8: Verify Search

```powershell
# Count documents in the index
$token = (az account get-access-token --resource "https://search.azure.com" | ConvertFrom-Json).accessToken
$r = Invoke-RestMethod -Uri "https://my-search.search.windows.net/indexes/sharepoint-index/docs?api-version=2024-07-01&search=*&`$count=true&`$top=0" -Headers @{"Authorization"="Bearer $token"}
Write-Host "Documents: $($r.'@odata.count')"
```

---

## Configuration Reference

### Environment Variables

| Variable | Required | Default | Description |
|---|---|---|---|
| `TENANT_ID` | **Yes** | — | Microsoft Entra tenant ID |
| `CLIENT_ID` | No | `""` | App registration client ID (only if using client secret auth for Graph) |
| `CLIENT_SECRET` | No | `""` | App registration client secret (only if using client secret auth for Graph) |
| `SHAREPOINT_SITE_URL` | **Yes** | — | Full URL, e.g. `https://company.sharepoint.com/sites/MySite` |
| `SHAREPOINT_LIBRARIES` | No | `""` (all) | Comma-separated library names to index (empty = all libraries) |
| `SEARCH_ENDPOINT` | **Yes** | — | e.g. `https://my-search.search.windows.net` |
| `SEARCH_INDEX_NAME` | No | `sharepoint-index` | Name of the search index to create/use |
| `FOUNDRY_ENDPOINT` | **Yes** | — | Azure OpenAI base URL (no path, no deployment) |
| `FOUNDRY_EMBEDDING_DEPLOYMENT` | No | `text-embedding-3-large` | Deployment name for the embedding model |
| `FOUNDRY_EMBEDDING_DIMENSIONS` | No | `1536` | Vector dimensions. ⚠️ Changing this requires index recreation |
| `INDEXED_EXTENSIONS` | No | 25 extensions | Comma-separated list of file extensions to index |
| `CHUNK_SIZE` | No | `2000` | Maximum characters per chunk |
| `CHUNK_OVERLAP` | No | `200` | Characters of overlap between consecutive chunks |
| `MAX_CONCURRENCY` | No | `4` | Number of parallel file-processing workers |
| `MAX_FILE_SIZE_MB` | No | `100` | Files larger than this (in MB) are skipped |
| `INCREMENTAL_MINUTES` | No | `0` | How far back to look for changes. `0` = full reindex. In production, use `65` with an hourly CRON. |
| `INDEXER_SCHEDULE` | No | `0 0 * * * *` | CRON expression (NCrontab, 6 fields). Default: every hour. |

> ⚠️ **`INCREMENTAL_MINUTES` vs `INDEXER_SCHEDULE`**: These work together. If your CRON runs every 60 minutes, set `INCREMENTAL_MINUTES=65` (5 minutes overlap). This ensures files modified in the last minute of the previous window aren't missed due to clock skew.

### Bicep Parameters

All Bicep parameters mirror the environment variables above. Edit `infra/main.bicepparam` before deployment. The most common parameter to change post-deployment is `INCREMENTAL_MINUTES` (via app settings, not Bicep redeployment).

---

## Authentication Deep Dive

The connector uses **three separate authentication flows**:

| Service | Auth Method | Credential Type | How It Works |
|---|---|---|---|
| **Azure AI Search** | `DefaultAzureCredential` | Managed identity (prod) or Azure CLI (dev) | The `azure-search-documents` SDK accepts a credential object directly |
| **Azure OpenAI / Foundry** | `DefaultAzureCredential` | Token provider via `get_bearer_token_provider()` | The `openai` SDK uses a callback that auto-refreshes tokens for scope `https://cognitiveservices.azure.com/.default` |
| **Microsoft Graph** (SharePoint) | `DefaultAzureCredential` **or** `ClientSecretCredential` | Managed identity or client secret | Gets token for scope `https://graph.microsoft.com/.default`. Uses `httpx` for HTTP calls (not an SDK). |

**No API keys are used anywhere.** All Azure service authentication is token-based.

**For local development**, `DefaultAzureCredential` falls through to Azure CLI login (`az login`). Make sure your Azure CLI user has the same RBAC roles as the managed identity.

**Graph API is special:** Unlike Search and OpenAI, Graph API requires **application permissions** (`Sites.Read.All`, `Files.Read.All`) to be explicitly granted to the identity. These are not RBAC roles — they're app role assignments on the Microsoft Graph service principal. This is the one-time manual step after deployment.

---



## Supported File Formats

| Format | Extensions | Library Used | Notes |
|---|---|---|---|
| PDF | `.pdf` | PyMuPDF (`fitz`) | Page-by-page text extraction |
| Word | `.docx`, `.docm` | `python-docx` | Paragraph text only (no images/tables layout) |
| Excel | `.xlsx`, `.xlsm` | `openpyxl` | All sheets, tab-separated cells |
| PowerPoint | `.pptx`, `.pptm` | `python-pptx` | Text from all shapes with text frames |
| Plain text | `.txt`, `.md` | Built-in | Encoding fallback chain |
| CSV | `.csv` | Built-in `csv` | Tab-separated output |
| JSON | `.json` | Built-in `json` | Pretty-printed structure |
| XML/KML | `.xml`, `.kml` | Built-in `xml.etree` | Text content from all elements |
| HTML | `.html`, `.htm` | BeautifulSoup | Strips scripts, styles, nav, footer, header |
| RTF | `.rtf` | `striprtf` | Plain text extraction |
| Email (EML) | `.eml` | Built-in `email` | Subject, from, date, body (HTML → text) |
| Email (MSG) | `.msg` | `extract-msg` | Outlook format: subject, from, date, body |
| EPUB | `.epub` | `ebooklib` + BeautifulSoup | All document items |
| OpenDocument | `.odt`, `.ods`, `.odp` | `odfpy` | Recursive text extraction |
| ZIP archive | `.zip` | Built-in `zipfile` | Extracts and processes inner files (depth limit: 3) |
| GZ archive | `.gz` | Built-in `gzip` | Decompresses and processes inner file |

**Not supported:** `.doc`, `.xls`, `.ppt` (old binary formats), images, video, audio.

## Incremental Sync & Reconciliation

### Incremental Mode (`INCREMENTAL_MINUTES > 0`)

In production, the indexer runs hourly with `INCREMENTAL_MINUTES=65`:

1. Graph API query filters files by `lastModifiedDateTime >= (now - 65 minutes)`
2. For each matching file, checks the search index for an existing `parent_id`
3. If the indexed `last_modified` matches (±1 second tolerance), skips the file
4. Otherwise, deletes old chunks and re-uploads

**The 5-minute overlap** (65 minutes for a 60-minute CRON) handles:
- Clock skew between SharePoint and the Function App
- Files modified in the last seconds of the previous window
- Timer drift in serverless environments

### Full Reindex (`INCREMENTAL_MINUTES=0`)

When `INCREMENTAL_MINUTES=0`, the indexer:
1. Processes **all files** (no time filter)
2. Still skips fresh files (freshness check is always on)
3. **Runs reconciliation**: Queries all `parent_id` values from the index, compares to current SharePoint files, and deletes orphaned chunks

> ⚠️ **Reconciliation only runs on full reindex.** If you delete files from SharePoint, their chunks will remain in the index until the next full reindex. To force cleanup, set `INCREMENTAL_MINUTES=0` temporarily.

---

## Security Trimming

The connector stores Entra ID object IDs (users and groups) that have access to each file in the `permission_ids` field. This enables query-time security filtering.

### How permissions are collected

1. For each file, the connector calls `GET /beta/drives/{driveId}/items/{itemId}/permissions`
2. It extracts identity IDs from `grantedToV2` (direct permissions) and `grantedToIdentitiesV2` (sharing links)
3. These are stored as a `Collection(Edm.String)` in the index

### How to use at query time

```python
from azure.search.documents import SearchClient

# Get the current user's Entra object ID and group memberships
user_id = "..."  # From authentication token
group_ids = ["...", "..."]  # From Microsoft Graph /me/memberOf

# Build filter
all_ids = [user_id] + group_ids
filter_clauses = " or ".join(f"permission_ids/any(p: p eq '{id}')" for id in all_ids)

results = search_client.search(
    search_text="quarterly report",
    filter=filter_clauses,
)
```

> ⚠️ **The permissions are a snapshot** from when the file was indexed. If permissions change in SharePoint, they won't be reflected until the file is re-indexed (on its next modification or next full reindex).

---

## Monitoring

```bash
func azure functionapp logstream <function-app-name>
```

Logs are also available in Application Insights. Search for `"Indexer run complete"` in traces to see run summaries.

---

## Running Tests

```bash
# Install dev dependencies
uv sync --extra dev

# Run all 53 tests
uv run pytest tests/ -v

# Run specific test file
uv run pytest tests/test_chunker.py -v
uv run pytest tests/test_document_processor.py -v
uv run pytest tests/test_config.py -v
```

Tests cover:
- **Chunking**: boundary detection, overlap, edge cases (empty text, single chunk, overlap >= size)
- **Document processing**: text extraction for all supported formats, encoding handling, archive depth limits
- **Configuration**: required vs optional variables, defaults, extensions parsing

---

## Customization Guide

### Add a new file format

1. Write an extractor function in `document_processor.py`:
   ```python
   def _extract_myformat(content: bytes, filename: str = "") -> str:
       # Your extraction logic
       return extracted_text
   ```
2. Add it to the `extractors` dict in `extract_text()`:
   ```python
   ".myext": _extract_myformat,
   ```
3. Add `.myext` to `INDEXED_EXTENSIONS` env var
4. Add the required library to `pyproject.toml`
5. Write a test in `tests/test_document_processor.py`

### Change the embedding model

1. Deploy the new model in Azure OpenAI
2. Set `FOUNDRY_EMBEDDING_DEPLOYMENT` to the new deployment name
3. If dimensions differ: set `FOUNDRY_EMBEDDING_DIMENSIONS`, **delete the search index**, and do a full reindex
4. If the model name doesn't contain `"embedding-3"`, the `dimensions` parameter won't be sent (only `text-embedding-3-*` models support it)

### Change the search index schema

1. Edit `_build_index()` in `search_client.py` to add/modify fields
2. Run `ensure_index()` — it uses `create_or_update_index()` so new fields are added to existing indexes
3. **Removing fields or changing vector dimensions** requires deleting and recreating the index

### Adjust concurrency

- `MAX_CONCURRENCY` controls how many files are processed in parallel
- Higher values = faster, but more memory usage and more Graph API/OpenAI API calls in parallel
- The Flex Consumption plan has 2 GB memory — 4 workers is a safe default for most file sizes

---

