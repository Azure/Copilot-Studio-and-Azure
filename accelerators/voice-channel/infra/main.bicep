// =============================================================================
// Voice Channel Accelerator — azd infrastructure
// Adapted from Azure-Samples/call-center-voice-agent-accelerator
// =============================================================================
// Provisions:
//   - Microsoft Foundry (AIServices) — hosts the IT Assistant Foundry Agent
//   - Azure Container Registry (ACR) — stores the server image
//   - Container Apps Environment + Container App — hosts the Voice Live relay + web UI
//   - Key Vault — holds the Copilot Studio Direct Line secret
//   - Log Analytics + Application Insights — observability
//   - User-assigned Managed Identity with:
//       - AcrPull on the registry
//       - Cognitive Services User + Azure AI User on the Foundry resource
//       - Key Vault Secrets User on the vault
//
// The Container App is tagged `azd-service-name: server` so `azd deploy`
// knows where to push the image built from ./server.

targetScope = 'resourceGroup'

// --------------------------- Parameters ------------------------------------

@minLength(1)
@maxLength(64)
@description('Name of the environment (azd sets this from `azd init`).')
param environmentName string

@minLength(1)
@description('Azure region. Must be one of the Voice Live supported regions.')
param location string

@description('Foundry model used when the IT Assistant is called by agent_id. Voice Live picks up this choice from the agent record after create-foundry-agent.ps1 runs.')
@allowed([
  'gpt-realtime'
  'gpt-realtime-mini'
  'gpt-4o'
  'gpt-4o-mini'
  'gpt-4.1'
  'gpt-4.1-mini'
])
param voiceLiveModel string = 'gpt-realtime-mini'

@description('TTS voice the web UI will use.')
param voiceName string = 'en-US-Ava:DragonHDLatestNeural'

@description('Copilot Studio agent display name the IT Assistant calls over Direct Line.')
param mcsAgentName string = 'Microsoft Learn Assistant'

@description('Principal ID of the user running azd. Granted Azure AI User on Foundry and Key Vault Secrets User on the vault so you can test locally. Leave empty to skip.')
param principalId string = ''

// --------------------------- Derived ---------------------------------------

var abbrs = loadJsonContent('./abbreviations.json')
var tags = {
  'azd-env-name': environmentName
}

var resourceToken = toLower(uniqueString(subscription().id, environmentName, location))

var foundryName             = '${abbrs.cognitiveServicesAccounts}${resourceToken}'
var foundryCustomDomain     = '${abbrs.cognitiveServicesAccounts}${resourceToken}'
var acrName                 = replace('${abbrs.containerRegistryRegistries}${resourceToken}', '-', '')
var caeName                 = '${abbrs.appManagedEnvironments}${resourceToken}'
var containerAppName        = '${abbrs.appContainerApps}${resourceToken}'
var managedIdentityName     = '${abbrs.managedIdentityUserAssignedIdentities}${resourceToken}'
var keyVaultName            = take('${abbrs.keyVaultVaults}${resourceToken}', 24)
var logAnalyticsName        = '${abbrs.operationalInsightsWorkspaces}${resourceToken}'
var appInsightsName         = '${abbrs.insightsComponents}${resourceToken}'

// Built-in role IDs
var acrPullRoleId                 = '7f951dda-4ed3-4680-a7ca-43fe172d538d'
var cognitiveServicesUserRoleId   = 'a97b65f3-24c7-4388-baec-2e87135dc908'
var azureAIUserRoleId             = '53ca6127-db72-4b80-b1b0-d745d6d5456d'
var keyVaultSecretsUserRoleId     = '4633458b-17de-408a-b874-0445c86b69e6'

// --------------------------- Managed identity ------------------------------

resource identity 'Microsoft.ManagedIdentity/userAssignedIdentities@2023-01-31' = {
  name: managedIdentityName
  location: location
  tags: tags
}

// --------------------------- Microsoft Foundry -----------------------------

resource foundry 'Microsoft.CognitiveServices/accounts@2024-10-01' = {
  name: foundryName
  location: location
  kind: 'AIServices'
  sku: { name: 'S0' }
  tags: tags
  identity: { type: 'SystemAssigned' }
  properties: {
    customSubDomainName: foundryCustomDomain
    publicNetworkAccess: 'Enabled'
    disableLocalAuth: false
  }
}

resource cognitiveUserAssignment 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(foundry.id, cognitiveServicesUserRoleId, identity.id)
  scope: foundry
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', cognitiveServicesUserRoleId)
    principalId: identity.properties.principalId
    principalType: 'ServicePrincipal'
  }
}

resource aiUserAssignment 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(foundry.id, azureAIUserRoleId, identity.id)
  scope: foundry
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', azureAIUserRoleId)
    principalId: identity.properties.principalId
    principalType: 'ServicePrincipal'
  }
}

// Also grant the deploying user, so they can test with az CLI locally
resource foundryUserForPrincipal 'Microsoft.Authorization/roleAssignments@2022-04-01' = if (!empty(principalId)) {
  name: guid(foundry.id, azureAIUserRoleId, principalId)
  scope: foundry
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', azureAIUserRoleId)
    principalId: principalId
    principalType: 'User'
  }
}

// --------------------------- Key Vault -------------------------------------

resource keyVault 'Microsoft.KeyVault/vaults@2024-04-01-preview' = {
  name: keyVaultName
  location: location
  tags: tags
  properties: {
    tenantId: subscription().tenantId
    sku: { family: 'A', name: 'standard' }
    enableRbacAuthorization: true
    softDeleteRetentionInDays: 7
    enablePurgeProtection: false
    publicNetworkAccess: 'Enabled'
  }
}

