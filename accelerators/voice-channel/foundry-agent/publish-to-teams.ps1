<#
.SYNOPSIS
    Publish the Foundry IT Assistant agent to Microsoft 365 Copilot + Teams.

.DESCRIPTION
    Wraps the publish-copilot flow:
    https://learn.microsoft.com/azure/foundry/agents/how-to/publish-copilot

    1. Registers Microsoft.BotService in the subscription.
    2. Calls the Foundry publish REST endpoint — creates an Entra app
       registration + Azure Bot Service resource and packages a Teams app zip.
    3. Polls until status transitions to Ready.
    4. Downloads the .zip to ./dist/it-assistant-teams-package.zip.
    5. Prints the exact portal click-path as a fallback if any step is not
       yet GA on your Foundry ring.

    Pre-reqs:
      - 'Azure AI Project Manager' on the Foundry project
      - Rights to create Azure Bot Service resources in the subscription

.PARAMETER FoundryEndpoint
    Same endpoint passed to create-foundry-agent.ps1.

.PARAMETER ProjectId
    Foundry project ID.

.PARAMETER AssistantId
    The assistant id printed by create-foundry-agent.ps1.

.PARAMETER DisplayName
    Name shown in the agent store. Default: IT Assistant.

.PARAMETER Publisher
    Publisher name. Default: signed-in Azure CLI account.

.PARAMETER WebsiteUrl / PrivacyUrl / TermsUrl
    HTTPS URLs in the Teams manifest. Placeholders OK for dev.

.PARAMETER OutputDir
    Where the zip is saved. Default: ./dist.

.EXAMPLE
    ./publish-to-teams.ps1 `
        -FoundryEndpoint $env:FOUNDRY_ENDPOINT `
        -ProjectId '<proj>' `
        -AssistantId '<asst>'
#>

param(
    [Parameter(Mandatory)] [string]$FoundryEndpoint,
    [Parameter(Mandatory)] [string]$ProjectId,
    [Parameter(Mandatory)] [string]$AssistantId,

    [string]$DisplayName = 'IT Assistant',
    [string]$Publisher   = '',
    [string]$WebsiteUrl  = 'https://example.com',
    [string]$PrivacyUrl  = 'https://example.com/privacy',
    [string]$TermsUrl    = 'https://example.com/terms',
    [string]$OutputDir   = './dist'
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

$apiVersion = '2025-10-01'

function Write-PortalFallback {
    param([string]$Endpoint, [string]$AssistantId)
    Write-Host @"

=== Portal fallback ===============================================

The publish REST endpoint isn't available on your Foundry ring yet. Follow
this click-path in the portal (3-5 min):

  1. https://ai.azure.com -> select your project
  2. Agents -> open the 'IT Assistant' agent (id: $AssistantId)
  3. Publish -> Publish to Teams and Microsoft 365 Copilot
  4. Azure Bot Service -> Create new
  5. Fill metadata (name, publisher, URLs)
  6. Prepare agent -> wait 1-2 min
  7. Download the package -> save to dist/it-assistant-teams-package.zip
  8. Teams -> Apps -> Upload custom app

===================================================================
"@ -ForegroundColor Yellow
}

Write-Host "`n=== Foundry IT Assistant — Publish to Teams + M365 ===" -ForegroundColor Cyan

# 1. Provider -----------------------------------------------------------------
Write-Host "`n[1/5] Registering Microsoft.BotService provider..." -ForegroundColor Yellow
az provider register --namespace Microsoft.BotService --wait --output none

# 2. Token --------------------------------------------------------------------
Write-Host "`n[2/5] Acquiring Foundry token..." -ForegroundColor Yellow
$token = az account get-access-token --scope 'https://ai.azure.com/.default' --query accessToken -o tsv
if (-not $token) { Write-Error "Run 'az login' first."; exit 1 }
$headers = @{ Authorization = "Bearer $token"; 'Content-Type' = 'application/json' }
if (-not $Publisher) { $Publisher = az account show --query 'user.name' -o tsv }
New-Item -ItemType Directory -Force -Path $OutputDir | Out-Null

# 3. Start publish ------------------------------------------------------------
Write-Host "`n[3/5] Submitting publish request..." -ForegroundColor Yellow
$publishUri = "$FoundryEndpoint/api/projects/$ProjectId/assistants/$AssistantId/publish?api-version=$apiVersion"

$publishBody = @{
    target = 'microsoft365'
    metadata = @{
        name             = $DisplayName
        shortDescription = 'Ask Microsoft Learn anything — voice or text.'
        fullDescription  = 'IT Assistant answers Microsoft product, Azure, M365, Power Platform, and developer questions using Microsoft Learn.'
        publisher        = $Publisher
        websiteUrl       = $WebsiteUrl
        privacyUrl       = $PrivacyUrl
        termsUrl         = $TermsUrl
    }
    botService = @{ mode = 'createNew' }
    scope      = 'individual'
} | ConvertTo-Json -Depth 5

try {
    $publish = Invoke-RestMethod -Method Post -Uri $publishUri -Headers $headers -Body $publishBody
} catch {
    Write-Warning "Publish REST endpoint returned an error: $($_.Exception.Message)"
    Write-PortalFallback -Endpoint $FoundryEndpoint -AssistantId $AssistantId
    exit 1
}
$publishId = $publish.id

# 4. Poll ---------------------------------------------------------------------
Write-Host "`n[4/5] Waiting for package ready (1-3 min)..." -ForegroundColor Yellow
$deadline = (Get-Date).AddMinutes(10)
do {
    Start-Sleep -Seconds 10
    $status = Invoke-RestMethod -Method Get `
        -Uri "$FoundryEndpoint/api/projects/$ProjectId/assistants/$AssistantId/publish/${publishId}?api-version=$apiVersion" `
        -Headers $headers
    Write-Host "  status: $($status.status)"
} while ($status.status -notin @('Ready', 'Failed') -and (Get-Date) -lt $deadline)

if ($status.status -ne 'Ready') {
    Write-Error "Publish did not reach Ready. Last status: $($status.status). $($status.error.message)"
    exit 1
}

# 5. Download -----------------------------------------------------------------
Write-Host "`n[5/5] Downloading Teams + M365 package..." -ForegroundColor Yellow
$zipUri = $status.packageUrl
if (-not $zipUri) {
    $zipUri = "$FoundryEndpoint/api/projects/$ProjectId/assistants/$AssistantId/publish/$publishId/package?api-version=$apiVersion"
}
$zipPath = Join-Path $OutputDir 'it-assistant-teams-package.zip'
Invoke-WebRequest -Uri $zipUri -Headers $headers -OutFile $zipPath
Write-Host "  Saved: $zipPath" -ForegroundColor Green

Write-Host @"

=== Done ==========================================================

  Package : $zipPath

Next:
  - Teams:  Teams -> Apps -> Manage your apps -> Upload a custom app
  - M365:   admin.teams.microsoft.com -> Teams apps -> Manage apps ->
            Upload new app. Then in the M365 admin center:
            Copilot -> Agents -> Integrated apps -> set Default state to
            Available for the users who should see the agent.

===================================================================
"@ -ForegroundColor Cyan
