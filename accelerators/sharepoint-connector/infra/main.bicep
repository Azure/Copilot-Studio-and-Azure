// SharePoint → Azure AI Search Connector — Pattern A (unified multimodal).
//
// End-to-end deployment. Everything is created by this template:
//   * Storage Account (blob + queue + table services) with the containers /
//     queues / tables the connector uses
//   * Log Analytics + Application Insights
//   * Azure AI Search (Basic tier — vector search requires Basic or above)
//   * Microsoft Foundry / Azure AI Services multi-service account (hosts
//     Azure AI Vision multimodal embeddings)
//   * Document Intelligence account (Layout model for PDF/Office extraction)
//   * Key Vault (for CLIENT_SECRET fallback if the admin adds one later)
//   * Flex Consumption plan + Function App with system-assigned managed identity
//   * Every RBAC role assignment on the MI
//
// Required parameters kept to the minimum that's genuinely user-specific.
// All operational tuning knobs (schedules, concurrency, retention, extensions,
// processing modes) are set to sensible defaults in this file and can be
// tweaked post-deployment via Function App settings if needed.

// ============================================================================
// Required parameters — user-supplied
// ============================================================================

@description('Base name for every resource. Lowercase letters / digits / hyphens. Used as a prefix; a short uniqueness hash is appended where Azure requires globally-unique names.')
@minLength(3)
@maxLength(16)
param baseName string

@description('Azure region. Pick one that supports Azure AI Vision multimodal 4.0 (see Microsoft Learn for the current list).')
param location string = resourceGroup().location

@description('Microsoft Entra tenant ID (Graph API authority for the SharePoint site).')
param tenantId string

@description('Full SharePoint site URL the connector will monitor, e.g. https://contoso.sharepoint.com/sites/YourSite')
param sharePointSiteUrl string

@description('Application (client) ID of the Entra app registration that represents the /api/search endpoint. Copilot Studio requests tokens for this audience via the OnKnowledgeRequested topic. Use the client ID GUID OR the App ID URI (e.g. api://<clientId>).')
param apiAudience string

@description('Public URL of the CI-built function-app zip. The deployment seeds it into the Function App storage container so no post-deploy `func publish` is needed. Override to point at a fork release URL if the code has been customised.')
param packageReleaseUrl string = 'https://github.com/Azure/Copilot-Studio-and-Azure/releases/download/sharepoint-connector-latest/sharepoint-connector.zip'

// ============================================================================
// Operational defaults — baked in; override post-deployment via app settings
// ============================================================================

var searchIndexName = 'sharepoint-index'
var indexerSchedule = '0 0 * * * *'            // every hour
var backupSchedule = '0 0 3 * * *'             // 03:00 UTC daily
var backupRetentionDays = 7

var processingMode = 'since-last-run'
var startDate = ''
var sharePointLibraries = ''                   // empty = all libraries
var sharePointRootPaths = ''                   // empty = whole library

var indexedExtensions = '.pdf,.docx,.docm,.xlsx,.xlsm,.pptx,.pptm,.txt,.md,.csv,.json,.xml,.kml,.html,.htm,.rtf,.eml,.epub,.msg,.odt,.ods,.odp,.zip,.gz,.png,.jpg,.jpeg,.tiff,.bmp'
var maxFileSizeMb = 500
var vectoriseConcurrency = 8
var multimodalMaxInFlight = 8
var reconcileEveryNRuns = 24

var functionProcessingMode = 'queue'
var instanceMemoryMB = 4096
var multimodalModelVersion = '2023-04-15'

var imagesContainerName = 'images'
var extractImages = true
var forceRecreateIndex = false
var alwaysAllowedIds = ''

var searchSku = 'basic'                        // vector search requires Basic+

// ============================================================================
// Derived names
// ============================================================================

var nameSuffix = take(uniqueString(resourceGroup().id, baseName), 6)

