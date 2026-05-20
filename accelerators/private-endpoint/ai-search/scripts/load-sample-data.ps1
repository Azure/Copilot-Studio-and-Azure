<#
.SYNOPSIS
  Ensures a storage account + container exist, downloads health-plan sample PDFs,
  uploads to blob storage, and creates an Azure AI Search index + indexer.

.DESCRIPTION
  Steps:
    0. Creates the storage account and blob container if they do not already exist.
    1. Downloads 6 PDF files from Azure-Samples/azure-search-sample-data (health-plan).
    2. Uploads them to the blob container.
    3. Opens full public network access on the search service.
    4. Creates index schema, data source, and indexer via the Search REST API.
    5. Waits for the indexer to finish its first run.
    6. Locks down public access to Selected IP addresses (current client IP only).

  Prerequisites:
    - Azure CLI signed in with Contributor on the resource group.
    - Run from the accelerators/private-endpoint/ai-search/ directory.

.PARAMETER ResourceGroup
  Azure resource group name (auto-read from deployment-outputs-aisearch.json if omitted).

.PARAMETER SearchServiceName
  Name of the Azure AI Search service (auto-read from deployment outputs if omitted).

.PARAMETER StorageAccountName
  Name for the sample data storage account. Created if it does not already exist.
  Must be globally unique, 3-24 lowercase alphanumeric characters.

.PARAMETER ContainerName
  Blob container name for PDFs. Default: health-plan-pdfs.

.PARAMETER IndexName
  Name for the search index. Default: health-plan-index.

