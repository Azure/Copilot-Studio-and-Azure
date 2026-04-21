<#
.SYNOPSIS
    Provision the "Microsoft Learn Assistant" Copilot Studio agent using pac CLI.

.DESCRIPTION
    1. Authenticates pac against the target Power Platform environment.
    2. Creates the agent from agent.yaml (declarative agent format).
    3. Attaches the Microsoft Learn MCP tool.
    4. Publishes the agent.
    5. Enables the Direct Line channel and prints the channel secret.

    The Direct Line secret is what the bridge App Service uses to talk to
    this agent. Paste it into the App Service settings (DIRECTLINE_SECRET).

.PARAMETER EnvironmentUrl
    Full URL of the target Dataverse environment
    (e.g. https://contoso.crm.dynamics.com).

.PARAMETER AgentName
    Display name. Defaults to "Microsoft Learn Assistant". Must match the
    MCS_AGENT_NAME setting on the bridge.

.PARAMETER SchemaName
    Internal schema name (letters/digits/underscore). Defaults to
    "microsoft_learn_assistant".

.EXAMPLE
    ./create-agent.ps1 -EnvironmentUrl https://contoso.crm.dynamics.com
#>

param(
    [Parameter(Mandatory)]
    [string]$EnvironmentUrl,

    [string]$AgentName = "Microsoft Learn Assistant",
    [string]$SchemaName = "microsoft_learn_assistant"
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$agentYaml = Join-Path $scriptDir 'agent.yaml'

# ---------------------------------------------------------------------------
# Sanity: pac installed?
# ---------------------------------------------------------------------------
$pacVersion = (& pac --version) 2>$null
if (-not $pacVersion) {
    Write-Error "Power Platform CLI (pac) not found. Install with: dotnet tool install --global Microsoft.PowerApps.CLI.Tool"
    exit 1
}
Write-Host "pac version: $pacVersion"

# ---------------------------------------------------------------------------
# Step 1 — Select/create auth profile for the environment
# ---------------------------------------------------------------------------
Write-Host "`n[1/5] Authenticating pac..." -ForegroundColor Yellow
pac auth create --environment $EnvironmentUrl --name 'voice-channel' | Out-Host
pac auth select --name 'voice-channel' | Out-Host
pac org who | Out-Host

# ---------------------------------------------------------------------------
# Step 2 — Create the agent
# ---------------------------------------------------------------------------
Write-Host "`n[2/5] Creating agent '$AgentName'..." -ForegroundColor Yellow

# The declarative-agent `pac copilot create --file` verb is the modern path.
# Older pac versions use `pac copilot new --name <n>` followed by
# `pac copilot edit --file agent.yaml`. Both are shown below; the script
# tries the newer verb first and falls back.
$createOk = $false
try {
    pac copilot create `
        --environment $EnvironmentUrl `
        --file $agentYaml `
        --name $AgentName `
        --schema-name $SchemaName | Out-Host
    $createOk = ($LASTEXITCODE -eq 0)
} catch {
    $createOk = $false
}

if (-not $createOk) {
    Write-Host "  `pac copilot create` not available or failed; falling back to `pac copilot new`..." -ForegroundColor DarkYellow
    pac copilot new `
        --environment $EnvironmentUrl `
        --name $AgentName `
        --schema-name $SchemaName | Out-Host
    pac copilot update `
        --environment $EnvironmentUrl `
        --schema-name $SchemaName `
        --file $agentYaml | Out-Host
}

# ---------------------------------------------------------------------------
# Step 3 — Publish
# ---------------------------------------------------------------------------
Write-Host "`n[3/5] Publishing agent..." -ForegroundColor Yellow
pac copilot publish `
    --environment $EnvironmentUrl `
    --schema-name $SchemaName | Out-Host

# ---------------------------------------------------------------------------
# Step 4 — Enable Direct Line channel
# ---------------------------------------------------------------------------
Write-Host "`n[4/5] Enabling Direct Line channel..." -ForegroundColor Yellow
pac copilot channel enable `
    --environment $EnvironmentUrl `
    --schema-name $SchemaName `
    --channel directLine | Out-Host

$secretJson = pac copilot channel show-secret `
    --environment $EnvironmentUrl `
    --schema-name $SchemaName `
    --channel directLine `
    --output json
$secret = ($secretJson | ConvertFrom-Json).secret

if (-not $secret) {
    Write-Warning "Could not read Direct Line secret automatically."
    Write-Warning "Open https://copilotstudio.microsoft.com -> $AgentName -> Channels -> Direct Line -> copy the secret manually."
} else {
    Write-Host "  Direct Line secret captured." -ForegroundColor Green
}

# ---------------------------------------------------------------------------
# Step 5 — Print next steps
# ---------------------------------------------------------------------------
Write-Host "`n[5/5] Done. Next steps:" -ForegroundColor Yellow
Write-Host @"

  Agent name         : $AgentName
  Schema name        : $SchemaName
  Environment        : $EnvironmentUrl
  Direct Line secret : $(if ($secret) { '[captured — see below]' } else { '[MANUAL COPY REQUIRED]' })

  Wire the secret into the bridge App Service:

    az webapp config appsettings set ``
        --resource-group <rg> ``
        --name <bridge-app-name> ``
        --settings DIRECTLINE_SECRET='$secret' MCS_AGENT_NAME='$AgentName'

  Then deploy the bridge code:

    cd ../bridge
    az webapp up --runtime 'PYTHON:3.11' --name <bridge-app-name> --resource-group <rg>

"@ -ForegroundColor Green

if ($secret) {
    Write-Host "Direct Line secret (copy this — shown once):" -ForegroundColor Cyan
    Write-Host $secret -ForegroundColor White
}
