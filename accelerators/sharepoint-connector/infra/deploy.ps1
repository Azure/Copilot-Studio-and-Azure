<#
.SYNOPSIS
    Deploy the SharePoint Connector as an Azure Function App.

.DESCRIPTION
    1. Creates infrastructure via Bicep (Function App, Storage + Queue/Table/State,
       App Insights, optional Key Vault, optional Document Intelligence, RBAC)
    2. Deploys the function code via Azure Functions Core Tools

.PARAMETER ResourceGroup
    Target resource group name.

.PARAMETER Location
    Azure region (default: swedencentral).

.PARAMETER BaseName
    Base name for all resources (default: sp-indexer).

.PARAMETER ClientSecret
    Optional Graph API client secret (for the Sites.Read.All / Files.Read.All app
    registration fallback). When supplied, the deployment provisions a Key Vault,
    stores the secret, and wires it into the Function App as a Key Vault reference.
    Prefer the pure-managed-identity path (leave this empty) when possible.

.PARAMETER ProvisionDocIntel
    If $true, provisions a new Document Intelligence account for image OCR.

.EXAMPLE
    # Pure managed-identity deployment
    .\deploy.ps1 -ResourceGroup sharepoint-testing

.EXAMPLE
    # With Key Vault-backed client secret
    .\deploy.ps1 -ResourceGroup sharepoint-testing -ClientSecret (Read-Host -AsSecureString)

.EXAMPLE
    # With Document Intelligence for image OCR
    .\deploy.ps1 -ResourceGroup sharepoint-testing -ProvisionDocIntel
#>

param(
    [Parameter(Mandatory)]
    [string]$ResourceGroup,

    [string]$Location = "swedencentral",
    [string]$BaseName = "sp-indexer",

    [securestring]$ClientSecret = $null,
    [switch]$ProvisionDocIntel
)

$ErrorActionPreference = "Stop"
Set-StrictMode -Version Latest

$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$projectRoot = Split-Path -Parent $scriptDir

Write-Host "`n=== SharePoint Connector — Deployment ===" -ForegroundColor Cyan

# ------------------------------------------------------------------
# Pre-flight: make sure a bicepparam file exists
# ------------------------------------------------------------------
$paramFile = Join-Path $scriptDir "main.bicepparam"
$sampleFile = Join-Path $scriptDir "main.bicepparam.sample"
if (-not (Test-Path $paramFile)) {
    if (Test-Path $sampleFile) {
        Write-Warning "main.bicepparam missing — copying from main.bicepparam.sample. Edit it with your values, then re-run."
        Copy-Item $sampleFile $paramFile
    }
    Write-Error "Please populate $paramFile with your tenant/subscription/SharePoint values before deploying."
    exit 1
}

# ------------------------------------------------------------------
# Step 1: Deploy infrastructure via Bicep
# ------------------------------------------------------------------
Write-Host "`n[1/4] Deploying infrastructure (Bicep)..." -ForegroundColor Yellow

$bicepFile = Join-Path $scriptDir "main.bicep"

# Assemble extra parameters (only override what was passed on the command line)
$extraParams = @(
    "baseName=$BaseName",
    "location=$Location"
)

if ($ClientSecret) {
    $plain = [System.Runtime.InteropServices.Marshal]::PtrToStringAuto(
        [System.Runtime.InteropServices.Marshal]::SecureStringToBSTR($ClientSecret)
    )
    $extraParams += "useClientSecret=true"
    $extraParams += "clientSecretValue=$plain"
}

if ($ProvisionDocIntel) {
    $extraParams += "provisionDocIntel=true"
}

az deployment group create `
    --resource-group $ResourceGroup `
    --template-file $bicepFile `
    --parameters $paramFile `
    --parameters $extraParams `
    --output table

if ($LASTEXITCODE -ne 0) {
    Write-Error "Bicep deployment failed"
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
$keyVaultName = $outputs.keyVaultName.value
$docIntelEndpoint = $outputs.docIntelEndpoint.value

Write-Host "  Function App:     $functionAppName" -ForegroundColor Green
Write-Host "  Managed Identity: $principalId" -ForegroundColor Green
if ($keyVaultName) {
    Write-Host "  Key Vault:        $keyVaultName" -ForegroundColor Green
}
if ($docIntelEndpoint) {
    Write-Host "  DocIntel:         $docIntelEndpoint" -ForegroundColor Green
}

# ------------------------------------------------------------------
# Step 2: Ensure requirements.txt is up to date
# ------------------------------------------------------------------
Write-Host "`n[2/4] Updating requirements.txt..." -ForegroundColor Yellow
Push-Location $projectRoot
uv export --no-hashes --extra func --no-dev 2>$null | Set-Content -Path requirements.txt -Encoding UTF8
Pop-Location
Write-Host "  requirements.txt updated" -ForegroundColor Green

# ------------------------------------------------------------------
# Step 3: Deploy function code
# ------------------------------------------------------------------
Write-Host "`n[3/4] Deploying function code..." -ForegroundColor Yellow
Push-Location $projectRoot

func azure functionapp publish $functionAppName --python

if ($LASTEXITCODE -ne 0) {
    Write-Error "Function deployment failed"
    Pop-Location
    exit 1
}
Pop-Location
Write-Host "  Code deployed successfully" -ForegroundColor Green

# ------------------------------------------------------------------
# Step 4: Post-deployment info
# ------------------------------------------------------------------
Write-Host "`n[4/4] Post-deployment checklist" -ForegroundColor Yellow
Write-Host @"

  Deployment complete!

  Function App:       $functionAppName
  Managed Identity:   $principalId

  IMPORTANT — Manual steps required:
  ═══════════════════════════════════════════════════════════════
  1. Graph API permissions for the managed identity:
     The Function App's managed identity ($principalId) needs
     Graph API access to your SharePoint site. Prefer the
     least-privilege Sites.Selected model over tenant-wide
     Sites.Read.All; see README section 'Authentication Deep Dive'.

  2. Verify the timer is running:
     az functionapp show --name $functionAppName --resource-group $ResourceGroup --query "state"

  3. Check logs:
     func azure functionapp logstream $functionAppName

  4. Trigger a one-off test:
     \$masterKey = (az functionapp keys list --name $functionAppName --resource-group $ResourceGroup --query "masterKey" -o tsv)
     Invoke-WebRequest -Uri "https://$functionAppName.azurewebsites.net/admin/functions/sp_indexer_timer" ``
         -Method POST -Headers @{"x-functions-key"=\$masterKey; "Content-Type"="application/json"} -Body '{}'
  ═══════════════════════════════════════════════════════════════
"@ -ForegroundColor White
