// Voice Channel Accelerator — infrastructure (no bridge)
// Provisions:
//   - Microsoft Foundry (AIServices) resource with custom subdomain
//   - Log Analytics + Application Insights for observability
//
// The Copilot Studio agent is created by copilot-studio-agent/create-agent.ps1.
// The Foundry "IT Assistant" agent is created by foundry-agent/create-foundry-agent.ps1.
// The agent is published to Teams / M365 Copilot by foundry-agent/publish-to-teams.ps1
// (which registers Microsoft.BotService and creates an Azure Bot Service resource).
//
// For a fully one-click experience (this Bicep + MCS provisioning + Foundry agent
// creation + Key Vault secret wiring) use deploy/main.bicep instead.

@description('Base name for all resources (lowercase, 3-18 chars).')
@minLength(3)
@maxLength(18)
param baseName string

@description('Azure region. Any region where Microsoft Foundry / Azure Bot Service are available.')
param location string = resourceGroup().location

// ---------------------------------------------------------------------------
// Derived names
// ---------------------------------------------------------------------------
var foundryName         = '${baseName}-foundry'
var foundryCustomDomain = toLower('${baseName}-foundry')
var appInsightsName     = '${baseName}-insights'
var logAnalyticsName    = '${baseName}-logs'

// ---------------------------------------------------------------------------
// Microsoft Foundry (hosts the IT Assistant Foundry Agent Service agent)
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
// Outputs — consumed by the post-deploy scripts in foundry-agent/ and
// copilot-studio-agent/
// ---------------------------------------------------------------------------
output foundryName               string = foundry.name
output foundryEndpoint           string = foundry.properties.endpoint
output foundryResourceId         string = foundry.id
output foundryPrincipalId        string = foundry.identity.principalId
output appInsightsConnection     string = appInsights.properties.ConnectionString
output logAnalyticsWorkspaceId   string = logAnalytics.id
