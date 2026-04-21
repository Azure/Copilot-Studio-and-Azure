<#
.SYNOPSIS
    Deploy the Voice Channel Accelerator infrastructure.

.DESCRIPTION
    Provisions:
      - Microsoft Foundry (AIServices) resource with custom subdomain
      - Log Analytics + Application Insights

    Post-deploy steps (separate scripts, run in this order):
      1. ../copilot-studio-agent/create-agent.ps1 — creates the MCS "Microsoft
         Learn Assistant" agent, enables Direct Line, prints the secret
      2. ../foundry-agent/create-foundry-agent.ps1 — creates the Foundry
         "IT Assistant" agent and attaches the Direct Line OpenAPI tool
      3. ../foundry-agent/publish-to-teams.ps1 — publishes the agent to
         Microsoft 365 Copilot and Teams via Azure Bot Service

.PARAMETER ResourceGroup
    Target resource group. Created if it does not exist.

.PARAMETER Location
    Azure region (default: swedencentral).

.PARAMETER BaseName
    Base name for all resources (default: voicech-01).

.EXAMPLE
    .\deploy.ps1 -ResourceGroup voice-pushtotalk-rg
#>

param(
    [Parameter(Mandatory)]
    [string]$ResourceGroup,

    [string]$Location = 'swedencentral',
    [string]$BaseName = 'voicech-01'
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$bicepFile = Join-Path $scriptDir 'main.bicep'
$paramFile = Join-Path $scriptDir 'main.bicepparam'

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
# Step 2 — Register required resource providers (publish-copilot needs these)
# ---------------------------------------------------------------------------
Write-Host "`n[2/3] Registering resource providers..." -ForegroundColor Yellow
az provider register --namespace Microsoft.BotService --wait --output none
az provider register --namespace Microsoft.CognitiveServices --wait --output none

# ---------------------------------------------------------------------------
# Step 3 — Bicep deployment
# ---------------------------------------------------------------------------
Write-Host "`n[3/3] Deploying Bicep template (2-3 minutes)..." -ForegroundColor Yellow

az deployment group create `
    --resource-group $ResourceGroup `
    --name 'voice-pushtotalk' `
    --template-file $bicepFile `
    --parameters $paramFile `
    --parameters baseName=$BaseName location=$Location `
    --output none

if ($LASTEXITCODE -ne 0) {
    Write-Error "Bicep deployment failed. See error above."
    exit 1
}

$outputs = az deployment group show `
    --resource-group $ResourceGroup `
    --name 'voice-pushtotalk' `
    --query 'properties.outputs' `
    --output json | ConvertFrom-Json

$foundryName     = $outputs.foundryName.value
$foundryEndpoint = $outputs.foundryEndpoint.value

Write-Host @"

=== Deployment complete ==========================================

  Foundry resource     : $foundryName
  Foundry endpoint     : $foundryEndpoint

=== Next steps ===================================================

  1. Create the Copilot Studio agent and capture the Direct Line secret:

     ../copilot-studio-agent/create-agent.ps1 ``
         -EnvironmentUrl 'https://<your-env>.crm.dynamics.com' ``
         -AgentName 'Microsoft Learn Assistant'

  2. Create the Foundry "IT Assistant" agent with the Direct Line tool:

     ../foundry-agent/create-foundry-agent.ps1 ``
         -FoundryEndpoint '$foundryEndpoint' ``
         -DirectLineSecret '<secret-from-step-1>'

  3. Publish the Foundry agent to Teams and M365 Copilot:

     ../foundry-agent/publish-to-teams.ps1 ``
         -ResourceGroup $ResourceGroup ``
         -FoundryName $foundryName

==================================================================
"@ -ForegroundColor Green
