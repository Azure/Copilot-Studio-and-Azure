// =============================================================================
// Voice Channel Accelerator — ONE-CLICK deployment (Azure + Power Platform)
// =============================================================================
// Combines:
//   1. Everything from infra/main.bicep (Foundry, ACR, Container App, Key
//      Vault, Log Analytics, Application Insights, user-assigned MI + RBAC).
//   2. A `build-server-image` deploymentScript that runs `az acr build`
//      against the GitHub source of this accelerator, so the container app
//      gets a real image on first deploy — no local Docker needed.
//   3. An optional `provision-mcs` deploymentScript (gated on Power Platform
//      SPN parameters) that creates the "Microsoft Learn Assistant" Copilot
//      Studio agent, enables Direct Line, and writes the channel secret to
//      Key Vault. If you skip it, run copilot-studio-agent/create-agent.ps1
//      from your workstation instead.
//
// After this deployment finishes, you still run these from your workstation:
//   ./foundry-agent/create-foundry-agent.ps1   (creates IT Assistant + wires
//                                                FOUNDRY_AGENT_ID into the CA)
//   ./foundry-agent/publish-to-teams.ps1       (publishes to Teams + M365)
//
// No Azure Bot Service or Teams plumbing is part of this Bicep — the Foundry
// publish-copilot flow creates those when you run publish-to-teams.ps1.

targetScope = 'resourceGroup'

// --------------------------- Azure params -----------------------------------

@minLength(1)
@maxLength(64)
@description('Environment name used for resource naming.')
param environmentName string = 'voice-channel'

@description('Azure region.')
param location string = resourceGroup().location

@description('Voice Live model used for real-time streaming (used by the server before create-foundry-agent.ps1 runs).')
@allowed([
  'gpt-realtime'
  'gpt-realtime-mini'
])
param voiceLiveModel string = 'gpt-realtime-mini'

@description('TTS voice the web UI will use.')
param voiceName string = 'en-US-Ava:DragonHDLatestNeural'

@description('Copilot Studio agent display name.')
param mcsAgentName string = 'Microsoft Learn Assistant'

@description('GitHub raw URL of the voice-channel repo root. Used by the ACR build step to fetch the Dockerfile + server code.')
param gitSourceUrl string = 'https://github.com/Azure/Copilot-Studio-and-Azure.git'

@description('Git branch used for the ACR build.')
param gitBranch string = 'main'

@description('Principal ID of the user running the deployment. Granted Azure AI User on Foundry and Key Vault Secrets User on the vault. Leave empty to skip.')
param principalId string = ''

// --------------------------- Copilot Studio (optional) ---------------------

@description('URL of the Power Platform environment (e.g. https://contoso.crm.dynamics.com). Leave empty to skip MCS provisioning — run copilot-studio-agent/create-agent.ps1 manually instead.')
param powerPlatformEnvironmentUrl string = ''

@description('Entra tenant ID. Defaults to the current subscription tenant.')
param entraTenantId string = tenant().tenantId

@description('Entra SPN client ID registered as an Application User + Dataverse System Admin in the PP env. Leave empty to skip.')
param powerPlatformSpnClientId string = ''

@description('Secret for the SPN. Leave empty to skip.')
@secure()
param powerPlatformSpnClientSecret string = ''

// --------------------------- Derived ---------------------------------------

var abbrs = loadJsonContent('../infra/abbreviations.json')
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

var provisionMcs = !empty(powerPlatformEnvironmentUrl) && !empty(powerPlatformSpnClientId) && !empty(powerPlatformSpnClientSecret)
var directLineSecretName = 'mcs-directline-secret'

// Built-in role IDs
var acrPullRoleId                 = '7f951dda-4ed3-4680-a7ca-43fe172d538d'
var acrPushRoleId                 = '8311e382-0749-4cb8-b61a-304f252e45ec'
var contributorRoleId             = 'b24988ac-6180-42a0-ab88-20f7382dd24c'
var cognitiveServicesUserRoleId   = 'a97b65f3-24c7-4388-baec-2e87135dc908'
var azureAIUserRoleId             = '53ca6127-db72-4b80-b1b0-d745d6d5456d'
var keyVaultSecretsOfficerRoleId  = 'b86a8fe4-44ce-4948-aee5-eccb2c155cd7'
var keyVaultSecretsUserRoleId     = '4633458b-17de-408a-b874-0445c86b69e6'

// --------------------------- Managed identity (shared) ---------------------

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

