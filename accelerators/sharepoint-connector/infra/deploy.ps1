<#
.SYNOPSIS
    Deploy the SharePoint Connector end-to-end.

.DESCRIPTION
    Runs the Bicep template. By default the template provisions every Azure
    resource and pulls the CI-built function-app package from GitHub
    Releases — so when the deployment finishes, the code is already running
    and Copilot Studio can wire AI Search in directly as a Knowledge Source
    (no Entra app registration, no Power Platform connection).

    Pass -EnableSecurityTrimming to additionally register the /api/search
    Entra app for the per-user trimming flow described in the README's
    "Extending with Per-User Security Trimming" section.

.PARAMETER ResourceGroup
    Target resource group (created if it doesn't already exist).

.PARAMETER Location
    Azure region (default: swedencentral). Pick one that supports Azure AI
    Vision multimodal 4.0.

.PARAMETER EnableSecurityTrimming
    Switch — when present, sets the Bicep `enableSecurityTrimming` parameter
    to $true. The template then declares the Entra app registration that
    Copilot Studio's OnKnowledgeRequested topic authenticates against.
    Requires the deployer to hold `Application Administrator` (or for
    -ApiAudience to be supplied as the escape hatch). Leave unset for the
    default direct-AI-Search-as-knowledge flow.

.PARAMETER ApiAudience
    Optional escape hatch for tenants where the deployer does NOT hold the
    `Application Administrator` Entra role. Only relevant alongside
    -EnableSecurityTrimming. Supply the clientId (GUID) of a pre-created
    Entra app registration; the template will then skip its own
    app-registration step and wire the Function App to this clientId
    instead. Use infra/create-api-app-registration.ps1 (run by an admin) to
    create one.

.EXAMPLE
    # Default: Copilot Studio queries AI Search directly as a Knowledge Source.
    .\deploy.ps1 -ResourceGroup sharepoint-rg

.EXAMPLE
    # Opt-in: per-user security trimming (deployer is Application Administrator).
    .\deploy.ps1 -ResourceGroup sharepoint-rg -EnableSecurityTrimming

.EXAMPLE
    # Opt-in: per-user security trimming, deployer lacks Graph privileges,
    # admin pre-created the app registration:
    .\deploy.ps1 -ResourceGroup sharepoint-rg `
        -EnableSecurityTrimming `
        -ApiAudience 00000000-1111-2222-3333-444444444444
#>

param(
    [Parameter(Mandatory)]
    [string]$ResourceGroup,

    [string]$Location = "swedencentral",

    [switch]$EnableSecurityTrimming,

    [string]$ApiAudience = ""
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

if ($ApiAudience -and -not $EnableSecurityTrimming) {
    Write-Warning "-ApiAudience is set but -EnableSecurityTrimming is not. apiAudience is only consumed when security trimming is enabled — ignoring."
    $ApiAudience = ""
}

Write-Host "  Resource group:        $ResourceGroup" -ForegroundColor Gray
Write-Host "  Location:              $Location"      -ForegroundColor Gray
Write-Host "  Security trimming:     $($EnableSecurityTrimming.IsPresent)" -ForegroundColor Gray

# Ensure the RG exists
az group create --name $ResourceGroup --location $Location --output none

# ------------------------------------------------------------------
# Deploy infrastructure
# ------------------------------------------------------------------
if ($EnableSecurityTrimming) {
    Write-Host "`nDeploying infrastructure + Entra app registration + seeding function-app package..." -ForegroundColor Yellow
}
else {
    Write-Host "`nDeploying infrastructure (default flow — direct AI Search as Knowledge Source) + seeding function-app package..." -ForegroundColor Yellow
}

$bicepFile = Join-Path $scriptDir "main.bicep"

$deployArgs = @(
    "deployment", "group", "create",
    "--resource-group", $ResourceGroup,
    "--template-file", $bicepFile,
    "--parameters", $paramFile,
    "--parameters", "location=$Location"
)
if ($EnableSecurityTrimming) {
    $deployArgs += @("--parameters", "enableSecurityTrimming=true")
}
if ($ApiAudience) {
    Write-Host "  apiAudience:           $ApiAudience (escape-hatch — template will skip app-registration creation)" -ForegroundColor Gray
    $deployArgs += @("--parameters", "apiAudience=$ApiAudience")
}
$deployArgs += @("--output", "table")

az @deployArgs

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
if ($EnableSecurityTrimming) {
    Write-Host @"

  Deployment complete (security trimming ENABLED). Azure resources +
  Entra app registration + function code are all in place.

  Remaining manual steps — see README "Extending with Per-User Security
  Trimming" for full detail:
  ════════════════════════════════════════════════════════════════
  1. Grant Sites.Selected on your target SharePoint site:
       .\infra\grant-site-permission.ps1 ``
           -SiteUrl "<your-site-url>" ``
           -FunctionAppName "$functionAppName"

  2. Grant GroupMember.Read.All to the Function's MI:
       .\infra\grant-graph-permission.ps1 -FunctionAppName "$functionAppName"

  3. Pre-authorize Power Platform on the API app registration
     (Entra admin centre → App registrations → [SharePoint Connector API]
     → Expose an API → Add a client application).

  4. Create the "HTTP with Microsoft Entra ID (preauthorized)" connection
     in Power Platform; capture its reference name.

  5. In your generative-orchestration agent: REMOVE the AI Search
     Knowledge Source (if added) and import
     copilot-studio-topics/OnKnowledgeRequested.yaml. Replace the
     placeholders (Function App hostname + OAuth2 connection reference)
     and publish.
  ════════════════════════════════════════════════════════════════
"@ -ForegroundColor White
}
else {
    Write-Host @"

  Deployment complete (default flow — Copilot Studio queries AI Search
  directly). No Entra app registration, no Power Platform connection.

  Remaining manual steps:
  ════════════════════════════════════════════════════════════════
  1. Grant Sites.Selected on your target SharePoint site:
       .\infra\grant-site-permission.ps1 ``
           -SiteUrl "<your-site-url>" ``
           -FunctionAppName "$functionAppName"

  2. In Copilot Studio, add Azure AI Search as a Knowledge Source on
     your agent:
       - Search service: $searchEndpoint
       - Index name:     sharepoint-index
       - Title field:    title  |  URL field: url  |  Content field: chunk
       - Vector field:   content_embedding
     Then publish the agent.

  Want per-user security trimming? See the README section
  "Extending with Per-User Security Trimming" — re-run this script
  with -EnableSecurityTrimming.
  ════════════════════════════════════════════════════════════════
"@ -ForegroundColor White
}

Write-Host @"

  To redeploy new code after a main-branch merge:
    1. Wait for the 'Release SharePoint Connector' GitHub Action to
       republish `sharepoint-connector-latest`.
    2. Restart the Function App:
         az functionapp restart --name $functionAppName --resource-group $ResourceGroup
"@ -ForegroundColor White
