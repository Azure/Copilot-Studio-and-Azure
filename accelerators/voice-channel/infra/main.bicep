// Voice Channel Accelerator — Real-time voice for Copilot Studio via Voice Live
// Deploys:
//   - Microsoft Foundry (AIServices) resource with Voice Live
//   - Azure App Service (Linux, Python 3.11) hosting the bridge
//   - Log Analytics + Application Insights
//   - System-assigned managed identity on the App Service with keyless
//     access to the Foundry resource (Cognitive Services User + Azure AI User)

@description('Base name for all resources (lowercase, 3-18 chars, no spaces)')
@minLength(3)
@maxLength(18)
param baseName string

@description('Azure region. Must be a Voice Live supported region (e.g. swedencentral, eastus2, westus2, centralindia, southeastasia, westeurope).')
param location string = resourceGroup().location

@description('Voice Live model name used by the bridge (pro: gpt-realtime, gpt-4.1, gpt-5, gpt-5-chat; basic: gpt-realtime-mini, gpt-4.1-mini, gpt-5-mini; lite: gpt-5-nano, phi4-mini).')
param voiceLiveModel string = 'gpt-realtime-mini'

@description('TTS voice used by the IT Assistant. See Voice Live language-support docs.')
param voiceName string = 'en-US-Ava:DragonHDLatestNeural'

@description('App Service plan SKU (B1 is enough for a dozen concurrent users; use P1v3 for production).')
param appServicePlanSku string = 'B1'

@description('Copilot Studio agent display name used inside the Voice Live tool schema.')
param mcsAgentName string = 'Microsoft Learn Assistant'

// ---------------------------------------------------------------------------
// Derived names
// ---------------------------------------------------------------------------
var foundryName         = '${baseName}-foundry'
var foundryCustomDomain = toLower('${baseName}-foundry')
var appServiceName      = '${baseName}-bridge'
var appServicePlanName  = '${baseName}-plan'
var appInsightsName     = '${baseName}-insights'
var logAnalyticsName    = '${baseName}-logs'

// Built-in role IDs for Foundry keyless auth
var cognitiveServicesUserRoleId = 'a97b65f3-24c7-4388-baec-2e87135dc908' // Cognitive Services User
var azureAIUserRoleId           = '53ca6127-db72-4b80-b1b0-d745d6d5456d' // Azure AI User

// ---------------------------------------------------------------------------
// Microsoft Foundry resource (Voice Live is hosted here)
// ---------------------------------------------------------------------------
resource foundry 'Microsoft.CognitiveServices/accounts@2024-10-01' = {
  name: foundryName
  location: location
  kind: 'AIServices'
  sku: {
    name: 'S0'
  }
  identity: {
    type: 'SystemAssigned'
  }
  properties: {
    customSubDomainName: foundryCustomDomain
    publicNetworkAccess: 'Enabled'
    disableLocalAuth: false
  }
}

// ---------------------------------------------------------------------------
// Observability
// ---------------------------------------------------------------------------
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

// ---------------------------------------------------------------------------
// App Service plan + Bridge web app
// ---------------------------------------------------------------------------
resource appServicePlan 'Microsoft.Web/serverfarms@2024-04-01' = {
  name: appServicePlanName
  location: location
  kind: 'linux'
  sku: {
    name: appServicePlanSku
  }
  properties: {
    reserved: true
  }
}

resource bridgeApp 'Microsoft.Web/sites@2024-04-01' = {
  name: appServiceName
  location: location
  kind: 'app,linux'
  identity: {
    type: 'SystemAssigned'
  }
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
        { name: 'SCM_DO_BUILD_DURING_DEPLOYMENT',        value: 'true'  }
        { name: 'ENABLE_ORYX_BUILD',                      value: 'true'  }
        { name: 'APPINSIGHTS_INSTRUMENTATIONKEY',         value: appInsights.properties.InstrumentationKey }
        { name: 'APPLICATIONINSIGHTS_CONNECTION_STRING',  value: appInsights.properties.ConnectionString }

        // Voice Live configuration
        { name: 'FOUNDRY_ENDPOINT',      value: foundry.properties.endpoint }
        { name: 'FOUNDRY_WEBSOCKET_URL', value: 'wss://${foundryCustomDomain}.services.ai.azure.com/voice-live/realtime?api-version=2025-10-01&model=${voiceLiveModel}' }
        { name: 'VOICE_LIVE_MODEL',      value: voiceLiveModel }
        { name: 'FOUNDRY_VOICE_NAME',    value: voiceName }

        // Copilot Studio — filled in post-deploy via `az webapp config appsettings set`
        { name: 'DIRECTLINE_SECRET',     value: '' }
        { name: 'MCS_AGENT_NAME',        value: mcsAgentName }
        { name: 'MCS_TIMEOUT_SECONDS',   value: '20' }

        { name: 'ALLOWED_ORIGINS',       value: '*' }
      ]
    }
  }
}

// ---------------------------------------------------------------------------
// RBAC — bridge app's managed identity on the Foundry resource
// ---------------------------------------------------------------------------
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

// ---------------------------------------------------------------------------
// Outputs
// ---------------------------------------------------------------------------
output foundryName           string = foundry.name
output foundryEndpoint       string = foundry.properties.endpoint
output voiceLiveWebSocketUrl string = 'wss://${foundryCustomDomain}.services.ai.azure.com/voice-live/realtime?api-version=2025-10-01&model=${voiceLiveModel}'
output bridgeAppName         string = bridgeApp.name
output bridgeAppHostName     string = bridgeApp.properties.defaultHostName
output bridgePrincipalId     string = bridgeApp.identity.principalId