resource kvUserForContainer 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(keyVault.id, keyVaultSecretsUserRoleId, identity.id)
  scope: keyVault
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', keyVaultSecretsUserRoleId)
    principalId: identity.properties.principalId
    principalType: 'ServicePrincipal'
  }
}

resource kvUserForPrincipal 'Microsoft.Authorization/roleAssignments@2022-04-01' = if (!empty(principalId)) {
  name: guid(keyVault.id, keyVaultSecretsUserRoleId, principalId)
  scope: keyVault
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', keyVaultSecretsUserRoleId)
    principalId: principalId
    principalType: 'User'
  }
}

// --------------------------- Observability ---------------------------------

resource logAnalytics 'Microsoft.OperationalInsights/workspaces@2023-09-01' = {
  name: logAnalyticsName
  location: location
  tags: tags
  properties: {
    sku: { name: 'PerGB2018' }
    retentionInDays: 30
  }
}

resource appInsights 'Microsoft.Insights/components@2020-02-02' = {
  name: appInsightsName
  location: location
  kind: 'web'
  tags: tags
  properties: {
    Application_Type: 'web'
    WorkspaceResourceId: logAnalytics.id
  }
}

// --------------------------- Azure Container Registry ----------------------

resource acr 'Microsoft.ContainerRegistry/registries@2023-11-01-preview' = {
  name: acrName
  location: location
  tags: tags
  sku: { name: 'Basic' }
  properties: {
    adminUserEnabled: false
    anonymousPullEnabled: false
  }
}

resource acrPullAssignment 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(acr.id, acrPullRoleId, identity.id)
  scope: acr
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', acrPullRoleId)
    principalId: identity.properties.principalId
    principalType: 'ServicePrincipal'
  }
}

// --------------------------- Container Apps --------------------------------

resource containerAppsEnv 'Microsoft.App/managedEnvironments@2024-03-01' = {
  name: caeName
  location: location
  tags: tags
  properties: {
    appLogsConfiguration: {
      destination: 'log-analytics'
      logAnalyticsConfiguration: {
        customerId: logAnalytics.properties.customerId
        sharedKey: logAnalytics.listKeys().primarySharedKey
      }
    }
    zoneRedundant: false
  }
}

resource containerApp 'Microsoft.App/containerApps@2024-03-01' = {
  name: containerAppName
  location: location
  // azd uses this tag to locate where the `server` service deploys
  tags: union(tags, { 'azd-service-name': 'server' })
  identity: {
    type: 'UserAssigned'
    userAssignedIdentities: { '${identity.id}': {} }
  }
  dependsOn: [ acrPullAssignment ]
  properties: {
    managedEnvironmentId: containerAppsEnv.id
    configuration: {
      ingress: {
        external: true
        targetPort: 8000
        transport: 'auto'
        allowInsecure: false
        corsPolicy: {
          allowedOrigins: [ '*' ]
          allowedMethods: [ 'GET', 'POST', 'OPTIONS' ]
          allowedHeaders: [ '*' ]
        }
      }
      registries: [
        {
          server: acr.properties.loginServer
          identity: identity.id
        }
      ]
    }
    template: {
      containers: [
        {
          name: 'server'
          // azd overwrites this tag on `azd deploy`; start with a placeholder image
          image: '${acr.properties.loginServer}/voice-channel/server:latest'
          resources: {
            cpu: json('1.0')
            memory: '2Gi'
          }
          env: [
            { name: 'FOUNDRY_ENDPOINT',     value: foundry.properties.endpoint }
            { name: 'VOICE_LIVE_MODEL',     value: voiceLiveModel }
            { name: 'FOUNDRY_VOICE_NAME',   value: voiceName }
            // Filled post-deploy by create-foundry-agent.ps1 via `az containerapp update --set-env-vars`
            { name: 'FOUNDRY_AGENT_ID',     value: '' }
            { name: 'FOUNDRY_PROJECT_ID',   value: '' }
            // DefaultAzureCredential uses this to pick the UAI
            { name: 'AZURE_CLIENT_ID',      value: identity.properties.clientId }
            { name: 'APPLICATIONINSIGHTS_CONNECTION_STRING', value: appInsights.properties.ConnectionString }
            { name: 'MCS_AGENT_NAME',       value: mcsAgentName }
          ]
        }
      ]
      scale: {
        minReplicas: 1
        maxReplicas: 3
        rules: [
          {
            name: 'http-scaler'
            http: { metadata: { concurrentRequests: '20' } }
          }
        ]
      }
    }
  }
}

// --------------------------- Outputs ---------------------------------------

output AZURE_LOCATION                    string = location
output AZURE_TENANT_ID                   string = subscription().tenantId
output AZURE_RESOURCE_GROUP              string = resourceGroup().name
output AZURE_CONTAINER_REGISTRY_ENDPOINT string = acr.properties.loginServer
output AZURE_CONTAINER_REGISTRY_NAME     string = acr.name
output AZURE_CONTAINER_APP_NAME          string = containerApp.name
output AZURE_CONTAINER_APP_FQDN          string = containerApp.properties.configuration.ingress.fqdn
output FOUNDRY_NAME                      string = foundry.name
output FOUNDRY_ENDPOINT                  string = foundry.properties.endpoint
output FOUNDRY_RESOURCE_ID               string = foundry.id
output KEY_VAULT_NAME                    string = keyVault.name
output KEY_VAULT_URI                     string = keyVault.properties.vaultUri
output MANAGED_IDENTITY_CLIENT_ID        string = identity.properties.clientId
output MANAGED_IDENTITY_PRINCIPAL_ID     string = identity.properties.principalId
