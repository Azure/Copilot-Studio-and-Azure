// =============================================================================
// Voice Channel Accelerator — ONE-CLICK unified deployment
// =============================================================================
// Deploys:
//   1. Microsoft Foundry (AIServices) — hosts the IT Assistant agent
//   2. Key Vault — holds the Copilot Studio Direct Line secret
//   3. Log Analytics + Application Insights
//   4. *(optional, if PP SPN is supplied)* — a deploymentScript that:
//        a. uses pac CLI to create the "Microsoft Learn Assistant" Copilot
//           Studio agent, enable Direct Line, capture the secret
//        b. writes the secret to Key Vault
//
// After the deployment completes, run (still one command each):
//   - foundry-agent/create-foundry-agent.ps1  (reads secret from Key Vault,
//     creates the Foundry assistant, attaches the Direct Line OpenAPI tool)
//   - foundry-agent/publish-to-teams.ps1      (publish-copilot flow → Teams zip)
//
// No App Service, no bridge, no web app. Everything user-facing runs in
// Teams / Microsoft 365 Copilot via the Azure Bot Service that publish-copilot
// auto-provisions.
// =============================================================================

// --------------------------- Azure params -----------------------------------

@description('Base name for all Azure resources (lowercase, 3-18 chars, no spaces).')
@minLength(3)
@maxLength(18)
param baseName string

@description('Azure region. Any region where Microsoft Foundry + Azure Bot Service are available.')
param location string = resourceGroup().location

@description('Foundry text model used by the IT Assistant.')
@allowed([
  'gpt-4.1'
  'gpt-4.1-mini'
  'gpt-4o'
  'gpt-4o-mini'
  'gpt-5'
  'gpt-5-mini'
])
param foundryModel string = 'gpt-4.1'

@description('Copilot Studio agent display name — must match the MCS agent created by the deploymentScript.')
param mcsAgentName string = 'Microsoft Learn Assistant'

// --------------------------- Copilot Studio params --------------------------

@description('URL of the target Power Platform environment (e.g. https://contoso.crm.dynamics.com). Leave empty to skip MCS provisioning and create the agent manually with copilot-studio-agent/create-agent.ps1.')
param powerPlatformEnvironmentUrl string = ''

@description('Entra tenant ID. Defaults to the current Azure subscription tenant.')
param entraTenantId string = tenant().tenantId

@description('Entra SPN client ID registered as an Application User (Dataverse System Admin) in the PP env. Leave empty to skip.')
param powerPlatformSpnClientId string = ''

@description('Secret for the SPN. Leave empty to skip.')
@secure()
param powerPlatformSpnClientSecret string = ''

@description('Object ID of the user / group that needs read access to the Key Vault secret (usually the deploying user). Defaults to the deploying principal.')
param secretReaderObjectId string = ''

// --------------------------- Derived ---------------------------------------

var foundryName         = '${baseName}-foundry'
var foundryCustomDomain = toLower('${baseName}-foundry')
var keyVaultName        = toLower('${baseName}-kv')
var appInsightsName     = '${baseName}-insights'
var logAnalyticsName    = '${baseName}-logs'

var provisionMcs = !empty(powerPlatformEnvironmentUrl) && !empty(powerPlatformSpnClientId) && !empty(powerPlatformSpnClientSecret)

var keyVaultSecretsOfficerRoleId = 'b86a8fe4-44ce-4948-aee5-eccb2c155cd7' // Key Vault Secrets Officer
var keyVaultSecretsUserRoleId    = '4633458b-17de-408a-b874-0445c86b69e6' // Key Vault Secrets User

var directLineSecretName = 'mcs-directline-secret'

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

// --------------------------- Key Vault -------------------------------------

resource keyVault 'Microsoft.KeyVault/vaults@2024-04-01-preview' = {
  name: keyVaultName
  location: location
  properties: {
    tenantId: subscription().tenantId
    sku: { family: 'A', name: 'standard' }
    enableRbacAuthorization: true
    softDeleteRetentionInDays: 7
    enablePurgeProtection: false
    publicNetworkAccess: 'Enabled'
  }
}

// Grant the deploying user read access to the secret, so foundry-agent scripts
// can fetch it from their workstation.
resource secretReaderAssignment 'Microsoft.Authorization/roleAssignments@2022-04-01' = if (!empty(secretReaderObjectId)) {
  name: guid(keyVault.id, keyVaultSecretsUserRoleId, secretReaderObjectId)
  scope: keyVault
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', keyVaultSecretsUserRoleId)
    principalId: secretReaderObjectId
    principalType: 'User'
  }
}

// --------------------------- Deployment-script identity ---------------------
// Only needed when we run the MCS provisioning script.

resource deployScriptIdentity 'Microsoft.ManagedIdentity/userAssignedIdentities@2023-01-31' = if (provisionMcs) {
  name: '${baseName}-deploy-mi'
  location: location
}

resource deployScriptKeyVaultRbac 'Microsoft.Authorization/roleAssignments@2022-04-01' = if (provisionMcs) {
  name: guid(keyVault.id, keyVaultSecretsOfficerRoleId, '${baseName}-deploy-mi')
  scope: keyVault
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', keyVaultSecretsOfficerRoleId)
    principalId: deployScriptIdentity.properties.principalId
    principalType: 'ServicePrincipal'
  }
}

// --------------------------- Copilot Studio provisioning -------------------

resource mcsDeployScript 'Microsoft.Resources/deploymentScripts@2023-08-01' = if (provisionMcs) {
  name: '${baseName}-deploy-mcs'
  location: location
  kind: 'AzurePowerShell'
  dependsOn: [ deployScriptKeyVaultRbac ]
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
      { name: 'PP_ENV_URL',       value: powerPlatformEnvironmentUrl }
      { name: 'SP_TENANT',        value: entraTenantId }
      { name: 'SP_CLIENT_ID',     value: powerPlatformSpnClientId }
      { name: 'SP_SECRET',        secureValue: powerPlatformSpnClientSecret }
      { name: 'AGENT_NAME',       value: mcsAgentName }
      { name: 'SCHEMA_NAME',      value: 'microsoft_learn_assistant' }
      { name: 'KV_NAME',          value: keyVault.name }
      { name: 'SECRET_NAME',      value: directLineSecretName }
    ]
    scriptContent: '''
      $ErrorActionPreference = 'Stop'

      Write-Host "=== Installing pac CLI ===" -ForegroundColor Cyan
      try { dotnet tool install --global Microsoft.PowerApps.CLI.Tool | Out-Null } catch { }
      $env:PATH = "$env:PATH" + [IO.Path]::PathSeparator + "$HOME/.dotnet/tools"

      Write-Host "`n=== Authenticating pac with SPN ===" -ForegroundColor Cyan
      pac auth create `
        --name 'oneclick' `
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
        secretUri  = "https://$env:KV_NAME.vault.azure.net/secrets/$env:SECRET_NAME"
      }

      Write-Host "`n=== Done ===" -ForegroundColor Green
    '''
  }
}

// --------------------------- Outputs ---------------------------------------

output foundryName       string = foundry.name
output foundryEndpoint   string = foundry.properties.endpoint
output foundryResourceId string = foundry.id
output keyVaultName      string = keyVault.name
output keyVaultUri       string = keyVault.properties.vaultUri
output directLineSecretName string = directLineSecretName
output mcsProvisioned    bool   = provisionMcs
output foundryModel      string = foundryModel
