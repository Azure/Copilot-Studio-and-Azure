<#
.SYNOPSIS
  Creates / updates the "Azure Content Understanding" custom connector in the
  selected Power Platform environment using pac CLI, then runs a connectivity
  unit test against the deployed AI Services account.

.DESCRIPTION
  - Reads scripts/deployment-outputs.json (produced by deploy.ps1).
  - Patches the swagger `host` with the actual AI Services hostname.
  - Pushes the connector via `pac connector create`.
  - Invokes the connector's ListAnalyzers operation directly against the
    AI Services REST API as a connectivity unit test (HTTP 200 expected when
    called from inside the VNet OR with a valid key from a permitted IP).

  Notes:
    - From your laptop the call WILL FAIL with 403 if you've deployed with
      publicNetworkAccess=Disabled (expected). That confirms the lockdown is
      working. Run -InsideVnetTest from a VM inside the VNet for an end-to-end
      green test, or run from a Power Automate flow once the Enterprise Policy
      is linked.
#>
[CmdletBinding()]
param(
  [string] $OutputsFile = (Join-Path $PSScriptRoot 'deployment-outputs.json'),
  [string] $ConnectorDisplayName = 'Azure Content Understanding (Private)',
  [switch] $SkipConnectorCreate,
  [switch] $InsideVnetTest
)

$ErrorActionPreference = 'Stop'

if (-not (Test-Path $OutputsFile)) {
  throw "Outputs file '$OutputsFile' not found. Run scripts/deploy.ps1 first."
}
$out = Get-Content $OutputsFile | ConvertFrom-Json

$aiName     = $out.aiAccountName
$aiEndpoint = $out.aiAccountEndpoint   # e.g. https://ais-xxx.cognitiveservices.azure.com/
$rg         = $out.resourceGroup
$subId      = $out.subscriptionId
$hostname   = ([Uri]$aiEndpoint).Host

Write-Host "==> Target account: $aiName  ($hostname)" -ForegroundColor Cyan

# --- Patch swagger host -----------------------------------------------------
$repoRoot   = Split-Path -Parent $PSScriptRoot
$swaggerSrc = Join-Path $repoRoot 'powerplatform\contentunderstanding-connector.swagger.json'
$swaggerOut = Join-Path $repoRoot 'powerplatform\contentunderstanding-connector.generated.json'

(Get-Content $swaggerSrc -Raw).Replace('REPLACE_WITH_AI_HOSTNAME', $hostname) |
  Set-Content $swaggerOut -Encoding UTF8
Write-Host "==> Generated $swaggerOut" -ForegroundColor Green

# --- Create connector via pac ----------------------------------------------
if (-not $SkipConnectorCreate) {
  Write-Host "==> Creating custom connector via pac CLI (display name comes from swagger info.title)" -ForegroundColor Cyan
  pac connector create `
      --api-definition-file $swaggerOut `
      --api-properties-file (Join-Path $repoRoot 'powerplatform\apiProperties.json')
  if ($LASTEXITCODE -ne 0) { throw "pac connector create failed (exit $LASTEXITCODE)." }
}

# --- Unit test: call the data plane directly --------------------------------
Write-Host ""
Write-Host "==> Unit test: GET https://$hostname/contentunderstanding/analyzers?api-version=2024-12-01-preview" -ForegroundColor Cyan

$key = az cognitiveservices account keys list -g $rg -n $aiName --subscription $subId --query key1 -o tsv
if (-not $key) { throw "Failed to fetch key for $aiName" }

$uri = "https://$hostname/contentunderstanding/analyzers?api-version=2024-12-01-preview"
try {
  $resp = Invoke-WebRequest -Uri $uri -Headers @{ 'Ocp-Apim-Subscription-Key' = $key } -UseBasicParsing -TimeoutSec 30
  Write-Host "PASS  HTTP $($resp.StatusCode) - data plane reachable." -ForegroundColor Green
  Write-Host ($resp.Content.Substring(0, [Math]::Min(400, $resp.Content.Length)))
  $exitOk = $true
} catch {
  $code = $_.Exception.Response.StatusCode.value__
  if ($InsideVnetTest) {
    Write-Host "FAIL  HTTP $code from inside VNet - investigate DNS resolution / NSG / PE state." -ForegroundColor Red
    throw
  } else {
    Write-Host "EXPECTED FAIL  HTTP $code from public internet - confirms private-endpoint lockdown." -ForegroundColor Yellow
    Write-Host "Re-run with -InsideVnetTest from a VM in vnet-prvendcu / snet-pe to validate end-to-end." -ForegroundColor Yellow
    $exitOk = $true
  }
}

if (-not $exitOk) { exit 1 }