.PARAMETER OpenAIEndpoint
  Azure OpenAI resource URI (e.g. https://my-openai.openai.azure.com/).
  If omitted, the script creates a new Azure OpenAI resource in the resource group
  and deploys the embedding model automatically.

.PARAMETER OpenAIApiKey
  Azure OpenAI API key. If omitted and -OpenAIEndpoint is not provided,
  the key is retrieved automatically from the newly created resource.

.PARAMETER OpenAIEmbeddingDeployment
  Name of the deployed embedding model. Default: text-embedding-3-large.

.PARAMETER OpenAIModelName
  Underlying model name reported to the vectorizer. Defaults to -OpenAIEmbeddingDeployment.

.PARAMETER EmbeddingDimensions
  Vector dimensions that match the deployed model. Default: 3072 (text-embedding-3-large).
  Use 1536 for text-embedding-3-small or ada-002.

.PARAMETER SkipPublicAccessRestore
  If set, leaves public access fully open after indexing (useful for debugging).

.PARAMETER SkipVectorization
  If set, skips OpenAI resource creation and vectorization entirely.

.EXAMPLE
  # Auto-create Azure OpenAI resource with integrated vectorization (default)
  ./scripts/load-sample-data.ps1 -ResourceGroup rg-myai -SearchServiceName srch-myai `
      -StorageAccountName stmyaisample

  # With existing OpenAI resource (skips resource creation)
  ./scripts/load-sample-data.ps1 -ResourceGroup rg-myai -SearchServiceName srch-myai `
      -StorageAccountName stmyaisample `
      -OpenAIEndpoint https://my-openai.openai.azure.com/ `
      -OpenAIApiKey <key>

  # Without vectors (Copilot Studio will show 'unsupported index')
  ./scripts/load-sample-data.ps1 -ResourceGroup rg-myai -SearchServiceName srch-myai `
      -StorageAccountName stmyaisample -SkipVectorization
#>
[CmdletBinding()]
param(
  [string] $ResourceGroup,
  [string] $SearchServiceName,
  [string] $StorageAccountName,
  [string] $ContainerName = 'health-plan-pdfs',
  [string] $IndexName = 'health-plan-index',
  # Integrated vectorization (required for Copilot Studio)
  [string] $OpenAIEndpoint,
  [string] $OpenAIApiKey,
  [string] $OpenAIEmbeddingDeployment = 'text-embedding-3-large',
  [string] $OpenAIModelName,
  [int]    $EmbeddingDimensions = 3072,
  [switch] $SkipPublicAccessRestore,
  [switch] $SkipVectorization
)

$ErrorActionPreference = 'Stop'

# ---------------------------------------------------------------------------
# Load deployment outputs if parameters not supplied
# ---------------------------------------------------------------------------
$outputsFile = Join-Path $PSScriptRoot 'deployment-outputs-aisearch.json'
if (Test-Path $outputsFile) {
  $outputs = Get-Content $outputsFile | ConvertFrom-Json
  if (-not $ResourceGroup)      { $ResourceGroup      = $outputs.resourceGroup }
  if (-not $SearchServiceName)  { $SearchServiceName  = $outputs.searchServiceName }
  if (-not $StorageAccountName) { $StorageAccountName = $outputs.sampleStorageAccountName }
}

foreach ($v in @('ResourceGroup', 'SearchServiceName', 'StorageAccountName')) {
  if (-not (Get-Variable -Name $v -ValueOnly -ErrorAction SilentlyContinue)) {
    throw "Missing required parameter '$v'. Provide it explicitly or run the Bicep deployment first."
  }
}

# Decide whether to enable integrated vectorization
if ($SkipVectorization) {
  $useVectors = $false
  Write-Warning "SkipVectorization set. Index will be created WITHOUT vector embeddings."
  Write-Warning "Copilot Studio requires integrated vectorization."
} elseif ($OpenAIEndpoint) {
  # User provided an existing OpenAI resource
  $useVectors = $true
  if (-not $OpenAIApiKey) {
    throw "When -OpenAIEndpoint is provided, -OpenAIApiKey is also required."
  }
  if (-not $OpenAIModelName) { $OpenAIModelName = $OpenAIEmbeddingDeployment }
  Write-Host "==> Integrated vectorization ENABLED using existing OpenAI resource" -ForegroundColor Cyan
  Write-Host "    Endpoint: $OpenAIEndpoint" -ForegroundColor Cyan
  Write-Host "    Model: $OpenAIModelName, Dimensions: $EmbeddingDimensions" -ForegroundColor Cyan
} else {
  # Create a new Azure OpenAI resource
  $useVectors = $true
  if (-not $OpenAIModelName) { $OpenAIModelName = $OpenAIEmbeddingDeployment }
  $rgLocation = if ($rgLocation) { $rgLocation } else { az group show -n $ResourceGroup --query location -o tsv }
  $openAIAccountName = "$($SearchServiceName)-openai"
  # Truncate to 64 chars (Azure OpenAI name limit)
  if ($openAIAccountName.Length -gt 64) { $openAIAccountName = $openAIAccountName.Substring(0, 64) }

  Write-Host "==> Checking Azure OpenAI resource '$openAIAccountName'" -ForegroundColor Cyan
  $existingOpenAI = az cognitiveservices account show -n $openAIAccountName -g $ResourceGroup --query id -o tsv 2>$null
  if (-not $existingOpenAI) {
    Write-Host "    Azure OpenAI resource not found -- creating it in '$ResourceGroup'" -ForegroundColor Yellow
    az cognitiveservices account create `
      --name $openAIAccountName `
      --resource-group $ResourceGroup `
      --location $rgLocation `
      --kind OpenAI `
      --sku S0 `
      --custom-domain $openAIAccountName `
      --only-show-errors | Out-Null
    if ($LASTEXITCODE -ne 0) { throw "Failed to create Azure OpenAI resource '$openAIAccountName'." }
    Write-Host "    Azure OpenAI resource '$openAIAccountName' created." -ForegroundColor Green
  } else {
    Write-Host "    Azure OpenAI resource '$openAIAccountName' already exists."
  }

  # Deploy embedding model
  Write-Host "==> Deploying model '$OpenAIModelName' as deployment '$OpenAIEmbeddingDeployment'" -ForegroundColor Cyan
  $existingDeployment = az cognitiveservices account deployment show `
    -n $openAIAccountName -g $ResourceGroup `
    --deployment-name $OpenAIEmbeddingDeployment `
    --query name -o tsv 2>$null
  if (-not $existingDeployment) {
    Write-Host "    Deployment not found -- creating '$OpenAIEmbeddingDeployment'" -ForegroundColor Yellow
    # Use ARM REST API directly because the CLI may not support GlobalStandard sku
    $subId = az account show --query id -o tsv
    $deployToken = az account get-access-token --resource 'https://management.azure.com/' --query accessToken -o tsv
    $deployUri = "https://management.azure.com/subscriptions/$subId/resourceGroups/$ResourceGroup/providers/Microsoft.CognitiveServices/accounts/$openAIAccountName/deployments/$OpenAIEmbeddingDeployment`?api-version=2024-06-01-preview"
    $deployBody = @{
      sku = @{ name = 'GlobalStandard'; capacity = 120 }
      properties = @{
        model = @{
          format  = 'OpenAI'
          name    = $OpenAIModelName
          version = '1'
        }
      }
    } | ConvertTo-Json -Depth 5
    $deployHeaders = @{ 'Authorization' = "Bearer $deployToken"; 'Content-Type' = 'application/json' }
    try {
      $deployResp = Invoke-RestMethod -Method PUT -Uri $deployUri -Headers $deployHeaders -Body $deployBody
      Write-Host "    Model deployment '$OpenAIEmbeddingDeployment' created (state: $($deployResp.properties.provisioningState))." -ForegroundColor Green
    } catch {
      throw "Failed to deploy model '$OpenAIModelName': $($_.Exception.Message)"
    }

    # Wait for deployment to become ready
    if ($deployResp.properties.provisioningState -ne 'Succeeded') {
      Write-Host "    Waiting for deployment to reach 'Succeeded' state..." -ForegroundColor Yellow
      $deployWait = 0
      $deployMaxWait = 120
      do {
        Start-Sleep -Seconds 10
        $deployWait += 10
        $provState = az cognitiveservices account deployment show `
          -n $openAIAccountName -g $ResourceGroup `
          --deployment-name $OpenAIEmbeddingDeployment `
          --query "properties.provisioningState" -o tsv 2>$null
        Write-Host "      provisioning state: $provState ($deployWait s)"
      } while ($provState -ne 'Succeeded' -and $deployWait -lt $deployMaxWait)
      if ($provState -ne 'Succeeded') {
        Write-Warning "Deployment did not reach 'Succeeded' within $deployMaxWait s (current: $provState). Vectorization may fail."
      }
    }
  } else {
    Write-Host "    Deployment '$OpenAIEmbeddingDeployment' already exists."
  }

  # Retrieve endpoint and key from the new resource
  $OpenAIEndpoint = az cognitiveservices account show -n $openAIAccountName -g $ResourceGroup --query "properties.endpoint" -o tsv
  $OpenAIApiKey = az cognitiveservices account keys list -n $openAIAccountName -g $ResourceGroup --query "key1" -o tsv
  if (-not $OpenAIEndpoint -or -not $OpenAIApiKey) {
    throw "Failed to retrieve endpoint or key from Azure OpenAI resource '$openAIAccountName'."
  }
  Write-Host "    Endpoint: $OpenAIEndpoint" -ForegroundColor Cyan
  Write-Host "    Model: $OpenAIModelName, Dimensions: $EmbeddingDimensions" -ForegroundColor Cyan
}

# ---------------------------------------------------------------------------
# 0. Ensure storage account and container exist
# ---------------------------------------------------------------------------
Write-Host "==> Checking storage account '$StorageAccountName'" -ForegroundColor Cyan
$existingStorage = az storage account show -n $StorageAccountName -g $ResourceGroup --query id -o tsv 2>$null
if (-not $existingStorage) {
  Write-Host "    Storage account not found — creating it in resource group '$ResourceGroup'" -ForegroundColor Yellow
  $rgLocation = az group show -n $ResourceGroup --query location -o tsv
  az storage account create `
    --name $StorageAccountName `
    --resource-group $ResourceGroup `
    --location $rgLocation `
    --sku Standard_LRS `
    --kind StorageV2 `
    --min-tls-version TLS1_2 `
    --https-only true `
    --allow-blob-public-access false `
    --only-show-errors | Out-Null
  Write-Host "    Storage account '$StorageAccountName' created." -ForegroundColor Green
} else {
  Write-Host "    Storage account '$StorageAccountName' already exists."
}

Write-Host "==> Checking blob container '$ContainerName'" -ForegroundColor Cyan
$existingContainer = az storage container show --name $ContainerName --account-name $StorageAccountName --auth-mode login --query name -o tsv 2>$null
if (-not $existingContainer) {
  Write-Host "    Container not found — creating '$ContainerName'" -ForegroundColor Yellow
  az storage container create `
    --name $ContainerName `
    --account-name $StorageAccountName `
    --auth-mode login `
    --only-show-errors | Out-Null
  Write-Host "    Container '$ContainerName' created." -ForegroundColor Green
} else {
  Write-Host "    Container '$ContainerName' already exists."
}

# ---------------------------------------------------------------------------
# 1. Download sample PDFs from GitHub
# ---------------------------------------------------------------------------
$pdfFiles = @(
  'Benefit_Options.pdf',
  'Northwind_Health_Plus_Benefits_Details.pdf',
  'Northwind_Standard_Benefits_Details.pdf',
  'PerksPlus.pdf',
  'employee_handbook.pdf',
  'role_library.pdf'
)

$baseUrl = 'https://raw.githubusercontent.com/Azure-Samples/azure-search-sample-data/main/health-plan'
$tempDir = Join-Path ([System.IO.Path]::GetTempPath()) 'aisearch-sample-pdfs'

if (-not (Test-Path $tempDir)) { New-Item -ItemType Directory -Path $tempDir | Out-Null }

Write-Host "==> Downloading sample PDFs from GitHub" -ForegroundColor Cyan
foreach ($file in $pdfFiles) {
  $dest = Join-Path $tempDir $file
  if (-not (Test-Path $dest)) {
    Write-Host "    $file"
    Invoke-WebRequest -Uri "$baseUrl/$file" -OutFile $dest -UseBasicParsing
  } else {
    Write-Host "    $file (cached)"
  }
}

# ---------------------------------------------------------------------------
# 2. Upload PDFs to blob storage
# ---------------------------------------------------------------------------
Write-Host "==> Uploading PDFs to storage account '$StorageAccountName' container '$ContainerName'" -ForegroundColor Cyan

$storageKey = (az storage account keys list -g $ResourceGroup -n $StorageAccountName --query '[0].value' -o tsv)
if ($LASTEXITCODE -ne 0) { throw "Failed to retrieve storage account key." }

foreach ($file in $pdfFiles) {
  $filePath = Join-Path $tempDir $file
  az storage blob upload `
    --account-name $StorageAccountName `
    --account-key $storageKey `
    --container-name $ContainerName `
    --file $filePath `
    --name $file `
    --overwrite true `
    --only-show-errors | Out-Null
  Write-Host "    uploaded: $file"
}

# ---------------------------------------------------------------------------
# 3. Open public access on the search service so we can call the REST API
# ---------------------------------------------------------------------------
Write-Host "==> Enabling full public network access on '$SearchServiceName' for indexing" -ForegroundColor Cyan
$subId = az account show --query id -o tsv
$mgmtBase = "https://management.azure.com/subscriptions/$subId/resourceGroups/$ResourceGroup/providers/Microsoft.Search/searchServices/$SearchServiceName"
$searchMgmtApi = '2023-11-01'

# Get ARM bearer token — avoids az rest quoting issues on Windows
$armToken = az account get-access-token --resource 'https://management.azure.com/' --query accessToken -o tsv
$mgmtHeaders = @{
  'Authorization' = "Bearer $armToken"
  'Content-Type'  = 'application/json'
}

# Clear IP rules and set publicNetworkAccess=enabled -> "All networks"
$openBody = '{"properties":{"networkRuleSet":{"ipRules":[]},"publicNetworkAccess":"enabled"}}'
Invoke-RestMethod -Method PATCH `
    -Uri "${mgmtBase}?api-version=$searchMgmtApi" `
    -Headers $mgmtHeaders `
    -Body $openBody | Out-Null

# Wait for the change to propagate (Azure AI Search updates take up to 60 s)
Write-Host "    Waiting 60 s for network access change to propagate..."
Start-Sleep -Seconds 60

# ---------------------------------------------------------------------------
# 4. Get admin key and build REST headers
# ---------------------------------------------------------------------------
$adminKey = (az search admin-key show -g $ResourceGroup --service-name $SearchServiceName --query 'primaryKey' -o tsv)
if ($LASTEXITCODE -ne 0) { throw "Failed to retrieve search admin key." }

$searchEndpoint = "https://$SearchServiceName.search.windows.net"
$apiVersion = '2024-07-01'
$headers = @{
  'api-key'      = $adminKey
  'Content-Type' = 'application/json'
}

# Helper: retry a REST call up to 5 times with 15-s back-off on 403/429
function Invoke-SearchRest {
  param([string]$Method, [string]$Uri, [hashtable]$Headers, [string]$Body)
  $attempt = 0
  $maxAttempts = 5
  do {
    $attempt++
    try {
      $params = @{ Method = $Method; Uri = $Uri; Headers = $Headers; ErrorAction = 'Stop' }
      if ($Body) { $params.Body = $Body }
      return Invoke-RestMethod @params
    } catch {
      $status = $_.Exception.Response.StatusCode.value__
      if ($status -in @(403, 429) -and $attempt -lt $maxAttempts) {
        Write-Host "      [attempt $attempt] HTTP $status - waiting 15 s for firewall to propagate..." -ForegroundColor Yellow
        Start-Sleep -Seconds 15
      } else {
        throw
      }
    }
  } while ($attempt -lt $maxAttempts)
}

# ---------------------------------------------------------------------------
# 5. Create index schema
# ---------------------------------------------------------------------------
Write-Host "==> Creating search index '$IndexName'" -ForegroundColor Cyan

$indexFields = @(
  @{ name = 'id';        type = 'Edm.String'; searchable = $true;  filterable = $true;  sortable = $false; facetable = $false; key = $true;  retrievable = $true; analyzer = 'keyword' }
  @{ name = 'parent_id'; type = 'Edm.String'; searchable = $false; filterable = $true;  sortable = $false; facetable = $false; key = $false; retrievable = $true }
  @{ name = 'title';     type = 'Edm.String'; searchable = $true;  filterable = $false; sortable = $false; facetable = $false; key = $false; retrievable = $true;  analyzer = 'standard.lucene' }
  @{ name = 'sourceUrl'; type = 'Edm.String'; searchable = $false; filterable = $false; sortable = $false; facetable = $false; key = $false; retrievable = $true }
  @{ name = 'content';   type = 'Edm.String'; searchable = $true;  filterable = $false; sortable = $false; facetable = $false; key = $false; retrievable = $true;  analyzer = 'standard.lucene' }
  @{ name = 'summary';   type = 'Edm.String'; searchable = $true;  filterable = $false; sortable = $false; facetable = $false; key = $false; retrievable = $true;  analyzer = 'standard.lucene' }
  @{ name = 'type';      type = 'Edm.String'; searchable = $false; filterable = $true;  sortable = $false; facetable = $false; key = $false; retrievable = $true }
  @{ name = 'createdAt'; type = 'Edm.DateTimeOffset'; searchable = $false; filterable = $true; sortable = $true; facetable = $false; key = $false; retrievable = $true }
)

$indexDef = @{ name = $IndexName; fields = $indexFields }

if ($useVectors) {
  $indexDef.fields += @{
    name                = 'contentVector'
    type                = 'Collection(Edm.Single)'
    searchable          = $true
    retrievable         = $false
    dimensions          = $EmbeddingDimensions
    vectorSearchProfile = 'hp-vector-profile'
  }
  $indexDef.vectorSearch = @{
    algorithms = @(
      @{ name = 'hp-hnsw'; kind = 'hnsw'; hnswParameters = @{ metric = 'cosine' } }
    )
    profiles = @(
      @{ name = 'hp-vector-profile'; algorithm = 'hp-hnsw'; vectorizer = 'hp-oai-vectorizer' }
    )
    vectorizers = @(
      @{
        name = 'hp-oai-vectorizer'
        kind = 'azureOpenAI'
        azureOpenAIParameters = @{
          resourceUri  = $OpenAIEndpoint.TrimEnd('/')
          deploymentId = $OpenAIEmbeddingDeployment
          apiKey       = $OpenAIApiKey
          modelName    = $OpenAIModelName
        }
      }
    )
  }
}

$resp = Invoke-SearchRest -Method PUT `
  -Uri "$searchEndpoint/indexes/$($IndexName)?api-version=$apiVersion" `
  -Headers $headers `
  -Body ($indexDef | ConvertTo-Json -Depth 15)
Write-Host "    index created: $($resp.name)"

# ---------------------------------------------------------------------------
# 5a. Create skillset (only when vectorization is enabled)
# ---------------------------------------------------------------------------
if ($useVectors) {
  Write-Host "==> Creating skillset 'ss-health-plan' (split + AzureOpenAI embedding)" -ForegroundColor Cyan
  $skillsetDef = @{
    name   = 'ss-health-plan'
    skills = @(
      @{
        '@odata.type'     = '#Microsoft.Skills.Text.SplitSkill'
        name              = 'hp-split-skill'
        context           = '/document'
        textSplitMode     = 'pages'
        maximumPageLength  = 2000
        pageOverlapLength  = 500
        inputs            = @( @{ name = 'text'; source = '/document/content' } )
        outputs           = @( @{ name = 'textItems'; targetName = 'pages' } )
      }
      @{
        '@odata.type' = '#Microsoft.Skills.Text.AzureOpenAIEmbeddingSkill'
        name          = 'hp-embedding-skill'
        context       = '/document/pages/*'
        resourceUri   = $OpenAIEndpoint.TrimEnd('/')
        apiKey        = $OpenAIApiKey
        deploymentId  = $OpenAIEmbeddingDeployment
        modelName     = $OpenAIModelName
        dimensions    = $EmbeddingDimensions
        inputs        = @( @{ name = 'text'; source = '/document/pages/*' } )
        outputs       = @( @{ name = 'embedding'; targetName = 'contentVector' } )
      }
    )
    indexProjections = @{
      selectors = @(
        @{
          targetIndexName    = $IndexName
          parentKeyFieldName = 'parent_id'
          sourceContext       = '/document/pages/*'
          mappings           = @(
            @{ name = 'content';       source = '/document/pages/*' }
            @{ name = 'contentVector'; source = '/document/pages/*/contentVector' }
            @{ name = 'title';         source = '/document/metadata_storage_name' }
            @{ name = 'sourceUrl';     source = '/document/metadata_storage_path' }
            @{ name = 'type';          source = '/document/metadata_content_type' }
            @{ name = 'createdAt';     source = '/document/metadata_storage_last_modified' }
          )
        }
      )
      parameters = @{ projectionMode = 'skipIndexingParentDocuments' }
    }
  }
  $resp = Invoke-SearchRest -Method PUT `
    -Uri "$searchEndpoint/skillsets/ss-health-plan?api-version=$apiVersion" `
    -Headers $headers `
    -Body ($skillsetDef | ConvertTo-Json -Depth 15)
  Write-Host "    skillset created: $($resp.name)"
}

# ---------------------------------------------------------------------------
# 6. Create data source
# ---------------------------------------------------------------------------
Write-Host "==> Creating data source 'ds-health-plan-blobs'" -ForegroundColor Cyan

$storageConnStr = "DefaultEndpointsProtocol=https;AccountName=$StorageAccountName;AccountKey=$storageKey;EndpointSuffix=core.windows.net"

$dataSourceDef = @{
  name = 'ds-health-plan-blobs'
  type = 'azureblob'
  credentials = @{ connectionString = $storageConnStr }
  container = @{ name = $ContainerName }
} | ConvertTo-Json -Depth 10

$resp = Invoke-SearchRest -Method PUT `
  -Uri "$searchEndpoint/datasources/ds-health-plan-blobs?api-version=$apiVersion" `
  -Headers $headers `
  -Body $dataSourceDef
Write-Host "    data source created: $($resp.name)"

# ---------------------------------------------------------------------------
# 7. Create indexer (uses built-in document cracking for PDFs)
# ---------------------------------------------------------------------------
Write-Host "==> Creating indexer 'ixr-health-plan'" -ForegroundColor Cyan

$indexerDef = @{
  name            = 'ixr-health-plan'
  dataSourceName  = 'ds-health-plan-blobs'
  targetIndexName = $IndexName
  parameters      = @{
    configuration = @{
      dataToExtract = 'contentAndMetadata'
      parsingMode   = 'default'
    }
  }
}

if ($useVectors) {
  $indexerDef.skillsetName = 'ss-health-plan'
  # Index projections in the skillset handle all field mappings for chunked output.
  # No fieldMappings or outputFieldMappings needed — projections map source fields directly.
} else {
  # Without vectors: map blob metadata to index fields directly
  $indexerDef.fieldMappings = @(
    @{
      sourceFieldName = 'metadata_storage_path'
      targetFieldName = 'id'
      mappingFunction = @{ name = 'base64Encode' }
    }
    @{
      sourceFieldName = 'metadata_storage_name'
      targetFieldName = 'title'
    }
    @{
      sourceFieldName = 'metadata_storage_path'
      targetFieldName = 'sourceUrl'
    }
    @{
      sourceFieldName = 'metadata_content_type'
      targetFieldName = 'type'
    }
    @{
      sourceFieldName = 'metadata_storage_last_modified'
      targetFieldName = 'createdAt'
    }
  )
}

$resp = Invoke-SearchRest -Method PUT `
  -Uri "$searchEndpoint/indexers/ixr-health-plan?api-version=$apiVersion" `
  -Headers $headers `
  -Body ($indexerDef | ConvertTo-Json -Depth 10)
Write-Host "    indexer created: $($resp.name)"

# ---------------------------------------------------------------------------
# 8. Wait for indexer to finish
# ---------------------------------------------------------------------------
Write-Host "==> Waiting for indexer run to complete..." -ForegroundColor Cyan
$maxWait = if ($useVectors) { 600 } else { 180 }  # seconds; vector indexing calls Azure OpenAI per chunk
$elapsed = 0
$pollInterval = 10

do {
  Start-Sleep -Seconds $pollInterval
  $elapsed += $pollInterval
  $status = Invoke-SearchRest -Method GET `
    -Uri "$searchEndpoint/indexers/ixr-health-plan/status?api-version=$apiVersion" `
    -Headers $headers

  $lastRun = $status.lastResult
  $runStatus = if ($lastRun) { $lastRun.status } else { 'running' }
  Write-Host "    status: $runStatus ($elapsed s elapsed)"
} while ($runStatus -notin @('success', 'transientFailure', 'persistentFailure') -and $elapsed -lt $maxWait)

if ($runStatus -eq 'success') {
  $docCount = $lastRun.itemsProcessed
  Write-Host "    Indexing complete: $docCount documents indexed." -ForegroundColor Green
} else {
  Write-Warning "Indexer did not complete successfully (status: $runStatus). Check the indexer in the Azure Portal for details."
}

# ---------------------------------------------------------------------------
# 9. Lock down: switch to Selected IP addresses, add current client IP
# ---------------------------------------------------------------------------
if (-not $SkipPublicAccessRestore) {
  Write-Host "==> Detecting current client public IP" -ForegroundColor Cyan
  $clientIp = (Invoke-RestMethod -Uri 'https://api.ipify.org' -UseBasicParsing).Trim()
  Write-Host "    Client IP: $clientIp"

  Write-Host "==> Setting '$SearchServiceName' to Selected IP addresses, allowing $clientIp" -ForegroundColor Cyan
  # Refresh token — the previous one may have expired during indexing
  $armToken = az account get-access-token --resource 'https://management.azure.com/' --query accessToken -o tsv
  $lockHeaders = @{
    'Authorization' = "Bearer $armToken"
    'Content-Type'  = 'application/json'
  }
  $lockBody = "{""properties"":{""networkRuleSet"":{""ipRules"":[{""value"":""$clientIp""}]},""publicNetworkAccess"":""enabled""}}"
  Invoke-RestMethod -Method PATCH `
      -Uri "${mgmtBase}?api-version=$searchMgmtApi" `
      -Headers $lockHeaders `
      -Body $lockBody | Out-Null
  Write-Host "    Public access set to Selected IP addresses. Allowed: $clientIp" -ForegroundColor Green
} else {
  Write-Warning "SkipPublicAccessRestore set — search service remains fully open. Lock it down manually."
}

Write-Host ""
if ($useVectors) {
  Write-Host "Sample data loaded. Index '$IndexName' is ready with vector embeddings (Copilot Studio compatible)." -ForegroundColor Green
} else {
  Write-Host "Sample data loaded. Index '$IndexName' is ready (keyword search only)." -ForegroundColor Green
  Write-Host "Re-run with -OpenAIEndpoint and -OpenAIApiKey to add integrated vectorization for Copilot Studio." -ForegroundColor Yellow
}
Write-Host "You can test in Copilot Studio or Search Explorer with: search=health AND indexName=$IndexName" -ForegroundColor Green
Write-Host ""
Write-Host "NOTE: Firewall rule changes take 1-3 minutes to propagate." -ForegroundColor Yellow
Write-Host "      If the Azure portal shows 403 when browsing indexes, wait a moment and refresh." -ForegroundColor Yellow
Write-Host "      If it persists, temporarily set the service to 'All networks', browse, then lock back down." -ForegroundColor Yellow