var functionAppName = '${baseName}-func-${nameSuffix}'
// baseName is @minLength 3 / @maxLength 16; stripping hyphens plus the literal
// 'st' (2 chars) + nameSuffix (6 chars) yields at most 24 chars and at least
// 8 (all-hyphen degenerate case) — both within Azure's storage-name bounds.
var storageName = toLower('${replace(baseName, '-', '')}st${nameSuffix}')
var appInsightsName = '${baseName}-insights'
var logAnalyticsName = '${baseName}-logs'
var keyVaultName = take('${baseName}-kv-${nameSuffix}', 24)
var searchServiceName = take(toLower('${baseName}-search-${nameSuffix}'), 60)
var foundryAccountName = take('${baseName}-foundry-${nameSuffix}', 60)
var docIntelName = take('${baseName}-docintel-${nameSuffix}', 60)

var deployContainerName = 'app-package'
var stateContainerName = 'state'
var backupContainerName = 'backup'
var indexerQueueName = 'sp-indexer-q'
var indexerPoisonQueueName = 'sp-indexer-q-poison'
var failedFilesTableName = 'failedFiles'
var runStateTableName = 'runState'
var watermarkTableName = 'watermark'

var foundryEndpoint = 'https://${foundryAccountName}.cognitiveservices.azure.com'
var docIntelEndpoint = 'https://${docIntelName}.cognitiveservices.azure.com'
var searchEndpoint = 'https://${searchServiceName}.search.windows.net'

// ============================================================================
// Built-in role definition IDs
// ============================================================================

var searchDataContributorRoleId = '8ebe5a00-799e-43f5-93ac-243d3dce84a7'
var searchServiceContributorRoleId = '7ca78c08-252a-4471-8644-bb5ff32d4ba0'
var cognitiveServicesUserRoleId = 'a97b65f3-24c7-4388-baec-2e87135dc908'
var storageBlobDataOwnerRoleId = 'b7e6dc6d-f1e8-4753-8033-0f276bb0955b'
var storageBlobDataContributorRoleId = 'ba92f5b4-2d11-453d-a403-e96b0029c9fe'
var storageAccountContributorRoleId = '17d1049b-9a84-46fb-8f53-869881c3d3ab'
var storageQueueDataContributorRoleId = '974c5e8b-45b9-4653-ba55-5f855dd0fb88'
var storageTableDataContributorRoleId = '0a9a7e1f-b9d0-4cc4-a60d-0319b160aaa3'
var keyVaultSecretsUserRoleId = '4633458b-17de-408a-b874-0445c86b69e6'

// ============================================================================
// Storage
// ============================================================================

resource storageAccount 'Microsoft.Storage/storageAccounts@2023-05-01' = {
  name: storageName
  location: location
  sku: { name: 'Standard_LRS' }
  kind: 'StorageV2'
  properties: {
    minimumTlsVersion: 'TLS1_2'
    supportsHttpsTrafficOnly: true
    allowSharedKeyAccess: false
    allowBlobPublicAccess: false
  }
}

resource blobService 'Microsoft.Storage/storageAccounts/blobServices@2023-05-01' = {
  parent: storageAccount
  name: 'default'
}

resource deployContainer 'Microsoft.Storage/storageAccounts/blobServices/containers@2023-05-01' = {
  parent: blobService
  name: deployContainerName
}

resource stateContainer 'Microsoft.Storage/storageAccounts/blobServices/containers@2023-05-01' = {
  parent: blobService
  name: stateContainerName
}

resource imagesContainer 'Microsoft.Storage/storageAccounts/blobServices/containers@2023-05-01' = {
  parent: blobService
  name: imagesContainerName
}

resource backupContainer 'Microsoft.Storage/storageAccounts/blobServices/containers@2023-05-01' = {
  parent: blobService
  name: backupContainerName
}

resource queueService 'Microsoft.Storage/storageAccounts/queueServices@2023-05-01' = {
  parent: storageAccount
  name: 'default'
}

resource indexerQueue 'Microsoft.Storage/storageAccounts/queueServices/queues@2023-05-01' = {
  parent: queueService
  name: indexerQueueName
}

resource indexerPoisonQueue 'Microsoft.Storage/storageAccounts/queueServices/queues@2023-05-01' = {
  parent: queueService
  name: indexerPoisonQueueName
}

resource tableService 'Microsoft.Storage/storageAccounts/tableServices@2023-05-01' = {
  parent: storageAccount
  name: 'default'
}

resource failedFilesTable 'Microsoft.Storage/storageAccounts/tableServices/tables@2023-05-01' = {
  parent: tableService
  name: failedFilesTableName
}

