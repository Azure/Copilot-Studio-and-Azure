// =============================================================================
// Voice Channel Accelerator — ONE-CLICK unified deployment
// =============================================================================
// Deploys everything the accelerator needs:
//   1. Microsoft Foundry (AIServices) with Voice Live
//   2. Azure App Service (Linux, Python 3.11) for the bridge
//   3. Log Analytics + App Insights + RBAC
//   4. Bridge application code (pulled from the repo's zip URL)
//   5. Copilot Studio "Microsoft Learn Assistant" agent (via pac CLI in a
//      Microsoft.Resources/deploymentScripts resource using a service
//      principal)
//   6. Wires the Direct Line secret from MCS back into the App Service
//
// Pre-requisites for the Copilot Studio side (because MCS runs in Dataverse,
// not Azure, it needs its own identity):
//   - An Entra service principal that is
//       * added as an Application User in the target Power Platform env
//       * granted Dataverse System Administrator role
//   - The target env URL (e.g. https://contoso.crm.dynamics.com)
//
// If you do not provide powerPlatformSpnClientId / powerPlatformSpnClientSecret
// the MCS script is skipped and you create the agent yourself with
// copilot-studio-agent/create-agent.ps1. The Azure side still deploys.
// =============================================================================

// --------------------------- Azure params -----------------------------------

@description('Base name for all Azure resources (lowercase, 3-18 chars, no spaces).')
@minLength(3)
@maxLength(18)
param baseName string

@description('Azure region. Must be a Voice Live supported region (e.g. swedencentral, eastus2, westus2, centralindia, southeastasia, westeurope).')
param location string = resourceGroup().location

@description('Voice Live model.')
@allowed([
  'gpt-realtime'
  'gpt-realtime-mini'
  'gpt-4o'
  'gpt-4o-mini'
  'gpt-4.1'
  'gpt-4.1-mini'
  'gpt-5'
  'gpt-5-mini'
  'gpt-5-nano'
  'gpt-5-chat'
  'phi4-mm-realtime'
  'phi4-mini'
])
param voiceLiveModel string = 'gpt-realtime-mini'

@description('TTS voice used by the IT Assistant.')
param voiceName string = 'en-US-Ava:DragonHDLatestNeural'

@description('App Service plan SKU.')
@allowed([ 'B1', 'B2', 'P1v3', 'P2v3' ])
param appServicePlanSku string = 'B1'

@description('Copilot Studio agent display name.')
param mcsAgentName string = 'Microsoft Learn Assistant'

@description('Public URL that the bridge-code deployment script will curl. Defaults to the zipped bridge/ folder in this repo.')
param bridgeCodeZipUrl string = 'https://github.com/Azure/Copilot-Studio-and-Azure/releases/latest/download/voice-channel-bridge.zip'

// --------------------------- Copilot Studio params --------------------------

@description('Full URL of the target Power Platform environment (e.g. https://contoso.crm.dynamics.com). Leave empty to skip MCS provisioning — you will then create the agent manually via create-agent.ps1.')
param powerPlatformEnvironmentUrl string = ''

@description('Entra tenant ID of the service principal. Defaults to the tenant of the Azure subscription.')
param entraTenantId string = tenant().tenantId

@description('Client ID of an Entra SPN that is registered as an Application User with Dataverse System Admin role in the target PP environment. Leave empty to skip MCS provisioning.')
param powerPlatformSpnClientId string = ''

@description('Client secret for the SPN. Leave empty to skip MCS provisioning.')
@secure()
param powerPlatformSpnClientSecret string = ''

// --------------------------- Derived ---------------------------------------

var foundryName         = '${baseName}-foundry'
var foundryCustomDomain = toLower('${baseName}-foundry')
var appServiceName      = '${baseName}-bridge'
var appServicePlanName  = '${baseName}-plan'
var appInsightsName     = '${baseName}-insights'
var logAnalyticsName    = '${baseName}-logs'

var provisionMcs = !empty(powerPlatformEnvironmentUrl) && !empty(powerPlatformSpnClientId) && !empty(powerPlatformSpnClientSecret)

