<#
.SYNOPSIS
    Deploy the SharePoint Connector end-to-end.

.DESCRIPTION
    Runs the Bicep template against the target resource group. The template
    provisions every Azure resource, pulls the latest CI-built function-app
    package from GitHub Releases via an ARM deploymentScript, and seeds the
    Function App's storage container so the code is ready on first startup.

    No separate `func publish` step is required — just run this script.

    Required values live in `infra/main.bicepparam` (baseName, tenantId,
    sharePointSiteUrl, apiAudience). Everything else is defaulted inside
    `main.bicep` and can be tuned post-deployment via Function App settings.

.PARAMETER ResourceGroup
    Target resource group. Will be created if it doesn't already exist.

.PARAMETER Location
    Azure region (default: swedencentral).

.EXAMPLE
    .\deploy.ps1 -ResourceGroup sharepoint-rg
#>

param(
    [Parameter(Mandatory)]
    [string]$ResourceGroup,

    [string]$Location = "swedencentral"
)

$ErrorActionPreference = "Stop"
Set-StrictMode -Version Latest

$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path

Write-Host "`n=== SharePoint Connector — Deployment ===" -ForegroundColor Cyan

# ------------------------------------------------------------------
# Pre-flight: ensure bicepparam exists
# ------------------------------------------------------------------
$paramFile = Join-Path $scriptDir "main.bicepparam"
$sampleFile = Join-Path $scriptDir "main.bicepparam.sample"
if (-not (Test-Path $paramFile)) {
    if (Test-Path $sampleFile) {
        Write-Warning "main.bicepparam missing — copying from main.bicepparam.sample. Edit it with your values, then re-run."
        Copy-Item $sampleFile $paramFile
    }
    Write-Error "Populate $paramFile with tenantId, sharePointSiteUrl, apiAudience before deploying."
    exit 1
}

# Ensure the RG exists
az group create --name $ResourceGroup --location $Location --output none

# ------------------------------------------------------------------
# Deploy infrastructure + seed function code
# ------------------------------------------------------------------
Write-Host "`nDeploying infrastructure + seeding function-app package..." -ForegroundColor Yellow

$bicepFile = Join-Path $scriptDir "main.bicep"

az deployment group create `
    --resource-group $ResourceGroup `
    --template-file $bicepFile `
    --parameters $paramFile `
    --parameters location=$Location `
    --output table

if ($LASTEXITCODE -ne 0) {
    Write-Error "Deployment failed"
    exit 1
}

# Get outputs
$outputs = az deployment group show `
    --resource-group $ResourceGroup `
    --name "main" `
    --query "properties.outputs" `
    --output json | ConvertFrom-Json

$functionAppName = $outputs.functionAppName.value
$principalId = $outputs.functionAppPrincipalId.value
$searchEndpoint = $outputs.searchEndpoint.value
$foundryEndpoint = $outputs.foundryEndpoint.value
$docIntelEndpoint = $outputs.docIntelEndpoint.value
$keyVaultName = $outputs.keyVaultName.value

Write-Host "`n  Function App:     $functionAppName" -ForegroundColor Green
Write-Host "  Managed Identity: $principalId"   -ForegroundColor Green
Write-Host "  Search:           $searchEndpoint" -ForegroundColor Green
Write-Host "  Foundry:          $foundryEndpoint" -ForegroundColor Green
Write-Host "  DocIntel:         $docIntelEndpoint" -ForegroundColor Green
Write-Host "  Key Vault:        $keyVaultName"   -ForegroundColor Green

# ------------------------------------------------------------------
# Post-deployment checklist
# ------------------------------------------------------------------
Write-Host @"

  Deployment complete. Function code is already on the Function App.

  Remaining manual steps (Graph + Copilot Studio — these require roles that
  Azure RG Owners typically don't hold, so they stay out-of-template on
  purpose):
  ════════════════════════════════════════════════════════════════
  1. Grant Sites.Selected on your target SharePoint site:

       .\infra\grant-site-permission.ps1 ``
           -SiteUrl "<your-site-url>" ``
           -FunctionAppName "$functionAppName"

     (Requires SharePoint Administrator or Global Administrator.)

  2. Grant ``GroupMember.Read.All`` (Application) Graph permission to the
     managed identity ($principalId). Required so /api/search can resolve
     transitive group memberships.

     (Requires Global Administrator or Cloud Application Administrator.)

  3. Import copilot-studio-topics/OnKnowledgeRequested.yaml into your
     generative-orchestration Copilot Studio agent, fill the placeholders
     (Function App hostname + OAuth2 connection reference), and publish.

  4. Verify:
       az functionapp show --name $functionAppName --resource-group $ResourceGroup --query "state"
       func azure functionapp logstream $functionAppName
  ════════════════════════════════════════════════════════════════

  Tip — to redeploy new function code after a main-branch merge:
    1. Wait for the 'Release SharePoint Connector' GitHub Action to
       publish a new ``sharepoint-connector-latest`` release.
    2. Restart the Function App (or run: az functionapp restart --name
       $functionAppName --resource-group $ResourceGroup) — it re-pulls
       the package from blob on next cold start.
"@ -ForegroundColor White