resource runStateTable 'Microsoft.Storage/storageAccounts/tableServices/tables@2023-05-01' = {
  parent: tableService
  name: runStateTableName
}

resource watermarkTable 'Microsoft.Storage/storageAccounts/tableServices/tables@2023-05-01' = {
  parent: tableService
  name: watermarkTableName
}

// ============================================================================
// Observability
// ============================================================================

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

// ============================================================================
// Azure AI Search (Basic tier — required for vector search)
// ============================================================================

resource searchService 'Microsoft.Search/searchServices@2024-06-01-preview' = {
  name: searchServiceName
  location: location
  sku: { name: searchSku }
  properties: {
    replicaCount: 1
    partitionCount: 1
    hostingMode: 'default'
    publicNetworkAccess: 'enabled'
    semanticSearch: 'standard'
  }
}

// ============================================================================
// Foundry / Azure AI Services (multi-service) — hosts Vision multimodal
// ============================================================================

resource foundryAccount 'Microsoft.CognitiveServices/accounts@2024-10-01' = {
  name: foundryAccountName
  location: location
  kind: 'AIServices'
  sku: { name: 'S0' }
  properties: {
    customSubDomainName: foundryAccountName
    publicNetworkAccess: 'Enabled'
  }
  identity: { type: 'SystemAssigned' }
}

// ============================================================================
// Document Intelligence — Layout model for PDF/Office extraction (mandatory)
// ============================================================================

resource docIntel 'Microsoft.CognitiveServices/accounts@2024-10-01' = {
  name: docIntelName
  location: location
  kind: 'FormRecognizer'
  sku: { name: 'S0' }
  properties: {
    customSubDomainName: docIntelName
    publicNetworkAccess: 'Enabled'
  }
  identity: { type: 'SystemAssigned' }
}

// ============================================================================
// Key Vault (mandatory — empty by default; admins can add secrets later)
// ============================================================================

resource keyVault 'Microsoft.KeyVault/vaults@2023-07-01' = {
  name: keyVaultName
  location: location
  properties: {
    tenantId: subscription().tenantId
    sku: { family: 'A', name: 'standard' }
    enableRbacAuthorization: true
    enableSoftDelete: true
    softDeleteRetentionInDays: 7
    publicNetworkAccess: 'Enabled'
  }
}

// ============================================================================
// One-shot code seeding — user-assigned MI + deploymentScript that downloads
// the CI-built package from GitHub Releases and writes it to the function's
// deploy container. No post-deploy `func publish` needed.
// ============================================================================

resource deployerIdentity 'Microsoft.ManagedIdentity/userAssignedIdentities@2023-01-31' = {
  name: '${baseName}-deployer-${nameSuffix}'
  location: location
}

resource deployerStorageRole 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(storageAccount.id, storageBlobDataContributorRoleId, deployerIdentity.id)
  scope: storageAccount
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', storageBlobDataContributorRoleId)
    principalId: deployerIdentity.properties.principalId
    principalType: 'ServicePrincipal'
  }
}

resource publishCode 'Microsoft.Resources/deploymentScripts@2023-08-01' = {
  name: '${baseName}-publish-code'
  location: location
  kind: 'AzureCLI'
  identity: {
    type: 'UserAssigned'
    userAssignedIdentities: {
      '${deployerIdentity.id}': {}
    }
  }
  properties: {
    azCliVersion: '2.65.0'
    timeout: 'PT10M'
    retentionInterval: 'PT1H'
    cleanupPreference: 'OnSuccess'
    environmentVariables: [
      { name: 'STORAGE_ACCOUNT', value: storageAccount.name }
      { name: 'CONTAINER', value: deployContainerName }
      { name: 'PACKAGE_URL', value: packageReleaseUrl }
      { name: 'PACKAGE_BLOB', value: 'function-package.zip' }
    ]
    scriptContent: '''
      set -eu
      TEMP=$(mktemp -d)
      cd "$TEMP"
      echo "Downloading $PACKAGE_URL"
      curl -sSL --fail -o package.zip "$PACKAGE_URL"
      echo "Uploading to $STORAGE_ACCOUNT/$CONTAINER/$PACKAGE_BLOB"
      az storage blob upload \
        --account-name "$STORAGE_ACCOUNT" \
        --container-name "$CONTAINER" \
        --name "$PACKAGE_BLOB" \
        --file package.zip \
        --auth-mode login \
        --overwrite
      echo "Upload complete."
    '''
  }
  dependsOn: [
    deployContainer
    deployerStorageRole
  ]
}