resource kvSecretsUserForContainer 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(keyVault.id, keyVaultSecretsUserRoleId, identity.id)
  scope: keyVault
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', keyVaultSecretsUserRoleId)
    principalId: identity.properties.principalId
    principalType: 'ServicePrincipal'
  }
}

resource kvSecretsOfficerForIdentity 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  // Same UAI writes + reads. Officer is a superset of User.
  name: guid(keyVault.id, keyVaultSecretsOfficerRoleId, identity.id)
  scope: keyVault
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', keyVaultSecretsOfficerRoleId)
    principalId: identity.properties.principalId
    principalType: 'ServicePrincipal'
  }
}

resource kvSecretsUserForPrincipal 'Microsoft.Authorization/roleAssignments@2022-04-01' = if (!empty(principalId)) {
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

// The build-image deployment script needs push rights too
resource acrPushAssignment 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(acr.id, acrPushRoleId, identity.id)
  scope: acr
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', acrPushRoleId)
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

// Permission for the deployment scripts to later update the Container App
resource containerAppContributor 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(resourceGroup().id, contributorRoleId, identity.id)
  scope: resourceGroup()
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', contributorRoleId)
    principalId: identity.properties.principalId
    principalType: 'ServicePrincipal'
  }
}

resource containerApp 'Microsoft.App/containerApps@2024-03-01' = {
  name: containerAppName
  location: location
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
          // build-server-image deploymentScript updates this tag after build
          image: 'mcr.microsoft.com/k8se/quickstart:latest'
          resources: {
            cpu: json('1.0')
            memory: '2Gi'
          }
          env: [
            { name: 'FOUNDRY_ENDPOINT',     value: foundry.properties.endpoint }
            { name: 'VOICE_LIVE_MODEL',     value: voiceLiveModel }
            { name: 'FOUNDRY_VOICE_NAME',   value: voiceName }
            { name: 'FOUNDRY_AGENT_ID',     value: '' }
            { name: 'FOUNDRY_PROJECT_ID',   value: '' }
            { name: 'AZURE_CLIENT_ID',      value: identity.properties.clientId }
            { name: 'APPLICATIONINSIGHTS_CONNECTION_STRING', value: appInsights.properties.ConnectionString }
            { name: 'MCS_AGENT_NAME',       value: mcsAgentName }
          ]
        }
      ]
      scale: {
        minReplicas: 1
        maxReplicas: 3
        rules: [ { name: 'http-scaler', http: { metadata: { concurrentRequests: '20' } } } ]
      }
    }
  }
}

// --------------------------- Deployment script: build the container image -

resource buildImageScript 'Microsoft.Resources/deploymentScripts@2023-08-01' = {
  name: '${environmentName}-build-image'
  location: location
  kind: 'AzureCLI'
  dependsOn: [ acrPushAssignment, containerAppContributor ]
  identity: {
    type: 'UserAssigned'
    userAssignedIdentities: { '${identity.id}': {} }
  }
  properties: {
    azCliVersion: '2.60.0'
    retentionInterval: 'PT1H'
    timeout: 'PT30M'
    cleanupPreference: 'OnSuccess'
    environmentVariables: [
      { name: 'ACR_NAME',        value: acr.name }
      { name: 'GIT_URL',         value: gitSourceUrl }
      { name: 'GIT_BRANCH',      value: gitBranch }
      { name: 'IMAGE_TAG',       value: '${acr.properties.loginServer}/voice-channel/server:initial' }
      { name: 'APP_NAME',        value: containerApp.name }
      { name: 'RG',              value: resourceGroup().name }
    ]
    scriptContent: '''
      set -euo pipefail
      echo "=== Building server image via ACR Tasks ==="
      echo "  registry : $ACR_NAME"
      echo "  git      : $GIT_URL @ $GIT_BRANCH"
      echo "  image    : $IMAGE_TAG"

      # --source accepts: <repo>#<branch>:<subpath>
      # Dockerfile lives at accelerators/voice-channel/server/Dockerfile with context rooted there.
      az acr build \
        --registry "$ACR_NAME" \
        --image voice-channel/server:initial \
        --file Dockerfile \
        --source "${GIT_URL}#${GIT_BRANCH}:accelerators/voice-channel/server"

      echo "=== Updating Container App to the built image ==="
      az containerapp update \
        --resource-group "$RG" \
        --name "$APP_NAME" \
        --image "$IMAGE_TAG"
    '''
  }
}

// --------------------------- Deployment script: provision MCS agent --------