var cognitiveServicesUserRoleId = 'a97b65f3-24c7-4388-baec-2e87135dc908'
var azureAIUserRoleId           = '53ca6127-db72-4b80-b1b0-d745d6d5456d'
var websiteContributorRoleId    = 'de139f84-1756-47ae-9be6-808fbbe84772' // Website Contributor — for the deployment-script MI to update app settings

var voiceLiveWsUrl = 'wss://${foundryCustomDomain}.services.ai.azure.com/voice-live/realtime?api-version=2025-10-01&model=${voiceLiveModel}'

// --------------------------- Foundry ---------------------------------------

resource foundry 'Microsoft.CognitiveServices/accounts@2024-10-01' = {
  name: foundryName
  location: location
  kind: 'AIServices'
  sku: { name: 'S0' }
  identity: { type: 'SystemAssigned' }
  properties: {
    customSubDomainName: foundryCustomDomain
    publicNetworkAccess: 'Enabled'
    disableLocalAuth: false
  }
}

// --------------------------- Observability ---------------------------------

resource logAnalytics 'Microsoft.OperationalInsights/workspaces@2023-09-01' = {
  name: logAnalyticsName
  location: location
  properties: {
    sku: { name: 'PerGB2018' }
    retentionInDays: 30
  }
}

resource appInsights 'Microsoft.Insights/components@2020-02-02' = {
  name: appInsightsName
  location: location
  kind: 'web'
  properties: {
    Application_Type: 'web'
    WorkspaceResourceId: logAnalytics.id
  }
}

// --------------------------- App Service ------------------------------------

resource appServicePlan 'Microsoft.Web/serverfarms@2024-04-01' = {
  name: appServicePlanName
  location: location
  kind: 'linux'
  sku: { name: appServicePlanSku }
  properties: { reserved: true }
}

resource bridgeApp 'Microsoft.Web/sites@2024-04-01' = {
  name: appServiceName
  location: location
  kind: 'app,linux'
  identity: { type: 'SystemAssigned' }
  properties: {
    serverFarmId: appServicePlan.id
    httpsOnly: true
    siteConfig: {
      linuxFxVersion: 'PYTHON|3.11'
      alwaysOn: appServicePlanSku != 'F1' && appServicePlanSku != 'B1' ? true : false
      ftpsState: 'Disabled'
      minTlsVersion: '1.2'
      webSocketsEnabled: true
      appCommandLine: 'gunicorn -k uvicorn.workers.UvicornWorker -b 0.0.0.0:8000 -w 2 --timeout 120 app:app'
      appSettings: [
        { name: 'SCM_DO_BUILD_DURING_DEPLOYMENT',        value: 'true' }
        { name: 'ENABLE_ORYX_BUILD',                      value: 'true' }
        { name: 'APPINSIGHTS_INSTRUMENTATIONKEY',         value: appInsights.properties.InstrumentationKey }
        { name: 'APPLICATIONINSIGHTS_CONNECTION_STRING',  value: appInsights.properties.ConnectionString }
        { name: 'FOUNDRY_ENDPOINT',                       value: foundry.properties.endpoint }
        { name: 'FOUNDRY_WEBSOCKET_URL',                  value: voiceLiveWsUrl }
        { name: 'VOICE_LIVE_MODEL',                       value: voiceLiveModel }
        { name: 'FOUNDRY_VOICE_NAME',                     value: voiceName }
        { name: 'DIRECTLINE_SECRET',                      value: '' } // overwritten by the MCS provisioning script below
        { name: 'MCS_AGENT_NAME',                         value: mcsAgentName }
        { name: 'MCS_TIMEOUT_SECONDS',                    value: '20' }
        { name: 'ALLOWED_ORIGINS',                        value: '*' }
      ]
    }
  }
}

// --------------------------- RBAC for the bridge MI ------------------------

resource cognitiveServicesUserAssignment 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(foundry.id, cognitiveServicesUserRoleId, bridgeApp.id)
  scope: foundry
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', cognitiveServicesUserRoleId)
    principalId: bridgeApp.identity.principalId
    principalType: 'ServicePrincipal'
  }
}

resource azureAIUserAssignment 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(foundry.id, azureAIUserRoleId, bridgeApp.id)
  scope: foundry
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', azureAIUserRoleId)
    principalId: bridgeApp.identity.principalId
    principalType: 'ServicePrincipal'
  }
}

