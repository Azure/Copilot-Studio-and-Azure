# Azure AI Search behind Private Endpoint + Copilot Studio

## Objective

Provide an end-to-end accelerator for hosting **Azure AI Search** behind a **Private Endpoint** (no public network access) and querying it from **Copilot Studio** in a **Power Platform Managed Environment** via [Enterprise Policy / VNet
injection](https://learn.microsoft.com/power-platform/admin/vnet-support-setup-configure).

> **Why not just use `bypass=AzureServices`?** Power Platform is not on the
> trusted-services list for Azure AI Search. `networkRuleSet.bypass` only covers
> services like Azure Machine Learning and Azure Cognitive Services indexers —
> not Copilot Studio runtime calls. A Power Platform Enterprise
> Policy linked to a delegated subnet is the supported bridge.

What you get when you finish the steps below:

* `Microsoft.Search/searchServices` with `publicNetworkAccess=Disabled`, optional system-assigned identity, and a Private Endpoint into a dedicated subnet.
* One Private DNS zone linked to the primary VNet:
  `privatelink.search.windows.net`.
* Two delegated subnets in [paired Azure regions for Power Platform](https://learn.microsoft.com/power-platform/admin/vnet-support-overview#supported-regions) VNet
  injection (multi-region PP geos like `unitedstates` require subnets in two regions).
* `Microsoft.PowerPlatform/enterprisePolicies` (kind `NetworkInjection`)
  referencing both delegated subnets, linked to your Managed PP environment.
* Copilot Studio connected to Azure AI Search via VNet injection over the Microsoft backbone — no public internet exposure.

## Architecture

![Power Platform → VNet → Azure AI Search](docs/ppvnet-aisearch-solution-architecture.png)

The architecture diagram source is at [docs/aisearch-architecture.drawio](docs/aisearch-architecture.drawio).

## Getting Started

### Prerequisites

| Requirement | Notes |
|---|---|
| [Azure subscription](https://azure.microsoft.com/free/) Owner / Contributor | RG, networking, AI Search, PE, DNS, Enterprise Policy |
| [Azure CLI](https://learn.microsoft.com/cli/azure/install-azure-cli) ≥ `2.50` | Only required for scripted path |
| [PowerShell 7+](https://learn.microsoft.com/powershell/scripting/install/installing-powershell) (`pwsh`) | For helper scripts |
| [`Microsoft.PowerPlatform.EnterprisePolicies` PowerShell module](https://www.powershellgallery.com/packages/Microsoft.PowerPlatform.EnterprisePolicies) | Auto-installed by `link-enterprise-policy.ps1` |
| [Power Platform / Global Administrator](https://learn.microsoft.com/power-platform/admin/use-service-admin-role-manage-tenant) | Required to enable Managed Environment + link the policy |
| Target environment is a [**Managed Environment**](https://learn.microsoft.com/power-platform/admin/managed-environment-overview) | Sandbox is not allowed; enable in PPAC |
| AI Search SKU must be **Basic or above** | Free tier does **not** support private endpoints |

> **Existing AI Search?** If you already have an AI Search service and only
> need to put it behind a private endpoint, set `provisionAiSearch=false` and
> supply `existingAiSearchResourceId` with the full ARM resource ID. The
> template will skip creating the search service and provision the network
> resources (VNet, PE, DNS, Enterprise Policy) only.

### Deployment

#### Step 1 — Clone the repository

```powershell
git clone https://github.com/<org>/Copilot-Studio-and-Azure.git
cd Copilot-Studio-and-Azure/accelerators/private-endpoint/ai-search
```

#### Step 2 — Copy `.env.example` to `.env` and fill in your values

```powershell
Copy-Item .env.example .env
# edit .env in your editor
```

| Variable | What to put here |
|---|---|
| `AZURE_SUBSCRIPTION_ID` | GUID of the Azure subscription |
| `AZURE_RESOURCE_GROUP` | Resource group name (created if it doesn't exist) |
| `BASE_NAME` | 3–11 chars, lowercase alphanumerics |
| `PP_TENANT_ID` | Microsoft Entra tenant ID |
| `PP_ENVIRONMENT_ID` | Power Platform environment GUID |
| `PP_GEO` | Power Platform region (`unitedstates`, `europe`, …) |
| `PROVISION_AI_SEARCH` | `true` to create a new search service, `false` to use existing |
| `EXISTING_AI_SEARCH_RESOURCE_ID` | Full ARM resource ID — only when `PROVISION_AI_SEARCH=false` |
| `AI_SEARCH_SKU` | `basic` (default), `standard`, `standard2`, `standard3` |
| `DEPLOY_SAMPLE_DATA` | `true` to load sample health-plan PDFs into an index (auto-creates Azure OpenAI resource for vectorization) |
| `PROVISION_VNET` | `true` (default) to create new VNets; `false` to use existing |
| `EXISTING_VNET_ID` | Full ARM resource ID of existing primary VNet — only when `PROVISION_VNET=false` |
| `EXISTING_PE_SUBNET_NAME` | PE subnet name in existing VNet (default: `snet-pe`) |
| `EXISTING_PP_SUBNET_NAME` | PP-delegated subnet name in existing VNet (default: `snet-powerplatform`) |
| `EXISTING_SECONDARY_VNET_ID` | Secondary VNet ARM ID — only for multi-region geos with `PROVISION_VNET=false` |
| `EXISTING_SECONDARY_PP_SUBNET_NAME` | PP-delegated subnet name in secondary VNet (default: `snet-powerplatform`) |

#### Step 3 — Provision the infrastructure

Pick **one** of the two options below, then continue with the linking step.

##### Option A — One-click ARM deploy (recommended)

[![Deploy to Azure](https://aka.ms/deploytoazurebutton)](https://portal.azure.com/#create/Microsoft.Template/uri/https%3A%2F%2Fraw.githubusercontent.com%2Fgokseloral%2FCopilot-Studio-and-Azure%2Fmain%2Faccelerators%2Fprivate-endpoint%2Fai-search%2Finfra%2Fazuredeploy-aisearch.json)

The portal blade collects:

| Parameter | Description | Example |
|---|---|---|
| `baseName` | 3–11 chars, lowercase alphanumerics | `pvsrch` |
| `powerPlatformRegion` | PP geo. Drives primary/secondary Azure regions. | `unitedstates` |
| `powerPlatformEnvironmentId` | GUID of the target PP environment | `00000000-…` |
| `provisionAiSearch` | `true` (default) to create a new search service; `false` to use existing | `true` |
| `existingAiSearchResourceId` | Full ARM resource ID of existing search service (when `provisionAiSearch=false`) | `/subscriptions/…/providers/Microsoft.Search/searchServices/<name>` |
| `aiSearchSku` | SKU for the new search service | `basic` |
| `deploySampleData` | `true` to provision a storage account and load sample health-plan PDFs into the index (see [Sample Data](#sample-data--optional-health-plan-index) below) | `false` |
| `provisionVnet` | `true` (default) to create new VNets; `false` to use existing VNets | `true` |
| `existingVnetId` | Full ARM resource ID of an existing primary VNet (when `provisionVnet=false`) | `/subscriptions/…/providers/Microsoft.Network/virtualNetworks/<name>` |
| `existingPeSubnetName` | Name of the PE subnet in the existing VNet (when `provisionVnet=false`). Must have `privateEndpointNetworkPolicies=Disabled`. | `snet-pe` |
| `existingPpSubnetName` | Name of the PP-delegated subnet in the existing VNet (when `provisionVnet=false`). Must be /24, delegated to `Microsoft.PowerPlatform/enterprisePolicies`. | `snet-powerplatform` |
| `existingSecondaryVnetId` | Full ARM resource ID of an existing secondary VNet (when `provisionVnet=false` and multi-region PP geo) | `/subscriptions/…/providers/Microsoft.Network/virtualNetworks/<name>` |
| `existingSecondaryPpSubnetName` | Name of the PP-delegated subnet in the existing secondary VNet | `snet-powerplatform` |
| `vnetAddressPrefix` / `peSubnetPrefix` / `ppSubnetPrefix` | Primary VNet + subnet CIDRs (ignored when `provisionVnet=false`) | `10.60.0.0/16` / `10.60.1.0/24` / `10.60.2.0/24` |
| `secondaryVnetAddressPrefix` / `secondaryPpSubnetPrefix` | Secondary VNet + delegated subnet (ignored for single-region geos or `provisionVnet=false`) | `10.61.0.0/16` / `10.61.2.0/24` |

> **Using an existing VNet?** Set `provisionVnet=false` and provide `existingVnetId` +
> subnet names. The existing PE subnet must have `privateEndpointNetworkPolicies` set to
> `Disabled`. The PP-delegated subnet must be exactly /24 with a delegation to
> `Microsoft.PowerPlatform/enterprisePolicies` and no NSG or route table attached.
> For multi-region PP geos (e.g., `unitedstates`), also provide `existingSecondaryVnetId`.

**Region mapping reference:**

| `powerPlatformRegion` | Primary Azure region | Secondary Azure region | Enterprise Policy `location` |
|---|---|---|---|
| `unitedstates` | `westus` | `eastus` | `unitedstates` |
| `europe` | `westeurope` | `northeurope` | `europe` |
| `unitedkingdom` | `uksouth` | `ukwest` | `unitedkingdom` |
| `japan` | `japaneast` | `japanwest` | `japan` |
| `australia` | `australiaeast` | `australiasoutheast` | `australia` |
| `asia` | `southeastasia` | `eastasia` | `asia` |
| `singapore` | `southeastasia` | *(none — single-region geo)* | `singapore` |
| `sweden` | `swedencentral` | *(none — single-region geo)* | `sweden` |

> For `singapore` and `sweden`, the template skips the secondary VNet entirely.

##### Option B — Scripted (`.env` + PowerShell)

```powershell
./scripts/deploy-aisearch.ps1
```

#### Step 3.5 — Load sample data (ARM template path only)

> **Skip this step if you used Option B (scripted path).** The `deploy-aisearch.ps1` script calls `load-sample-data.ps1` automatically when `DEPLOY_SAMPLE_DATA=true`.

When you deploy via the one-click ARM template with `deploySampleData=true`, the template provisions the **storage account and container** but cannot run post-deployment scripts from the portal. You must run `load-sample-data.ps1` manually from your local machine to:

1. Download the 6 sample health-plan PDFs from [azure-search-sample-data](https://github.com/Azure-Samples/azure-search-sample-data/tree/main/health-plan).
2. Upload them to the `health-plan-pdfs` blob container.
3. Create an Azure OpenAI resource and deploy `text-embedding-3-large` (skipped if `-OpenAIEndpoint` is provided).
4. Temporarily open the AI Search firewall to your current public IP.
5. Create the `health-plan-index` index schema (with `contentVector` field, 3072 dimensions), skillset, data source, and indexer via the Search REST API.
6. Wait for the indexer to run, then restore the firewall to private-only.

```powershell
# Run from accelerators/private-endpoint/ai-search/
# Default: auto-creates Azure OpenAI resource with text-embedding-3-large
./scripts/load-sample-data.ps1 `
    -ResourceGroup       <your-resource-group> `
    -SearchServiceName   <search-service-name> `
    -StorageAccountName  <storage-account-name>

# Or use an existing Azure OpenAI resource:
./scripts/load-sample-data.ps1 `
    -ResourceGroup       <your-resource-group> `
    -SearchServiceName   <search-service-name> `
    -StorageAccountName  <storage-account-name> `
    -OpenAIEndpoint      https://my-openai.openai.azure.com/ `
    -OpenAIApiKey        <key>
```

| Parameter | Default | Description |
|---|---|---|
| `-ResourceGroup` | *(from deployment outputs)* | Azure resource group name |
| `-SearchServiceName` | *(from deployment outputs)* | Name of the AI Search service |
| `-StorageAccountName` | *(from deployment outputs)* | Storage account for sample PDFs |
| `-OpenAIEndpoint` | *(auto-created)* | Existing Azure OpenAI endpoint. If omitted, a new resource is created. |
| `-OpenAIApiKey` | *(auto-retrieved)* | API key for existing OpenAI resource. Required only with `-OpenAIEndpoint`. |
| `-OpenAIEmbeddingDeployment` | `text-embedding-3-large` | Name of the embedding model deployment |
| `-OpenAIModelName` | *(same as deployment)* | Underlying model name for the vectorizer |
| `-EmbeddingDimensions` | `3072` | Vector dimensions (use `1536` for text-embedding-3-small) |
| `-SkipVectorization` | `$false` | Skip OpenAI creation and vector embeddings entirely |
| `-SkipPublicAccessRestore` | `$false` | Leave public access open after indexing (for debugging) |

Replace the placeholder values with the resource names from your deployment. You can find them in the **Deployment details** blade in the Azure portal (the names follow the pattern `srch-<baseName>…` and `stp<baseName>…`).

> **Prerequisites for this step:** Azure CLI (`az`) signed in with at least **Contributor** on the resource group, and **PowerShell 7+** (`pwsh`).

#### Step 4 — Link the Enterprise Policy to your PP environment

ARM cannot call the Power Platform admin API — that step requires local interactive auth.

**If you deployed via the one-click ARM template** (no `.env`):

```powershell
# From accelerators/private-endpoint/ (parent folder)
./scripts/link-enterprise-policy.ps1 `
    -ResourceGroup      <your-rg-name> `
    -PowerPlatformEnvId <pp-environment-guid> `
    -UseDeviceCode
```

**If you deployed via the scripted path** (`.env` already populated):

```powershell
cd ..   # move to accelerators/private-endpoint/
./scripts/link-enterprise-policy.ps1 -UseDeviceCode
```

To unlink later:

```powershell
./scripts/link-enterprise-policy.ps1 -Unlink -PowerPlatformEnvId <guid>
```

## Testing

### 1. Verify private connectivity

| Run from | Expected | Meaning |
|---|---|---|
| Your laptop (public internet) | `403 Forbidden` or timeout | ✅ Public access is disabled |
| VM inside `snet-pe` | `200 OK` | ✅ Private endpoint + DNS working |
| Copilot Studio in linked env | Search results returned | ✅ End-to-end PP → PE working |

### 2. End-to-end test from Copilot Studio

1. Open [Copilot Studio](https://copilotstudio.microsoft.com/) in the same linked Managed Environment.
2. Create or open an existing agent (copilot).
3. Go to **Knowledge** → **+ Add knowledge** → **Azure AI Search**.
4. Provide the search service endpoint (`https://<name>.search.windows.net`) and authentication details.
5. In the **Test your agent** pane, send a message that triggers a search (e.g. _"What are the PerksPlus benefits?"_).
6. The agent should return results from your AI Search index — confirming private connectivity works end-to-end from Copilot Studio through the VNet.

> **Note:** Copilot Studio connects directly to Azure AI Search via VNet
> injection when the environment is linked to an Enterprise Policy. No custom
> connector is required.

### 4. Verify the Enterprise Policy link

```powershell
$envId = '<pp-environment-guid>'
$tok   = az account get-access-token --resource 'https://service.powerapps.com/' --query accessToken -o tsv
$uri   = "https://api.bap.microsoft.com/providers/Microsoft.BusinessAppPlatform/scopes/admin/environments/$envId" + '?api-version=2019-10-01&$expand=properties.enterprisePolicies'
$ppEnv = Invoke-RestMethod -Uri $uri -Headers @{ Authorization = "Bearer $tok" }

if (-not $ppEnv.properties.PSObject.Properties['enterprisePolicies']) {
  Write-Warning "No Enterprise Policy linked. Run scripts/link-enterprise-policy.ps1."
} else {
  $ppEnv.properties.enterprisePolicies | ConvertTo-Json -Depth 10
}
```

Look for `"linkStatus": "Linked"` in the `vNets` object.


## Troubleshooting

| Symptom | Likely cause / fix |
|---|---|
| Copilot Studio returns `403` | Enterprise Policy not linked yet. Verify with the BAP API snippet above and run `link-enterprise-policy.ps1`. |
| `404` from `enterprisePolicies/vnet/link` | Environment is not a Managed Environment. Enable it in PPAC, then re-run the link script. |
| `Environment location 'unitedstates' does not match enterprise policy location 'westus'` | The Enterprise Policy `location` must be the PP geo string (`unitedstates`), not an Azure region. Redeploy using the provided template which handles this automatically. |
| `EnterprisePolicyUpdateNotAllowed` on redeploy | The policy is currently linked. Unlink first (`-Unlink`), redeploy, then re-link. |
| `400 Bad Request` from SearchDocuments | Check `api-version` parameter and request body schema. Minimum body: `{"search": "*"}`. |
| AI Search returns `401 Unauthorized` | Wrong key type — use the **query key** for search operations, not the admin key. |
| Private endpoint status shows `Pending` | If using an existing search service (`provisionAiSearch=false`), the PE connection may need approval. Go to the search service → Networking → Private endpoint connections and approve. |

### Cleanup

```powershell
# From accelerators/private-endpoint/
./scripts/link-enterprise-policy.ps1 -Unlink
az group delete -n $env:AZURE_RESOURCE_GROUP --yes --no-wait
```

---

## Sample Data — Optional Health Plan Index

When `deploySampleData=true` is set, the accelerator provisions a **Storage Account** with a `health-plan-pdfs` container and expects 6 sample PDF files to be indexed by Azure AI Search.

> **Important:** The ARM template (portal one-click deploy) only creates the Azure **infrastructure** (storage account + container). The file upload, index, data source, and indexer are created by the `load-sample-data.ps1` script, which must be run separately (see [Step 3.5](#step-35--load-sample-data-arm-template-path-only) above).

### What the script creates

| Resource | Name |
|---|---|
| Azure OpenAI resource | `<searchServiceName>-openai` (skipped if `-OpenAIEndpoint` provided) |
| Model deployment | `text-embedding-3-large` (3072 dimensions) |
| Blob container | `health-plan-pdfs` |
| AI Search index | `health-plan-index` |
| AI Search skillset | `ss-health-plan` |
| AI Search data source | `ds-health-plan-blobs` |
| AI Search indexer | `ixr-health-plan` |

### Sample PDF files

The script downloads these files from [Azure-Samples/azure-search-sample-data](https://github.com/Azure-Samples/azure-search-sample-data/tree/main/health-plan):

- `Benefit_Options.pdf`
- `Northwind_Health_Plus_Benefits_Details.pdf`
- `Northwind_Standard_Benefits_Details.pdf`
- `PerksPlus.pdf`
- `employee_handbook.pdf`
- `role_library.pdf`

### Re-running the script

The script is idempotent — re-running it will overwrite existing blobs, and the `PUT` calls to the Search REST API will update the index/data source/indexer if they already exist.

---

Sample code provided as-is, no warranty. Review and adapt for production use
(naming conventions, RBAC, diagnostic settings, address-space planning, etc.).

## Sample Data — Optional Health-Plan Index

Set `DEPLOY_SAMPLE_DATA=true` in your `.env` (or `deploySampleData=true` in the ARM template) to automatically provision a storage account and populate a search index with sample PDF documents from the [Azure-Samples/azure-search-sample-data](https://github.com/Azure-Samples/azure-search-sample-data/tree/main/health-plan) repository.

### What gets created

| Resource | Name | Purpose |
|---|---|---|
| Azure OpenAI resource | `<searchServiceName>-openai` | Hosts the embedding model (skipped if `-OpenAIEndpoint` provided) |
| Model deployment | `text-embedding-3-large` | Generates 3072-dimension vectors for content |
| Storage account | `st<baseName><uniqueString>` | Hosts the PDF blobs |
| Blob container | `health-plan-pdfs` | Contains the 6 sample PDFs |
| Search index | `health-plan-index` | Fields: `id` (key), `title`, `sourceUrl`, `content`, `summary`, `type`, `createdAt`, `contentVector` (3072 dims) |
| Skillset | `ss-health-plan` | AzureOpenAI embedding skill that vectorizes document content |
| Data source | `ds-health-plan-blobs` | Azure Blob data source pointing to the container |
| Indexer | `ixr-health-plan` | Built-in document cracking (PDF → text) + vector enrichment; runs once during setup |

### Sample documents

| File | Description |
|---|---|
| `Benefit_Options.pdf` | Overview of Northwind Health benefit options |
| `Northwind_Health_Plus_Benefits_Details.pdf` | Detailed Health Plus plan benefits |
| `Northwind_Standard_Benefits_Details.pdf` | Detailed Standard plan benefits |
| `PerksPlus.pdf` | PerksPlus wellness program details |
| `employee_handbook.pdf` | General employee handbook |
| `role_library.pdf` | Role descriptions and responsibilities |

### How it works

1. The Bicep template provisions the storage account and blob container (conditional on `deploySampleData=true`).
2. After the infrastructure deployment, `scripts/load-sample-data.ps1` runs automatically (if using the scripted path) or can be invoked manually:

```powershell
./scripts/load-sample-data.ps1
```

The script:
- Creates an Azure OpenAI resource and deploys `text-embedding-3-large` (3072 dimensions) if no `-OpenAIEndpoint` is provided.
- Downloads the 6 PDFs from GitHub.
- Uploads them to the blob container.
- Detects the deployer's public IP and adds it as the **only** allowed IP rule on the search service firewall (the service is never exposed to the full internet).
- Creates the index schema (including `contentVector` field), skillset, data source, and indexer via the Search REST API.
- Waits for the indexer to finish processing all documents (including vector enrichment via the embedding model).
- Removes the IP rule and **restores** `publicNetworkAccess=Disabled` on the search service.

> **Security note:** The search service is only reachable from your single IP
> during setup. No full public access is ever enabled. To skip the restore
> (e.g., for debugging), pass `-SkipPublicAccessRestore`.
>
> **Without vectors:** Pass `-SkipVectorization` to create a keyword-only index
> (no OpenAI resource will be created). Note that Copilot Studio requires
> integrated vectorization.

### Testing with sample data

Once indexed, you can search the health-plan documents from Copilot Studio or the Azure portal Search Explorer:

- **Copilot Studio:** Ask the agent a question like _"What are the PerksPlus benefits?"_ — it will search the index and return results from the indexed PDFs.
- **Search Explorer:** In the Azure portal, open the search service → Indexes → `health-plan-index` → Search Explorer. Enter a query like `benefits` to verify documents are indexed.

## Appendix

### Repository Layout

```
ai-search/
  README.md                                   # this file
  .env.example                                # copy to .env and fill in
  infra/
    main-aisearch.bicep                       # Bicep source template
    azuredeploy-aisearch.json                 # compiled ARM — used by Deploy to Azure button
  scripts/
    deploy-aisearch.ps1                       # provision Azure infra from .env
    load-sample-data.ps1                      # download PDFs + create index/indexer (optional)
  docs/
    aisearch-architecture.drawio              # editable architecture diagram
```

### AI Search SKU Private Endpoint Support

| SKU | Private Endpoint | Max Replicas | Max Partitions | Notes |
|---|---|---|---|---|
| `free` | ❌ Not supported | 1 | 1 | Do not use for PE scenarios |
| `basic` | ✅ | 3 | 1 | Good for dev/test; single partition only |
| `standard` | ✅ | 12 | 12 | Recommended for production |
| `standard2` | ✅ | 12 | 12 | Higher storage and throughput |
| `standard3` | ✅ | 12 | 12 / 3 | HD mode available |

### Key Differences from the Content Understanding Sub-Scenario

| | AI Content Understanding | AI Search |
|---|---|---|
| Azure service | `Microsoft.CognitiveServices/accounts` kind `AIServices` | `Microsoft.Search/searchServices` |
| Private DNS zone | `privatelink.cognitiveservices.azure.com` (+ 2 others) | `privatelink.search.windows.net` |
| PE group ID | `account` | `searchService` |
| Auth | `Ocp-Apim-Subscription-Key` header | `api-key` header (query key or admin key) |
| Copilot Studio integration | Custom connector required | Direct knowledge source (no connector needed) |
| SKU restriction | S0 only (Content Understanding) | Basic or above for PE |
