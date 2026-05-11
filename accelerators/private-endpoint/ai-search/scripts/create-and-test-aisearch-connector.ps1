<#
.SYNOPSIS
  Creates / updates the "Azure AI Search (Private)" custom connector in the
  selected Power Platform environment using pac CLI, then runs a connectivity
  test against the deployed AI Search service.

.DESCRIPTION
  - Resolves the deployed AI Search service in one of two ways:
      1. Reads scripts/deployment-outputs-aisearch.json (produced by deploy-aisearch.ps1), or
      2. Falls back to ARM deployment discovery: pass -ResourceGroup and the script
         discovers the Search service in the resource group.
  - Patches the swagger `host` field with the real AI Search hostname.
  - Pushes the connector via `pac connector create`.
  - Runs a connectivity unit test:
      GET https://<name>.search.windows.net/indexes?api-version=2024-07-01
    From the public internet this should return 403/401 (confirms lockdown).
    From inside the VNet (or from a Power Automate flow in the linked environment)
    this should return 200.

.PARAMETER OutputsFile
  Path to deployment-outputs-aisearch.json. Defaults to scripts/deployment-outputs-aisearch.json.

.PARAMETER ResourceGroup
  Resource group to discover the AI Search service from (used when OutputsFile is missing).

.PARAMETER SubscriptionId
  Azure subscription ID (defaults to current az login context).

.PARAMETER ConnectorDisplayName
  Display name for the custom connector in Power Platform.

.PARAMETER SkipConnectorCreate
  If specified, skips the pac connector create step (useful to re-run only the test).

.PARAMETER InsideVnetTest
  If specified, treats a non-200 response as a failure (use from inside the VNet).

.EXAMPLE
  # Full create + test from outside VNet (expects lockdown 403)
  ./scripts/create-and-test-aisearch-connector.ps1 -ResourceGroup my-rg

  # Only test (connector already pushed)
  ./scripts/create-and-test-aisearch-connector.ps1 -SkipConnectorCreate -ResourceGroup my-rg

  # Test from a jump-box inside snet-pe (expects 200)
  ./scripts/create-and-test-aisearch-connector.ps1 -InsideVnetTest -ResourceGroup my-rg
#>
[CmdletBinding()]
param(
  [string] $OutputsFile = (Join-Path $PSScriptRoot 'deployment-outputs-aisearch.json'),
  [string] $ResourceGroup,
  [string] $SubscriptionId,
  [string] $ConnectorDisplayName = 'Azure AI Search (Private)',
  [switch] $SkipConnectorCreate,
  [switch] $InsideVnetTest
)

$ErrorActionPreference = 'Stop'

# ---------------------------------------------------------------------------
# Resolve AI Search service name and endpoint
# ---------------------------------------------------------------------------
$searchName     = $null
$searchEndpoint = $null
$rg             = $ResourceGroup
$subId          = $SubscriptionId

