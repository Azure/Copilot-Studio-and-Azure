<#
.SYNOPSIS
    Create the Foundry Agent Service "IT Assistant" agent, attach the
    Direct Line OpenAPI tool, and wire FOUNDRY_AGENT_ID / FOUNDRY_PROJECT_ID
    into the Container App that hosts the Voice Live relay.

.DESCRIPTION
    1. Authenticates to the Foundry project via az CLI (scope https://ai.azure.com/.default).
    2. Creates the assistant from it-assistant.agent.json.
    3. Attaches ask-mcs.openapi.yaml as an OpenAPI tool with the Direct Line
       secret baked into the bearer-auth scheme.
    4. Updates the Container App env vars so subsequent browser sessions
       reach the agent by agent_id + project_id (Voice Live agent mode).

.PARAMETER FoundryEndpoint
    Foundry resource endpoint, e.g. https://cog-xyz.services.ai.azure.com.
    azd exposes this as $env:FOUNDRY_ENDPOINT after `azd up`.

.PARAMETER ProjectId
    Foundry project ID. If omitted, the script lists projects and prompts.

.PARAMETER DirectLineSecret
    Copilot Studio Direct Line channel secret from copilot-studio-agent/create-agent.ps1.

.PARAMETER Model
    Foundry model name. Default: gpt-4.1.

.PARAMETER AgentName
    Agent display name. Default: IT Assistant.

.PARAMETER ContainerAppName
    Container App to update with FOUNDRY_AGENT_ID/FOUNDRY_PROJECT_ID. Falls
    back to $env:AZURE_CONTAINER_APP_NAME (exported by `azd env get-values`).

.PARAMETER ResourceGroup
    Resource group containing the Container App. Falls back to
    $env:AZURE_RESOURCE_GROUP.

.EXAMPLE
    azd env get-values > .env
    ./create-foundry-agent.ps1 `
        -FoundryEndpoint $env:FOUNDRY_ENDPOINT `
        -DirectLineSecret 'abc...def'
#>

param(
    [Parameter(Mandatory)]
    [string]$FoundryEndpoint,

    [string]$ProjectId = '',

    [Parameter(Mandatory)]
    [string]$DirectLineSecret,

    [string]$Model            = 'gpt-4.1',
    [string]$AgentName        = 'IT Assistant',
    [string]$ContainerAppName = $env:AZURE_CONTAINER_APP_NAME,
    [string]$ResourceGroup    = $env:AZURE_RESOURCE_GROUP
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

$scriptDir        = Split-Path -Parent $MyInvocation.MyCommand.Path
$instructionsFile = Join-Path $scriptDir 'it-assistant-instructions.md'
$agentJsonFile    = Join-Path $scriptDir 'it-assistant.agent.json'
$openApiFile      = Join-Path $scriptDir 'ask-mcs.openapi.yaml'

$apiVersion = '2025-10-01'

Write-Host "`n=== Foundry IT Assistant — Create ===" -ForegroundColor Cyan

# 1. Token ------------------------------------------------------------------
Write-Host "`n[1/5] Acquiring Foundry token..." -ForegroundColor Yellow
$token = az account get-access-token --scope 'https://ai.azure.com/.default' --query accessToken -o tsv
if (-not $token) { Write-Error "Run 'az login' first."; exit 1 }
$headers = @{ Authorization = "Bearer $token"; 'Content-Type' = 'application/json' }

# 2. Project ID --------------------------------------------------------------
if (-not $ProjectId) {
    Write-Host "`n[2/5] Listing Foundry projects..." -ForegroundColor Yellow
    $projects = Invoke-RestMethod -Method Get `
        -Uri "$FoundryEndpoint/api/projects?api-version=$apiVersion" `
        -Headers $headers
    if (-not $projects.value -or $projects.value.Count -eq 0) {
        Write-Error "No projects on $FoundryEndpoint. Create one in the Foundry portal first."
        exit 1
    }
    if ($projects.value.Count -eq 1) {
        $ProjectId = $projects.value[0].id
        Write-Host "  Using project: $($projects.value[0].name) ($ProjectId)" -ForegroundColor Green
    } else {
        for ($i = 0; $i -lt $projects.value.Count; $i++) {
            Write-Host "  [$i] $($projects.value[$i].name) — $($projects.value[$i].id)"
        }
        $idx = Read-Host "Select project"
        $ProjectId = $projects.value[[int]$idx].id
    }
} else {
    Write-Host "`n[2/5] Using project $ProjectId" -ForegroundColor Yellow
}

# 3. Create assistant --------------------------------------------------------
Write-Host "`n[3/5] Creating assistant '$AgentName'..." -ForegroundColor Yellow
$instructions     = (Get-Content $instructionsFile -Raw).Trim()
$instructionsJson = ($instructions | ConvertTo-Json -Compress).Trim('"')
$agentBody        = (Get-Content $agentJsonFile -Raw).Replace('${INSTRUCTIONS}', $instructionsJson).Replace('${MODEL}', $Model)

$agent = Invoke-RestMethod -Method Post `
    -Uri "$FoundryEndpoint/api/projects/$ProjectId/assistants?api-version=$apiVersion" `
    -Headers $headers -Body $agentBody

$assistantId = $agent.id
if (-not $assistantId) {
    Write-Error "Assistant create returned no id: $($agent | ConvertTo-Json -Depth 5)"
    exit 1
}
Write-Host "  Assistant id: $assistantId" -ForegroundColor Green

# 4. Attach OpenAPI tool with Direct Line secret ----------------------------
Write-Host "`n[4/5] Attaching ask_microsoft_learn_assistant tool..." -ForegroundColor Yellow
$openApiSpec = Get-Content $openApiFile -Raw
$toolBody = @{
    type = 'openapi'
    openapi = @{
        name        = 'ask_microsoft_learn_assistant'
        description = 'Answers Microsoft product / IT-pro questions via the Microsoft Learn Assistant Copilot Studio agent over Direct Line.'
        spec        = $openApiSpec
        auth = @{
            type           = 'connection'
            securityScheme = 'bearerAuth'
            credentials    = @{ bearer_token = $DirectLineSecret }
        }
    }
} | ConvertTo-Json -Depth 10

Invoke-RestMethod -Method Post `
    -Uri "$FoundryEndpoint/api/projects/$ProjectId/assistants/$assistantId/tools?api-version=$apiVersion" `
    -Headers $headers -Body $toolBody | Out-Null

Write-Host "  Tool attached." -ForegroundColor Green

# 5. Wire agent_id + project_id into the Container App ---------------------
Write-Host "`n[5/5] Updating Container App env vars..." -ForegroundColor Yellow
if (-not $ContainerAppName -or -not $ResourceGroup) {
    Write-Warning "ContainerAppName or ResourceGroup not provided; skipping Container App update."
    Write-Warning "Set them manually:"
    Write-Warning "  az containerapp update --resource-group <rg> --name <app> ``"
    Write-Warning "    --set-env-vars FOUNDRY_AGENT_ID=$assistantId FOUNDRY_PROJECT_ID=$ProjectId"
} else {
    az containerapp update `
        --resource-group $ResourceGroup `
        --name $ContainerAppName `
        --set-env-vars "FOUNDRY_AGENT_ID=$assistantId" "FOUNDRY_PROJECT_ID=$ProjectId" `
        --output none
    Write-Host "  Container App '$ContainerAppName' updated." -ForegroundColor Green
}

Write-Host @"

=== Done ==========================================================

  Project id    : $ProjectId
  Assistant id  : $assistantId
  Model         : $Model
  Tool          : ask_microsoft_learn_assistant (Direct Line, bearerAuth)

Next:
  - Visit the Container App URL (azd env get-values | findstr FQDN) to
    test the web UI.
  - Publish to Teams + M365 Copilot:
      ./publish-to-teams.ps1 ``
          -FoundryEndpoint '$FoundryEndpoint' ``
          -ProjectId       '$ProjectId' ``
          -AssistantId     '$assistantId'

===================================================================
"@ -ForegroundColor Cyan