resource mcsDeployScript 'Microsoft.Resources/deploymentScripts@2023-08-01' = if (provisionMcs) {
  name: '${environmentName}-provision-mcs'
  location: location
  kind: 'AzurePowerShell'
  dependsOn: [ kvSecretsOfficerForIdentity ]
  identity: {
    type: 'UserAssigned'
    userAssignedIdentities: { '${identity.id}': {} }
  }
  properties: {
    azPowerShellVersion: '11.5'
    retentionInterval: 'PT1H'
    timeout: 'PT30M'
    cleanupPreference: 'OnSuccess'
    environmentVariables: [
      { name: 'PP_ENV_URL',  value: powerPlatformEnvironmentUrl }
      { name: 'SP_TENANT',   value: entraTenantId }
      { name: 'SP_CLIENT',   value: powerPlatformSpnClientId }
      { name: 'SP_SECRET',   secureValue: powerPlatformSpnClientSecret }
      { name: 'AGENT_NAME',  value: mcsAgentName }
      { name: 'SCHEMA_NAME', value: 'microsoft_learn_assistant' }
      { name: 'KV_NAME',     value: keyVault.name }
      { name: 'SECRET_NAME', value: directLineSecretName }
    ]
    scriptContent: '''
      $ErrorActionPreference = 'Stop'

      Write-Host "=== Installing pac CLI ===" -ForegroundColor Cyan
      try { dotnet tool install --global Microsoft.PowerApps.CLI.Tool | Out-Null } catch { }
      $env:PATH = "$env:PATH" + [IO.Path]::PathSeparator + "$HOME/.dotnet/tools"

      Write-Host "`n=== pac auth via SPN ===" -ForegroundColor Cyan
      pac auth create `
        --name 'oneclick' `
        --tenant "$env:SP_TENANT" `
        --applicationId "$env:SP_CLIENT" `
        --clientSecret "$env:SP_SECRET" `
        --environment "$env:PP_ENV_URL"

      $agentYaml = @"
schemaVersion: "1.0"
kind: DeclarativeAgent
name: "$env:AGENT_NAME"
description: Answers Microsoft product and IT-pro questions using Microsoft Learn.
instructions: |
  You are the Microsoft Learn Assistant. Every answer must be grounded in
  results from the Microsoft Learn MCP tool. Call microsoft_docs_search first,
  optionally follow up with microsoft_docs_fetch. Cite Learn article titles
  inline. Keep answers under 6 sentences.
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
    enabled: false
"@
      Set-Content -Path ./agent.yaml -Value $agentYaml -Encoding UTF8

      Write-Host "`n=== Creating agent ===" -ForegroundColor Cyan
      $created = $false
      try {
        pac copilot create --file ./agent.yaml --name "$env:AGENT_NAME" --schema-name "$env:SCHEMA_NAME"
        if ($LASTEXITCODE -eq 0) { $created = $true }
      } catch { }
      if (-not $created) {
        pac copilot new --name "$env:AGENT_NAME" --schema-name "$env:SCHEMA_NAME"
        pac copilot update --schema-name "$env:SCHEMA_NAME" --file ./agent.yaml
      }

      Write-Host "`n=== Publishing ===" -ForegroundColor Cyan
      pac copilot publish --schema-name "$env:SCHEMA_NAME"

      Write-Host "`n=== Enabling Direct Line ===" -ForegroundColor Cyan
      pac copilot channel enable --schema-name "$env:SCHEMA_NAME" --channel directLine
      $secretJson = pac copilot channel show-secret --schema-name "$env:SCHEMA_NAME" --channel directLine --output json
      $secret = ($secretJson | ConvertFrom-Json).secret
      if (-not $secret) { throw 'Failed to capture Direct Line secret.' }

      Write-Host "`n=== Writing secret to Key Vault ===" -ForegroundColor Cyan
      az login --identity | Out-Null
      az keyvault secret set `
        --vault-name "$env:KV_NAME" `
        --name "$env:SECRET_NAME" `
        --value "$secret" | Out-Null

      $DeploymentScriptOutputs = @{
        agentName  = $env:AGENT_NAME
        schemaName = $env:SCHEMA_NAME
      }
      Write-Host "`n=== Done ===" -ForegroundColor Green
    '''
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
output DIRECTLINE_SECRET_NAME            string = directLineSecretName
output MANAGED_IDENTITY_CLIENT_ID        string = identity.properties.clientId
output MCS_PROVISIONED                   bool   = provisionMcs
