<#
.SYNOPSIS
    Deploy the Voice Channel Accelerator infrastructure.

.DESCRIPTION
    Provisions:
      - Microsoft Foundry resource (Voice Live enabled)
      - Azure App Service (Linux / Python 3.11) for the bridge
      - Log Analytics + Application Insights
      - RBAC (Cognitive Services User + Azure AI User) for the App Service MI

    After this script completes you still need to:
      1. Run copilot-studio-agent/create-agent.ps1 (creates the MCS agent and prints Direct Line secret)
      2. az webapp config appsettings set ... DIRECTLINE_SECRET=<secret>
      3. cd ../bridge && az webapp up ... (deploys the bridge code)

.PARAMETER ResourceGroup
    Target resource group. Must already exist.

.PARAMETER Location
    Azure region (default: swedencentral).

.PARAMETER BaseName
    Base name for all resources (default: voicech-01). Must match main.bicepparam.

.PARAMETER GrantRbacOnly
    Skip Bicep deployment and only (re)run the role-assignment section.
    Useful when RBAC propagation lags on first deploy.

.EXAMPLE
    .\deploy.ps1 -ResourceGroup voice-channel-rg

.EXAMPLE
    .\deploy.ps1 -ResourceGroup voice-channel-rg -BaseName myorg-voice -Location eastus2
#>

param(
    [Parameter(Mandatory)]
    [string]$ResourceGroup,

    [string]$Location = 'swedencentral',
    [string]$BaseName = 'voicech-01',

    [switch]$GrantRbacOnly
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

$scriptDir  = Split-Path -Parent $MyInvocation.MyCommand.Path
$bicepFile  = Join-Path $scriptDir 'main.bicep'
$paramFile  = Join-Path $scriptDir 'main.bicepparam'

Write-Host "`n=== Voice Channel Accelerator — Infrastructure ===" -ForegroundColor Cyan
Write-Host "  Resource group : $ResourceGroup"
Write-Host "  Location       : $Location"
Write-Host "  Base name      : $BaseName"
Write-Host ""

# ---------------------------------------------------------------------------
# Step 1 — Ensure resource group exists
# ---------------------------------------------------------------------------
$existing = az group exists --name $ResourceGroup
if ($existing -eq 'false') {
    Write-Host "[1/3] Creating resource group..." -ForegroundColor Yellow
    az group create --name $ResourceGroup --location $Location --output none
}
else {
    Write-Host "[1/3] Resource group exists — skipping create." -ForegroundColor Yellow
}

# ---------------------------------------------------------------------------
# Step 2 — Bicep deployment
# ---------------------------------------------------------------------------
if (-not $GrantRbacOnly) {
    Write-Host "`n[2/3] Deploying Bicep template (this takes 3-5 minutes)..." -ForegroundColor Yellow

    az deployment group create `
        --resource-group $ResourceGroup `
        --name 'voice-channel' `
        --template-file $bicepFile `
        --parameters $paramFile `
        --parameters baseName=$BaseName location=$Location `
        --output none

    if ($LASTEXITCODE -ne 0) {
        Write-Error "Bicep deployment failed. See error above."
        exit 1
    }
}
else {
    Write-Host "`n[2/3] Skipping Bicep deployment (-GrantRbacOnly)." -ForegroundColor Yellow
}

# ---------------------------------------------------------------------------
# Step 3 — Collect outputs and print next steps
# ---------------------------------------------------------------------------
Write-Host "`n[3/3] Collecting deployment outputs..." -ForegroundColor Yellow

$outputs = az deployment group show `
    --resource-group $ResourceGroup `
    --name 'voice-channel' `
    --query 'properties.outputs' `
    --output json | ConvertFrom-Json

$foundryName       = $outputs.foundryName.value
$foundryEndpoint   = $outputs.foundryEndpoint.value
$wsUrl             = $outputs.voiceLiveWebSocketUrl.value
$bridgeApp         = $outputs.bridgeAppName.value
$bridgeHost        = $outputs.bridgeAppHostName.value
$bridgePrincipalId = $outputs.bridgePrincipalId.value

Write-Host @"

=== Deployment complete ==========================================

  Foundry resource       : $foundryName
  Foundry endpoint       : $foundryEndpoint
  Voice Live WS URL      : $wsUrl
  Bridge App Service     : $bridgeApp
  Bridge URL             : https://$bridgeHost
  Bridge MI principalId  : $bridgePrincipalId

=== Next steps ===================================================

  1. Create the Copilot Studio agent and capture the Direct Line secret:

     ../copilot-studio-agent/create-agent.ps1 ``
         -EnvironmentUrl 'https://<your-env>.crm.dynamics.com' ``
         -AgentName 'Microsoft Learn Assistant'

  2. Wire the Direct Line secret into the bridge:

     az webapp config appsettings set ``
         --resource-group $ResourceGroup ``
         --name $bridgeApp ``
         --settings DIRECTLINE_SECRET='<secret-from-step-1>'

  3. Deploy the bridge code:

     cd ../bridge
     az webapp up --resource-group $ResourceGroup --name $bridgeApp --runtime 'PYTHON:3.11'

  4. Open https://$bridgeHost to test, or side-load the Teams app
     from bridge/teams/manifest.json.

==================================================================
"@ -ForegroundColor Green
