<#
.SYNOPSIS
    Deploy the SharePoint Connector end-to-end.

.DESCRIPTION
    Runs the Bicep template. The template itself provisions every Azure
    resource, declares the Entra app registration that /api/search needs
    (via the Microsoft Graph Bicep extension), and pulls the CI-built
    function-app package from GitHub Releases — so when the deployment
    finishes, the code is already running.

    No `func publish`, no separate app-registration step, no parameters
    beyond the two genuinely user-specific values (baseName and
    sharePointSiteUrl). Tenant is inferred from the az context.

.PARAMETER ResourceGroup
    Target resource group (created if it doesn't already exist).

.PARAMETER Location
    Azure region (default: swedencentral). Pick one that supports Azure AI
    Vision multimodal 4.0.

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
    Write-Error "Populate $paramFile (baseName + sharePointSiteUrl) before deploying."
    exit 1
}

Write-Host "  Resource group:  $ResourceGroup" -ForegroundColor Gray
Write-Host "  Location:        $Location"    -ForegroundColor Gray

# Ensure the RG exists
az group create --name $ResourceGroup --location $Location --output none

# ------------------------------------------------------------------
# Deploy infrastructure (includes Entra app registration + code seeding)
# ------------------------------------------------------------------
Write-Host "`nDeploying infrastructure + Entra app registration + seeding function-app package..." -ForegroundColor Yellow

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

$functionAppName  = $outputs.functionAppName.value
$principalId      = $outputs.functionAppPrincipalId.value
$searchEndpoint   = $outputs.searchEndpoint.value
$foundryEndpoint  = $outputs.foundryEndpoint.value
$docIntelEndpoint = $outputs.docIntelEndpoint.value
$keyVaultName     = $outputs.keyVaultName.value
$apiAudience      = $outputs.apiAudience.value
$apiAppName       = $outputs.apiAppDisplayName.value

Write-Host "`n  Function App:     $functionAppName" -ForegroundColor Green
Write-Host "  Managed Identity: $principalId"   -ForegroundColor Green
Write-Host "  Search:           $searchEndpoint" -ForegroundColor Green
Write-Host "  Foundry:          $foundryEndpoint" -ForegroundColor Green
Write-Host "  DocIntel:         $docIntelEndpoint" -ForegroundColor Green
Write-Host "  Key Vault:        $keyVaultName"   -ForegroundColor Green
Write-Host "  API app reg:      $apiAppName"     -ForegroundColor Green
Write-Host "  apiAudience:      $apiAudience"    -ForegroundColor Green

# ------------------------------------------------------------------
# Post-deployment checklist
# ------------------------------------------------------------------
Write-Host @"

  Deployment complete. Azure resources + app registration + function code
  are all in place.

  Remaining manual steps — these require Entra / SharePoint / Power Platform
  roles that RG Owners typically don't hold, so they stay out-of-template on
  purpose:
  ════════════════════════════════════════════════════════════════
  1. Grant admin consent on the /api/search app registration's Graph
     permission (GroupMember.Read.All). Requires Global Administrator or
     Cloud Application Administrator:

       az ad app permission admin-consent --id $apiAudience

  2. Grant Sites.Selected on your target SharePoint site. Requires
     SharePoint Administrator or Global Administrator:

       .\infra\grant-site-permission.ps1 ``
           -SiteUrl "<your-site-url>" ``
           -FunctionAppName "$functionAppName"

  3. Import copilot-studio-topics/OnKnowledgeRequested.yaml into your
     generative-orchestration Copilot Studio agent, fill the placeholders
     (Function App hostname + OAuth2 connection reference pointing at
     clientId $apiAudience), and publish.

  4. Verify:
       az functionapp show --name $functionAppName --resource-group $ResourceGroup --query "state"
       func azure functionapp logstream $functionAppName
  ════════════════════════════════════════════════════════════════

  To redeploy new code after a main-branch merge:
    1. Wait for the 'Release SharePoint Connector' GitHub Action to
       republish `sharepoint-connector-latest`.
    2. Restart the Function App:
         az functionapp restart --name $functionAppName --resource-group $ResourceGroup
"@ -ForegroundColor White