if (Test-Path $OutputsFile) {
  $out            = Get-Content $OutputsFile | ConvertFrom-Json
  $searchName     = $out.searchServiceName
  $searchEndpoint = $out.searchServiceEndpoint
  $rg             = if ($ResourceGroup) { $ResourceGroup } else { $out.resourceGroup }
  $subId          = if ($SubscriptionId) { $SubscriptionId } else { $out.subscriptionId }
} else {
  Write-Host "Outputs file '$OutputsFile' not found — falling back to ARM deployment discovery." -ForegroundColor Yellow

  if (-not $ResourceGroup) {
    $ResourceGroup = Read-Host 'Resource group name (where azuredeploy-aisearch.json was deployed)'
  }
  if (-not $subId) { $subId = az account show --query id -o tsv }
  if (-not $subId) { throw 'Could not resolve subscription. Run `az login` or pass -SubscriptionId.' }

  Write-Host "==> Using subscription $subId" -ForegroundColor Cyan
  az account set --subscription $subId | Out-Null

  # Try to read outputs from the most recent succeeded deployment.
  $depName = az deployment group list -g $ResourceGroup `
      --query "sort_by([?properties.provisioningState=='Succeeded'], &properties.timestamp)[-1].name" -o tsv 2>$null

  if ($depName) {
    Write-Host "==> Reading outputs from deployment '$depName'" -ForegroundColor Cyan
    $depJson = az deployment group show -g $ResourceGroup -n $depName --query 'properties.outputs' -o json 2>$null
    if ($LASTEXITCODE -eq 0 -and $depJson -and $depJson -ne 'null') {
      $dep = $depJson | ConvertFrom-Json
      if ($dep.searchServiceName)     { $searchName     = $dep.searchServiceName.value }
      if ($dep.searchServiceEndpoint) { $searchEndpoint = $dep.searchServiceEndpoint.value }
    }
  }

  # Fallback: query the resource group directly for a Search service.
  if (-not $searchName) {
    Write-Host "==> Discovering AI Search service in resource group $ResourceGroup" -ForegroundColor Cyan
    $accounts = az search service list -g $ResourceGroup --query '[].{name:name}' -o json 2>$null | ConvertFrom-Json
    if (-not $accounts -or $accounts.Count -eq 0) {
      throw "No Azure AI Search service found in resource group '$ResourceGroup'. Verify the deployment finished and -ResourceGroup is correct."
    }
    if ($accounts.Count -gt 1) {
      throw "Multiple AI Search services found in '$ResourceGroup': $(($accounts | ForEach-Object { $_.name }) -join ', '). Re-run with a valid -OutputsFile."
    }
    $searchName     = $accounts[0].name
    $searchEndpoint = "https://$($searchName).search.windows.net/"
  }

  $rg    = $ResourceGroup
  $subId = $subId
}

if (-not $searchName -or -not $searchEndpoint) {
  throw 'Could not resolve AI Search service name/endpoint. Supply -OutputsFile or -ResourceGroup.'
}

$hostname = ([Uri]$searchEndpoint).Host
Write-Host "==> Target service: $searchName  ($hostname)" -ForegroundColor Cyan

# ---------------------------------------------------------------------------
# Patch swagger host and write generated connector file
# ---------------------------------------------------------------------------
$repoRoot   = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
$swaggerSrc = Join-Path (Split-Path -Parent $PSScriptRoot) 'powerplatform\aisearch-connector.swagger.json'
$swaggerOut = Join-Path (Split-Path -Parent $PSScriptRoot) 'powerplatform\aisearch-connector.generated.json'

if (-not (Test-Path $swaggerSrc)) {
  throw "Swagger source not found: $swaggerSrc"
}

(Get-Content $swaggerSrc -Raw).Replace('REPLACE_WITH_SEARCH_HOSTNAME', $hostname) |
  Set-Content $swaggerOut -Encoding UTF8
Write-Host "==> Generated $swaggerOut" -ForegroundColor Green

# ---------------------------------------------------------------------------
# Create / update the custom connector via pac CLI
# ---------------------------------------------------------------------------
if (-not $SkipConnectorCreate) {
  $apiPropsFile = Join-Path (Split-Path -Parent $PSScriptRoot) 'powerplatform\apiProperties-aisearch.json'
  Write-Host "==> Creating custom connector via pac CLI" -ForegroundColor Cyan
  pac connector create `
      --api-definition-file $swaggerOut `
      --api-properties-file $apiPropsFile
  if ($LASTEXITCODE -ne 0) {
    throw "pac connector create failed (exit $LASTEXITCODE)."
  }
  Write-Host "==> Connector created / updated." -ForegroundColor Green
}

# ---------------------------------------------------------------------------
# Connectivity unit test
# ---------------------------------------------------------------------------
Write-Host ""
Write-Host "==> Connectivity test: GET https://$hostname/indexes?api-version=2024-07-01" -ForegroundColor Cyan

# Fetch admin key to test the data plane (admin key works for query operations too).
# In production, use the query key. Admin key is used here only for CI/CD testing.
$adminKey = az search admin-key show -g $rg --service-name $searchName --subscription $subId --query primaryKey -o tsv 2>$null
if (-not $adminKey) {
  Write-Warning "Could not retrieve admin key for '$searchName' (may lack RBAC). Skipping authenticated test."
  Write-Host "To test manually:"
  Write-Host "  Invoke-WebRequest -Uri 'https://$hostname/indexes?api-version=2024-07-01' -Headers @{ 'api-key' = '<your-query-key>' }"
  exit 0
}

$uri = "https://$hostname/indexes?api-version=2024-07-01"
try {
  $resp = Invoke-WebRequest -Uri $uri -Headers @{ 'api-key' = $adminKey } -UseBasicParsing -TimeoutSec 30
  Write-Host "PASS  HTTP $($resp.StatusCode) — data plane reachable from this host." -ForegroundColor Green
  $json = $resp.Content | ConvertFrom-Json
  $count = if ($json.value) { $json.value.Count } else { 0 }
  Write-Host "      Index count: $count"
  if ($count -gt 0) {
    Write-Host "      Indexes: $(($json.value | ForEach-Object { $_.name }) -join ', ')"
  }
} catch {
  $code = $_.Exception.Response.StatusCode.value__
  if ($InsideVnetTest) {
    Write-Host "FAIL  HTTP $code from inside VNet. Check DNS resolution, NSG rules, and PE connection status." -ForegroundColor Red
    throw
  } else {
    if ($code -in 403, 401) {
      Write-Host "EXPECTED FAIL  HTTP $code from public internet — confirms private-endpoint lockdown is working." -ForegroundColor Yellow
      Write-Host "  Re-run with -InsideVnetTest from a VM in snet-pe, or validate from a Power Automate flow." -ForegroundColor Yellow
    } else {
      Write-Host "UNEXPECTED FAIL  HTTP $code — investigate the error." -ForegroundColor Red
      Write-Host $_.Exception.Message -ForegroundColor Red
    }
  }
}

Write-Host ""
Write-Host "Next steps:" -ForegroundColor Cyan
Write-Host "  1. In the linked Power Platform environment, create a flow with an Instant trigger."
Write-Host "  2. Add a 'Search Documents' action from the '$ConnectorDisplayName' connector."
Write-Host "  3. Create a new connection using a Query API key (Azure Portal → AI Search → Keys → Query keys)."
Write-Host "  4. Set indexName and search='*'. Run the flow — a 200 response confirms end-to-end connectivity."
