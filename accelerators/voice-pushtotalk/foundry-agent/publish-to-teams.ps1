<#
.SYNOPSIS
    Publish the Foundry IT Assistant agent to Microsoft 365 Copilot + Teams.

.DESCRIPTION
    Orchestrates the publish-copilot flow described in
    https://learn.microsoft.com/azure/foundry/agents/how-to/publish-copilot

    1. Ensures Microsoft.BotService is registered in the subscription.
    2. Calls the Foundry "publish" REST endpoint to turn the agent version into
       an agent application (creates an Entra app registration + Azure Bot
       Service resource behind the scenes).
    3. Polls status until "Ready".
    4. Downloads the Teams/M365 package zip to ./dist/<agent>.zip.
    5. Prints the exact portal click-path as a fallback if any step is not yet
       exposed in the REST surface on your Foundry ring.

    Prerequisites:
      - 'Azure AI Project Manager' on the Foundry project
      - Rights to create Azure Bot Service resources in the target subscription
      - Microsoft.BotService provider registered (script does this)

.PARAMETER FoundryEndpoint
    Foundry resource endpoint (same one passed to create-foundry-agent.ps1).

.PARAMETER ProjectId
    Foundry project ID.

.PARAMETER AssistantId
    The assistant id printed by create-foundry-agent.ps1.

.PARAMETER DisplayName
    Name shown in the agent store. Default: IT Assistant.

.PARAMETER Publisher
    Publisher name in the Teams manifest. Default: tenant display name.

.PARAMETER WebsiteUrl / PrivacyUrl / TermsUrl
    HTTPS URLs embedded in the package. Placeholders are fine for dev.

.PARAMETER OutputDir
    Where the zip is saved. Default: ./dist

.EXAMPLE
    ./publish-to-teams.ps1 `
        -FoundryEndpoint 'https://voicech-01-foundry.services.ai.azure.com' `
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

Write-Host "`n=== Foundry IT Assistant — Publish to Teams + M365 ===" -ForegroundColor Cyan

# ---------------------------------------------------------------------------
# Step 1 — Register Microsoft.BotService
# ---------------------------------------------------------------------------
Write-Host "`n[1/5] Registering Microsoft.BotService provider..." -ForegroundColor Yellow
az provider register --namespace Microsoft.BotService --wait --output none

# ---------------------------------------------------------------------------
# Step 2 — Acquire token + resolve defaults
# ---------------------------------------------------------------------------
Write-Host "`n[2/5] Acquiring Foundry token..." -ForegroundColor Yellow
$token = az account get-access-token --scope 'https://ai.azure.com/.default' --query accessToken -o tsv
if (-not $token) { Write-Error "Run 'az login' first."; exit 1 }
$headers = @{ Authorization = "Bearer $token"; 'Content-Type' = 'application/json' }

if (-not $Publisher) {
    $Publisher = az account show --query 'user.name' -o tsv
}

New-Item -ItemType Directory -Force -Path $OutputDir | Out-Null

# ---------------------------------------------------------------------------
# Step 3 — Kick off publish
# ---------------------------------------------------------------------------
Write-Host "`n[3/5] Submitting publish request..." -ForegroundColor Yellow

$publishUri = "$FoundryEndpoint/api/projects/$ProjectId/assistants/$AssistantId/publish?api-version=$apiVersion"

$publishBody = @{
    target = 'microsoft365'
    metadata = @{
        name             = $DisplayName
        shortDescription = 'Ask Microsoft Learn anything — voice or text.'
        fullDescription  = 'IT Assistant answers Microsoft product, Azure, M365, Power Platform, and developer questions using Microsoft Learn as its grounded source.'
        publisher        = $Publisher
        websiteUrl       = $WebsiteUrl
        privacyUrl       = $PrivacyUrl
        termsUrl         = $TermsUrl
    }
    botService = @{
        mode = 'createNew'
    }
    scope = 'individual'
} | ConvertTo-Json -Depth 5

try {
    $publish = Invoke-RestMethod -Method Post -Uri $publishUri -Headers $headers -Body $publishBody
} catch {
    Write-Warning "Publish REST endpoint returned an error: $($_.Exception.Message)"
    Write-Warning "The programmatic publish surface may not be available on your Foundry ring."
    Print-PortalFallback -Endpoint $FoundryEndpoint -AssistantId $AssistantId
    exit 1
}

$publishId = $publish.id

# ---------------------------------------------------------------------------
# Step 4 — Poll until Ready
# ---------------------------------------------------------------------------
Write-Host "`n[4/5] Waiting for package to be ready (1-3 minutes)..." -ForegroundColor Yellow

$deadline = (Get-Date).AddMinutes(10)
do {
    Start-Sleep -Seconds 10
    $status = Invoke-RestMethod -Method Get `
        -Uri "$FoundryEndpoint/api/projects/$ProjectId/assistants/$AssistantId/publish/${publishId}?api-version=$apiVersion" `
        -Headers $headers
    Write-Host ("  status: " + $status.status)
} while ($status.status -notin @('Ready', 'Failed') -and (Get-Date) -lt $deadline)

if ($status.status -ne 'Ready') {
    Write-Error "Publish did not reach Ready. Last status: $($status.status). $($status.error.message)"
    exit 1
}

# ---------------------------------------------------------------------------
# Step 5 — Download the package
# ---------------------------------------------------------------------------
Write-Host "`n[5/5] Downloading Teams / M365 package..." -ForegroundColor Yellow

$zipUri = $status.packageUrl
if (-not $zipUri) {
    Write-Warning "Response did not include a packageUrl — fetching by id."
    $zipUri = "$FoundryEndpoint/api/projects/$ProjectId/assistants/$AssistantId/publish/$publishId/package?api-version=$apiVersion"
}

$zipPath = Join-Path $OutputDir 'it-assistant-teams-package.zip'
Invoke-WebRequest -Uri $zipUri -Headers $headers -OutFile $zipPath
Write-Host "  Saved: $zipPath" -ForegroundColor Green

Write-Host @"

=== Done ==========================================================

  Package         : $zipPath

Next:
  - Teams:  Teams -> Apps -> Manage your apps -> Upload a custom app
            Select $zipPath.
  - M365:   https://admin.teams.microsoft.com -> Teams apps -> Manage apps ->
            Upload new app. Publish -> Granted. Then in the M365 admin center:
            Copilot -> Agents -> Integrated apps -> set Default state to
            Available.

See docs/publishing-via-foundry.md for the full walkthrough.

===================================================================
"@ -ForegroundColor Cyan

# ---------------------------------------------------------------------------
# Helper — portal fallback
# ---------------------------------------------------------------------------
function Print-PortalFallback {
    param([string]$Endpoint, [string]$AssistantId)
    Write-Host @"

=== Portal fallback ===============================================

The publish REST endpoint isn't available on your Foundry ring yet.
Do these steps in the portal (3-5 minutes):

  1. https://ai.azure.com -> select your project.
  2. Open the 'IT Assistant' agent (id: $AssistantId).
  3. Publish -> Publish to Teams and Microsoft 365 Copilot.
  4. Azure Bot Service: Create new.
  5. Fill metadata: $DisplayName, $Publisher, URLs.
  6. Prepare agent -> wait ~1-2 min.
  7. Download the package. Save it to dist/it-assistant-teams-package.zip.
  8. Teams -> Apps -> Upload custom app.

===================================================================
"@ -ForegroundColor Yellow
}