// ============================================================================
// Flex Consumption plan + Function App
// ============================================================================

resource flexPlan 'Microsoft.Web/serverfarms@2024-04-01' = {
  name: '${baseName}-plan'
  location: location
  kind: 'functionapp'
  sku: { tier: 'FlexConsumption', name: 'FC1' }
  properties: { reserved: true }
}

resource functionApp 'Microsoft.Web/sites@2024-04-01' = {
  name: functionAppName
  location: location
  kind: 'functionapp,linux'
  identity: { type: 'SystemAssigned' }
  dependsOn: [
    // Ensure the code package is in the container before the Function App
    // tries to start; otherwise the first-startup pull would race.
    publishCode
  ]
  properties: {
    serverFarmId: flexPlan.id
    httpsOnly: true
    functionAppConfig: {
      deployment: {
        storage: {
          type: 'blobContainer'
          value: '${storageAccount.properties.primaryEndpoints.blob}${deployContainerName}'
          authentication: { type: 'SystemAssignedIdentity' }
        }
      }
      scaleAndConcurrency: {
        maximumInstanceCount: 40
        instanceMemoryMB: instanceMemoryMB
      }
      runtime: { name: 'python', version: '3.11' }
    }
    siteConfig: {
      appSettings: [
        { name: 'AzureWebJobsStorage__accountName', value: storageAccount.name }
        { name: 'AzureWebJobsStorage__credential', value: 'managedidentity' }
        { name: 'FUNCTIONS_EXTENSION_VERSION', value: '~4' }
        { name: 'APPLICATIONINSIGHTS_CONNECTION_STRING', value: appInsights.properties.ConnectionString }

        // Connector config
        { name: 'TENANT_ID', value: tenantId }
        { name: 'SHAREPOINT_SITE_URL', value: sharePointSiteUrl }
        { name: 'SHAREPOINT_LIBRARIES', value: sharePointLibraries }
        { name: 'SHAREPOINT_ROOT_PATHS', value: sharePointRootPaths }
        { name: 'SEARCH_ENDPOINT', value: searchEndpoint }
        { name: 'SEARCH_INDEX_NAME', value: searchIndexName }
        { name: 'INDEXED_EXTENSIONS', value: indexedExtensions }
        { name: 'INDEXER_SCHEDULE', value: indexerSchedule }

        // Processing
        { name: 'PROCESSING_MODE', value: processingMode }
        { name: 'START_DATE', value: startDate }
        { name: 'FUNCTION_PROCESSING_MODE', value: functionProcessingMode }

        // Large file handling + concurrency
        { name: 'MAX_FILE_SIZE_MB', value: string(maxFileSizeMb) }
        { name: 'MAX_CONCURRENCY', value: '4' }
        { name: 'CHUNK_SIZE', value: '2000' }
        { name: 'CHUNK_OVERLAP', value: '200' }
        { name: 'VECTORISE_CONCURRENCY', value: string(vectoriseConcurrency) }
        { name: 'MULTIMODAL_MAX_IN_FLIGHT', value: string(multimodalMaxInFlight) }
        { name: 'RECONCILE_EVERY_N_RUNS', value: string(reconcileEveryNRuns) }

        // State store (Blob / Queue / Table)
        { name: 'STATE_CONTAINER', value: stateContainerName }
        { name: 'INDEXER_QUEUE_NAME', value: indexerQueueName }
        { name: 'FAILED_FILES_TABLE', value: failedFilesTableName }
        { name: 'RUN_STATE_TABLE', value: runStateTableName }
        { name: 'WATERMARK_TABLE', value: watermarkTableName }

        // Backup
        { name: 'BACKUP_SCHEDULE', value: backupSchedule }
        { name: 'BACKUP_CONTAINER', value: backupContainerName }
        { name: 'BACKUP_RETENTION_DAYS', value: string(backupRetentionDays) }

        // Multimodal embeddings + Document Intelligence (both always created)
        { name: 'MULTIMODAL_ENDPOINT', value: foundryEndpoint }
        { name: 'MULTIMODAL_MODEL_VERSION', value: multimodalModelVersion }
        { name: 'DOCINTEL_ENDPOINT', value: docIntelEndpoint }
        { name: 'IMAGES_CONTAINER', value: imagesContainerName }
        { name: 'EXTRACT_IMAGES', value: extractImages ? 'true' : 'false' }

        // Destructive index-recreate flag (unset after one run)
        { name: 'FORCE_RECREATE_INDEX', value: forceRecreateIndex ? 'true' : 'false' }

        // Query-time security trimming (/api/search, called from OnKnowledgeRequested topic)
        { name: 'API_AUDIENCE', value: apiAudience }
        { name: 'ALWAYS_ALLOWED_IDS', value: alwaysAllowedIds }

        // Reference to the provisioned Key Vault — admins can add CLIENT_SECRET here
        // later via `@Microsoft.KeyVault(SecretUri=...)` app setting, without redeploy.
        { name: 'KEY_VAULT_URI', value: keyVault.properties.vaultUri }
      ]
    }
  }
}