// --------------------------- User-assigned MI for deployment scripts -------
// The MCS + code deployment scripts run with a user-assigned MI that has
// Website Contributor on the resource group, so they can write app settings
// and deploy zips.

resource deployScriptIdentity 'Microsoft.ManagedIdentity/userAssignedIdentities@2023-01-31' = {
  name: '${baseName}-deploy-mi'
  location: location
}

resource deployScriptRbac 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(resourceGroup().id, websiteContributorRoleId, deployScriptIdentity.id)
  scope: resourceGroup()
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', websiteContributorRoleId)
    principalId: deployScriptIdentity.properties.principalId
    principalType: 'ServicePrincipal'
  }
}

// --------------------------- Bridge code deployment ------------------------
// Pulls the bridge zip, unzips, and deploys via Zip Deploy to the App Service.

resource codeDeployScript 'Microsoft.Resources/deploymentScripts@2023-08-01' = {
  name: '${baseName}-deploy-code'
  location: location
  kind: 'AzureCLI'
  dependsOn: [ deployScriptRbac ]
  identity: {
    type: 'UserAssigned'
    userAssignedIdentities: { '${deployScriptIdentity.id}': {} }
  }
  properties: {
    azCliVersion: '2.60.0'
    retentionInterval: 'PT1H'
    timeout: 'PT20M'
    cleanupPreference: 'OnSuccess'
    environmentVariables: [
      { name: 'ZIP_URL',  value: bridgeCodeZipUrl }
      { name: 'RG',       value: resourceGroup().name }
      { name: 'APP_NAME', value: bridgeApp.name }
    ]
    scriptContent: '''
      set -euo pipefail
      echo "Downloading bridge code from $ZIP_URL ..."
      curl -fsSL "$ZIP_URL" -o /tmp/bridge.zip || {
        echo "WARN: bridge zip not found at $ZIP_URL — skipping code deploy."
        echo "Run this manually once the zip is published:"
        echo "  az webapp deploy --resource-group $RG --name $APP_NAME --src-url '$ZIP_URL' --type zip"
        exit 0
      }
      echo "Deploying to App Service $APP_NAME ..."
      az webapp deploy --resource-group "$RG" --name "$APP_NAME" --src-path /tmp/bridge.zip --type zip
      echo "done"
    '''
  }
}

// --------------------------- Copilot Studio deployment ---------------------
// Runs only when SPN creds are supplied. Uses pac CLI inside the deployment
// script container, installs it via dotnet tool, creates the agent from
// inline YAML, enables Direct Line, and writes the secret to App Service.

