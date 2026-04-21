<#
.SYNOPSIS
    Create the Foundry Agent Service "IT Assistant" agent and attach the
    Direct Line OpenAPI tool that calls the Microsoft Learn Assistant.

.DESCRIPTION
    1. Authenticates to the Foundry project with az CLI (scope: https://ai.azure.com/.default).
    2. Calls POST /api/projects/{project}/assistants with the body from
       it-assistant.agent.json, substituting ${INSTRUCTIONS} and ${MODEL}.
    3. Attaches ask-mcs.openapi.yaml as an OpenAPI tool with the Direct Line
       secret wired into the bearer-auth scheme.
    4. Prints the assistant_id for use by publish-to-teams.ps1.

    Authentication: uses the signed-in Azure CLI identity. That identity needs
    "Azure AI Project Manager" on the Foundry project.

.PARAMETER FoundryEndpoint
    Foundry resource endpoint, e.g. https://voicech-01-foundry.services.ai.azure.com.
    Get this from the infra/deploy.ps1 output.

.PARAMETER ProjectId
    The Foundry project ID. If omitted, the script lists projects on the
    resource and prompts you to pick one.

.PARAMETER DirectLineSecret
    Copilot Studio Direct Line channel secret (from copilot-studio-agent/create-agent.ps1).

.PARAMETER Model
    Foundry model deployment name. Default: gpt-4.1.

.PARAMETER AgentName
    Agent display name. Default: IT Assistant.

.EXAMPLE
    ./create-foundry-agent.ps1 `
        -FoundryEndpoint 'https://voicech-01-foundry.services.ai.azure.com' `
        -DirectLineSecret 'abc...def' `
        -Model 'gpt-4.1'
#>

param(
    [Parameter(Mandatory)]
    [string]$FoundryEndpoint,

    [string]$ProjectId = '',

    [Parameter(Mandatory)]
    [string]$DirectLineSecret,

    [string]$Model = 'gpt-4.1',
    [string]$AgentName = 'IT Assistant'
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

$scriptDir       = Split-Path -Parent $MyInvocation.MyCommand.Path
$instructionsFile = Join-Path $scriptDir 'it-assistant-instructions.md'
$agentJsonFile    = Join-Path $scriptDir 'it-assistant.agent.json'
$openApiFile      = Join-Path $scriptDir 'ask-mcs.openapi.yaml'

$apiVersion = '2025-10-01'

Write-Host "`n=== Foundry IT Assistant — Create ===" -ForegroundColor Cyan

# ---------------------------------------------------------------------------
# Step 1 — Acquire token
# ---------------------------------------------------------------------------
Write-Host "`n[1/4] Acquiring Foundry token..." -ForegroundColor Yellow
$token = az account get-access-token --scope 'https://ai.azure.com/.default' --query accessToken -o tsv
if (-not $token) {
    Write-Error "Could not acquire token. Run 'az login' first."
    exit 1
}
$headers = @{
    Authorization  = "Bearer $token"
    'Content-Type' = 'application/json'
}

# ---------------------------------------------------------------------------
# Step 2 — Resolve project ID
# ---------------------------------------------------------------------------
if (-not $ProjectId) {
    Write-Host "`n[2/4] Listing Foundry projects..." -ForegroundColor Yellow
    $projects = Invoke-RestMethod `
        -Method Get `
        -Uri  "$FoundryEndpoint/api/projects?api-version=$apiVersion" `
        -Headers $headers
    if (-not $projects.value -or $projects.value.Count -eq 0) {
        Write-Error "No projects found on $FoundryEndpoint. Create one in the Foundry portal first."
        exit 1
    }
    if ($projects.value.Count -eq 1) {
        $ProjectId = $projects.value[0].id
        Write-Host "  Using project: $($projects.value[0].name) ($ProjectId)" -ForegroundColor Green
    }
    else {
        for ($i = 0; $i -lt $projects.value.Count; $i++) {
            Write-Host "  [$i] $($projects.value[$i].name) — $($projects.value[$i].id)"
        }
        $idx = Read-Host "Select project"
        $ProjectId = $projects.value[[int]$idx].id
    }
}

# ---------------------------------------------------------------------------
# Step 3 — Create assistant
# ---------------------------------------------------------------------------
Write-Host "`n[3/4] Creating assistant '$AgentName'..." -ForegroundColor Yellow

$instructions = (Get-Content $instructionsFile -Raw).Trim()
$instructionsJson = ($instructions | ConvertTo-Json -Compress).Trim('"')

$agentBody = (Get-Content $agentJsonFile -Raw) `
                .Replace('${INSTRUCTIONS}', $instructionsJson) `
                .Replace('${MODEL}', $Model)

$agent = Invoke-RestMethod `
    -Method Post `
    -Uri "$FoundryEndpoint/api/projects/$ProjectId/assistants?api-version=$apiVersion" `
    -Headers $headers `
    -Body $agentBody

$assistantId = $agent.id
if (-not $assistantId) {
    Write-Error "Assistant creation returned no id. Response: $($agent | ConvertTo-Json -Depth 5)"
    exit 1
}
Write-Host "  Assistant id: $assistantId" -ForegroundColor Green

# ---------------------------------------------------------------------------
# Step 4 — Attach OpenAPI tool with Direct Line secret
# ---------------------------------------------------------------------------
Write-Host "`n[4/4] Attaching ask_microsoft_learn_assistant tool..." -ForegroundColor Yellow

$openApiSpec = Get-Content $openApiFile -Raw

$toolBody = @{
    type    = 'openapi'
    openapi = @{
        name            = 'ask_microsoft_learn_assistant'
        description     = 'Answers Microsoft product / IT-pro questions via the Microsoft Learn Assistant Copilot Studio agent over Direct Line.'
        spec            = $openApiSpec
        auth = @{
            type          = 'connection'
            securityScheme = 'bearerAuth'
            credentials   = @{
                bearer_token = $DirectLineSecret
            }
        }
    }
} | ConvertTo-Json -Depth 10

$tool = Invoke-RestMethod `
    -Method Post `
    -Uri "$FoundryEndpoint/api/projects/$ProjectId/assistants/$assistantId/tools?api-version=$apiVersion" `
    -Headers $headers `
    -Body $toolBody

Write-Host "  Tool attached: $($tool.id)" -ForegroundColor Green

Write-Host @"

=== Done ==========================================================

  Project id      : $ProjectId
  Assistant id    : $assistantId
  Model           : $Model
  Tool            : ask_microsoft_learn_assistant (Direct Line)

Next: publish to Microsoft 365 Copilot + Teams:

  ./publish-to-teams.ps1 ``
      -FoundryEndpoint '$FoundryEndpoint' ``
      -ProjectId '$ProjectId' ``
      -AssistantId '$assistantId'

===================================================================
"@ -ForegroundColor Cyan