// ============================================================================
// RBAC assignments on the Function App's managed identity
// ============================================================================

// Azure AI Search
resource searchDataContributorAssignment 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(searchService.id, searchDataContributorRoleId, functionApp.id)
  scope: searchService
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', searchDataContributorRoleId)
    principalId: functionApp.identity.principalId
    principalType: 'ServicePrincipal'
  }
}

resource searchServiceContributorAssignment 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(searchService.id, searchServiceContributorRoleId, functionApp.id)
  scope: searchService
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', searchServiceContributorRoleId)
    principalId: functionApp.identity.principalId
    principalType: 'ServicePrincipal'
  }
}

// Foundry / AI Services (Vision multimodal)
resource foundryAssignment 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(foundryAccount.id, cognitiveServicesUserRoleId, functionApp.id)
  scope: foundryAccount
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', cognitiveServicesUserRoleId)
    principalId: functionApp.identity.principalId
    principalType: 'ServicePrincipal'
  }
}

// Document Intelligence
resource docIntelAssignment 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(docIntel.id, cognitiveServicesUserRoleId, functionApp.id)
  scope: docIntel
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', cognitiveServicesUserRoleId)
    principalId: functionApp.identity.principalId
    principalType: 'ServicePrincipal'
  }
}

// Storage (blob / queue / table / account)
resource storageBlobDataOwnerAssignment 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(storageAccount.id, storageBlobDataOwnerRoleId, functionApp.id)
  scope: storageAccount
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', storageBlobDataOwnerRoleId)
    principalId: functionApp.identity.principalId
    principalType: 'ServicePrincipal'
  }
}

resource storageAccountContributorAssignment 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(storageAccount.id, storageAccountContributorRoleId, functionApp.id)
  scope: storageAccount
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', storageAccountContributorRoleId)
    principalId: functionApp.identity.principalId
    principalType: 'ServicePrincipal'
  }
}

resource storageQueueDataContributorAssignment 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(storageAccount.id, storageQueueDataContributorRoleId, functionApp.id)
  scope: storageAccount
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', storageQueueDataContributorRoleId)
    principalId: functionApp.identity.principalId
    principalType: 'ServicePrincipal'
  }
}

resource storageTableDataContributorAssignment 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(storageAccount.id, storageTableDataContributorRoleId, functionApp.id)
  scope: storageAccount
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', storageTableDataContributorRoleId)
    principalId: functionApp.identity.principalId
    principalType: 'ServicePrincipal'
  }
}

// Key Vault
resource keyVaultSecretsUserAssignment 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(keyVault.id, keyVaultSecretsUserRoleId, functionApp.id)
  scope: keyVault
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', keyVaultSecretsUserRoleId)
    principalId: functionApp.identity.principalId
    principalType: 'ServicePrincipal'
  }
}

// ============================================================================
// Outputs
// ============================================================================

output functionAppName string = functionApp.name
output functionAppPrincipalId string = functionApp.identity.principalId
output storageAccountName string = storageAccount.name
output searchEndpoint string = searchEndpoint
output foundryEndpoint string = foundryEndpoint
output docIntelEndpoint string = docIntelEndpoint
output keyVaultName string = keyVault.name