resource mcsDeployScript 'Microsoft.Resources/deploymentScripts@2023-08-01' = if (provisionMcs) {
  name: '${baseName}-deploy-mcs'
  location: location
  kind: 'AzurePowerShell'
  dependsOn: [ deployScriptRbac ]
  identity: {
    type: 'UserAssigned'
    userAssignedIdentities: { '${deployScriptIdentity.id}': {} }
  }
  properties: {
    azPowerShellVersion: '11.5'
    retentionInterval: 'PT1H'
    timeout: 'PT30M'
    cleanupPreference: 'OnSuccess'
    environmentVariables: [
      { name: 'PP_ENV_URL',    value: powerPlatformEnvironmentUrl }
      { name: 'SP_TENANT',     value: entraTenantId }
      { name: 'SP_CLIENT_ID',  value: powerPlatformSpnClientId }
      { name: 'SP_SECRET',     secureValue: powerPlatformSpnClientSecret }
      { name: 'AGENT_NAME',    value: mcsAgentName }
      { name: 'SCHEMA_NAME',   value: 'microsoft_learn_assistant' }
      { name: 'APP_NAME',      value: bridgeApp.name }
      { name: 'RG',            value: resourceGroup().name }
    ]
    scriptContent: '''
      $ErrorActionPreference = "Stop"

      Write-Host "=== Installing pac CLI ===" -ForegroundColor Cyan
      try {
        dotnet tool install --global Microsoft.PowerApps.CLI.Tool | Out-Null
      } catch {
        Write-Host "pac already installed or install returned non-zero; continuing"
      }
      $env:PATH = "$env:PATH" + [IO.Path]::PathSeparator + "$HOME/.dotnet/tools"

      Write-Host "`n=== Authenticating pac with SPN ===" -ForegroundColor Cyan
      pac auth create `
        --name "oneclick" `
        --tenant "$env:SP_TENANT" `
        --applicationId "$env:SP_CLIENT_ID" `
        --clientSecret "$env:SP_SECRET" `
        --environment "$env:PP_ENV_URL"

      Write-Host "`n=== Writing agent.yaml ===" -ForegroundColor Cyan
      $agentYaml = @"
schemaVersion: "1.0"
kind: DeclarativeAgent
name: "$env:AGENT_NAME"
description: Answers Microsoft product and IT-pro questions using Microsoft Learn.
instructions: |
  You are the Microsoft Learn Assistant. Every answer must be grounded in
  results from the Microsoft Learn MCP tool. Call microsoft_docs_search first,
  optionally follow up with microsoft_docs_fetch. Cite Learn article titles
  inline. Keep answers under 6 sentences. Plain prose only — no code fences,
  no markdown tables, no long URLs (you are frequently called by a voice agent).
aiSettings:
  generativeMode: enabled
  temperature: 0.3
tools:
  - kind: ModelContextProtocolTool
    name: "Microsoft Learn MCP"
    server:
      transport: streamableHttp
      url: "https://learn.microsoft.com/api/mcp"
      authentication:
        type: none
channels:
  directLine:
    enabled: true
  microsoftTeams:
    enabled: true
"@
      Set-Content -Path ./agent.yaml -Value $agentYaml -Encoding UTF8

      Write-Host "`n=== Creating agent '$env:AGENT_NAME' ===" -ForegroundColor Cyan
      $created = $false
      try {
        pac copilot create --file ./agent.yaml --name "$env:AGENT_NAME" --schema-name "$env:SCHEMA_NAME"
        if ($LASTEXITCODE -eq 0) { $created = $true }
      } catch {
        Write-Host "pac copilot create failed, trying fallback verb"
      }
      if (-not $created) {
        pac copilot new --name "$env:AGENT_NAME" --schema-name "$env:SCHEMA_NAME"
        pac copilot update --schema-name "$env:SCHEMA_NAME" --file ./agent.yaml
      }

      Write-Host "`n=== Publishing agent ===" -ForegroundColor Cyan
      pac copilot publish --schema-name "$env:SCHEMA_NAME"

      Write-Host "`n=== Enabling Direct Line channel ===" -ForegroundColor Cyan
      pac copilot channel enable --schema-name "$env:SCHEMA_NAME" --channel directLine
      $secretJson = pac copilot channel show-secret --schema-name "$env:SCHEMA_NAME" --channel directLine --output json
      $secret = ($secretJson | ConvertFrom-Json).secret

      if (-not $secret) {
        throw "Failed to capture Direct Line secret."
      }

      Write-Host "`n=== Writing DIRECTLINE_SECRET to App Service '$env:APP_NAME' ===" -ForegroundColor Cyan
      az login --identity | Out-Null
      az webapp config appsettings set `
        --resource-group "$env:RG" `
        --name "$env:APP_NAME" `
        --settings "DIRECTLINE_SECRET=$secret" | Out-Null

      $DeploymentScriptOutputs = @{}
      $DeploymentScriptOutputs['agentName']   = $env:AGENT_NAME
      $DeploymentScriptOutputs['schemaName']  = $env:SCHEMA_NAME
      $DeploymentScriptOutputs['secretSet']   = 'true'

      Write-Host "`n=== Done ===" -ForegroundColor Green
    '''
  }
}

// --------------------------- Outputs ---------------------------------------

output foundryName           string = foundry.name
output foundryEndpoint       string = foundry.properties.endpoint
output voiceLiveWebSocketUrl string = voiceLiveWsUrl
output bridgeAppName         string = bridgeApp.name
output bridgeAppHostName     string = bridgeApp.properties.defaultHostName
output bridgeUrl             string = 'https://${bridgeApp.properties.defaultHostName}'
output bridgePrincipalId     string = bridgeApp.identity.principalId
output mcsProvisioned        bool   = provisionMcs
