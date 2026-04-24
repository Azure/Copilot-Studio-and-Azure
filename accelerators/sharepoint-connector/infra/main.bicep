// SharePoint → Azure AI Search Connector — Pattern A (unified multimodal).
//
// Deploys:
//   * Function App (Flex Consumption, Python 3.11) with system-assigned MI
//   * Storage Account (blob + queue + table services) with state/images containers
//   * App Insights + Log Analytics
//   * Optional Key Vault (Graph CLIENT_SECRET fallback, conditional)
//   * Optional Document Intelligence (conditional, for Layout-aware extraction)
//   * RBAC assignments for the MI
//
// Embeddings: Azure AI Vision multimodal 4.0 (Florence) via the Foundry /
// multi-service Azure AI Services resource — produces 1024d vectors for both
// text and images in the same space. No Azure OpenAI dependency.

@description('Base name for all resources (lowercase, no spaces)')
param baseName string

@description('Azure region for deployment')
param location string = resourceGroup().location

@description('Tenant ID for Entra ID / Graph API')
param tenantId string

@description('SharePoint site URL (e.g. https://company.sharepoint.com/sites/MySite)')
param sharePointSiteUrl string

@description('Azure AI Search endpoint')
param searchEndpoint string

@description('Azure AI Search resource ID (for RBAC scope)')
param searchResourceId string

@description('Search index name')
param searchIndexName string = 'sharepoint-index'

@description('Microsoft Foundry / Azure AI Services multi-service endpoint. Hosts Azure AI Vision multimodal embeddings (required) and optionally Document Intelligence.')
param foundryEndpoint string

@description('Foundry / Azure AI Services resource ID (for RBAC scope)')
param foundryResourceId string

@description('Azure AI Vision multimodal embeddings model version.')
param multimodalModelVersion string = '2023-04-15'

@description('CRON schedule for the indexer (default: every hour)')
param indexerSchedule string = '0 0 * * * *'

@description('Processing mode: full | since-date | since-last-run')
@allowed([
  'full'
  'since-date'
  'since-last-run'
])
param processingMode string = 'since-last-run'

@description('Absolute start date (ISO-8601 UTC). Only used when processingMode = since-date.')
param startDate string = ''

@description('SharePoint libraries to index (comma-separated, empty = all)')
param sharePointLibraries string = ''

@description('File extensions to index.')
param indexedExtensions string = '.pdf,.docx,.docm,.xlsx,.xlsm,.pptx,.pptm,.txt,.md,.csv,.json,.xml,.kml,.html,.htm,.rtf,.eml,.epub,.msg,.odt,.ods,.odp,.zip,.gz,.png,.jpg,.jpeg,.tiff,.bmp'

@description('Max file size in MB (files larger than this are skipped)')
param maxFileSizeMb string = '500'

@description('Function processing mode: queue (default, scales to >50 files) or inline (legacy single-function)')
@allowed([
  'queue'
  'inline'
])
param functionProcessingMode string = 'queue'

@description('Function instance memory in MB (Flex Consumption: 512/1024/2048/4096)')
@allowed([
  512
  1024
  2048
  4096
])
param instanceMemoryMB int = 4096

@description('Use CLIENT_SECRET fallback for Graph API (requires Key Vault). When false, uses managed identity only.')
param useClientSecret bool = false

@description('Client secret value. Only used when useClientSecret = true. Passed via secure CLI parameter.')
@secure()
param clientSecretValue string = ''

@description('Provision a new Document Intelligence resource for structured layout extraction. Optional — only PDF/DOCX/PPTX/XLSX benefit. Standalone image files go direct to Azure AI Vision multimodal.')
param provisionDocIntel bool = false

@description('Existing Document Intelligence endpoint (leave empty to skip; PDF/Office fall back to hand-written extractors).')
param docIntelEndpoint string = ''

@description('Existing Document Intelligence resource ID (for RBAC scope)')
param docIntelResourceId string = ''

@description('Blob container name for extracted image crops (citations).')
param imagesContainerName string = 'images'

@description('DESTRUCTIVE: drops and recreates the AI Search index on next run. Set once after a breaking schema change, then revert to false.')
param forceRecreateIndex bool = false

@description('Expected audience for tokens hitting the /api/search endpoint. Set to the API app registration client ID (or Application ID URI). When empty, the endpoint is effectively disabled.')
param apiAudience string = ''

@description('Always-allowed Entra object IDs. Comma-separated. Useful for tenant-wide share groups.')
param alwaysAllowedIds string = ''

@description('Enable image handling (requires foundryEndpoint with Azure AI Vision multimodal available). Default true.')
param extractImages bool = true

@description('Optional comma-separated folder paths (relative to each drive root) to scope the indexer to. Empty = whole library. Example: "Finance/Reports,HR/Policies".')
param sharePointRootPaths string = ''

@description('Per-file chunk vectorisation concurrency inside a worker. Bounded at the source by MULTIMODAL_MAX_IN_FLIGHT.')
param vectoriseConcurrency int = 8

@description('Hard ceiling on in-flight Azure AI Vision embedding requests per Function instance (protects the Vision endpoint from overload).')
param multimodalMaxInFlight int = 8

@description('Cadence (in indexer runs) at which a belt-and-braces full reconciliation scans for orphans. 0 = never.')
param reconcileEveryNRuns int = 24

@description('CRON schedule for the nightly index backup (default: 03:00 UTC daily).')
param backupSchedule string = '0 0 3 * * *'

@description('Number of dated backup folders to keep in the backup container.')
param backupRetentionDays int = 7

// Derived names
var functionAppName = '${baseName}-func'
var storageName = replace('${baseName}st', '-', '')
var appInsightsName = '${baseName}-insights'
var logAnalyticsName = '${baseName}-logs'
var keyVaultName = take(replace('${baseName}-kv-${uniqueString(resourceGroup().id)}', '--', '-'), 24)
var docIntelName = '${baseName}-docintel'
var deployContainerName = 'app-package'
var stateContainerName = 'state'
var effectiveImagesContainer = imagesContainerName
var backupContainerName = 'backup'
var indexerQueueName = 'sp-indexer-q'
var indexerPoisonQueueName = 'sp-indexer-q-poison'
var failedFilesTableName = 'failedFiles'
var runStateTableName = 'runState'
var watermarkTableName = 'watermark'

// Extract resource names from resource IDs
var searchServiceName = last(split(searchResourceId, '/'))
var foundryAccountName = last(split(foundryResourceId, '/'))
var effectiveDocIntelName = provisionDocIntel ? docIntelName : (empty(docIntelResourceId) ? '' : last(split(docIntelResourceId, '/')))
var effectiveDocIntelEndpoint = provisionDocIntel ? 'https://${docIntelName}.cognitiveservices.azure.com' : docIntelEndpoint

// Built-in role definition IDs
var searchDataContributorRoleId = '8ebe5a00-799e-43f5-93ac-243d3dce84a7'
var searchServiceContributorRoleId = '7ca78c08-252a-4471-8644-bb5ff32d4ba0'
var cognitiveServicesUserRoleId = 'a97b65f3-24c7-4388-baec-2e87135dc908'
var storageBlobDataOwnerRoleId = 'b7e6dc6d-f1e8-4753-8033-0f276bb0955b'
var storageAccountContributorRoleId = '17d1049b-9a84-46fb-8f53-869881c3d3ab'
var storageQueueDataContributorRoleId = '974c5e8b-45b9-4653-ba55-5f855dd0fb88'
var storageTableDataContributorRoleId = '0a9a7e1f-b9d0-4cc4-a60d-0319b160aaa3'
var keyVaultSecretsUserRoleId = '4633458b-17de-408a-b874-0445c86b69e6'

// Existing resources for RBAC scoping
resource searchService 'Microsoft.Search/searchServices@2024-06-01-preview' existing = {
  name: searchServiceName
}

resource foundryAccount 'Microsoft.CognitiveServices/accounts@2024-10-01' existing = {
  name: foundryAccountName
}

resource existingDocIntel 'Microsoft.CognitiveServices/accounts@2024-10-01' existing = if (!provisionDocIntel && !empty(docIntelResourceId)) {
  name: effectiveDocIntelName
}

// Storage Account
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
  name: effectiveImagesContainer
}

// Nightly index + state backup lands here (retention managed in Python).
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

// Log Analytics
resource logAnalytics 'Microsoft.OperationalInsights/workspaces@2023-09-01' = {
  name: logAnalyticsName
  location: location
  properties: {
    sku: { name: 'PerGB2018' }
    retentionInDays: 30
  }
}

// App Insights
resource appInsights 'Microsoft.Insights/components@2020-02-02' = {
  name: appInsightsName
  location: location
  kind: 'web'
  properties: {
    Application_Type: 'web'
    WorkspaceResourceId: logAnalytics.id
  }
}

// Key Vault (conditional)
resource keyVault 'Microsoft.KeyVault/vaults@2023-07-01' = if (useClientSecret) {
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

resource graphClientSecret 'Microsoft.KeyVault/vaults/secrets@2023-07-01' = if (useClientSecret) {
  parent: keyVault
  name: 'graph-client-secret'
  properties: {
    value: clientSecretValue
  }
}

// Document Intelligence (conditional)
resource docIntel 'Microsoft.CognitiveServices/accounts@2024-10-01' = if (provisionDocIntel) {
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

// Flex Consumption Plan
resource flexPlan 'Microsoft.Web/serverfarms@2024-04-01' = {
  name: '${baseName}-plan'
  location: location
  kind: 'functionapp'
  sku: { tier: 'FlexConsumption', name: 'FC1' }
  properties: { reserved: true }
}

// Function App
resource functionApp 'Microsoft.Web/sites@2024-04-01' = {
  name: functionAppName
  location: location
  kind: 'functionapp,linux'
  identity: { type: 'SystemAssigned' }
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
      appSettings: concat([
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

        // Processing mode
        { name: 'PROCESSING_MODE', value: processingMode }
        { name: 'START_DATE', value: startDate }
        { name: 'FUNCTION_PROCESSING_MODE', value: functionProcessingMode }

        // Large file handling
        { name: 'MAX_FILE_SIZE_MB', value: maxFileSizeMb }
        { name: 'MAX_CONCURRENCY', value: '4' }
        { name: 'CHUNK_SIZE', value: '2000' }
        { name: 'CHUNK_OVERLAP', value: '200' }

        // Per-file chunk-vectorisation concurrency + Vision rate-limit ceiling
        { name: 'VECTORISE_CONCURRENCY', value: string(vectoriseConcurrency) }
        { name: 'MULTIMODAL_MAX_IN_FLIGHT', value: string(multimodalMaxInFlight) }
        { name: 'RECONCILE_EVERY_N_RUNS', value: string(reconcileEveryNRuns) }

        // Index backup
        { name: 'BACKUP_SCHEDULE', value: backupSchedule }
        { name: 'BACKUP_CONTAINER', value: backupContainerName }
        { name: 'BACKUP_RETENTION_DAYS', value: string(backupRetentionDays) }

        // State store
        { name: 'STATE_CONTAINER', value: stateContainerName }
        { name: 'INDEXER_QUEUE_NAME', value: indexerQueueName }
        { name: 'FAILED_FILES_TABLE', value: failedFilesTableName }
        { name: 'RUN_STATE_TABLE', value: runStateTableName }
        { name: 'WATERMARK_TABLE', value: watermarkTableName }

        // Pattern A — unified multimodal embeddings
        { name: 'MULTIMODAL_ENDPOINT', value: foundryEndpoint }
        { name: 'MULTIMODAL_MODEL_VERSION', value: multimodalModelVersion }
        { name: 'IMAGES_CONTAINER', value: effectiveImagesContainer }
        { name: 'EXTRACT_IMAGES', value: extractImages ? 'true' : 'false' }

        // Optional Document Intelligence (layout-aware extraction)
        { name: 'DOCINTEL_ENDPOINT', value: effectiveDocIntelEndpoint }

        // Destructive index-recreate flag (unset after one run)
        { name: 'FORCE_RECREATE_INDEX', value: forceRecreateIndex ? 'true' : 'false' }

        // Query-time security trimming (/api/search, called from OnKnowledgeRequested topic)
        { name: 'API_AUDIENCE', value: apiAudience }
        { name: 'ALWAYS_ALLOWED_IDS', value: alwaysAllowedIds }
      ], useClientSecret ? [
        { name: 'CLIENT_SECRET', value: '@Microsoft.KeyVault(SecretUri=${useClientSecret ? keyVault!.properties.vaultUri : ''}secrets/graph-client-secret/)' }
      ] : [])
    }
  }
}

// RBAC — Azure AI Search (Index Data Contributor + Service Contributor)
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

// RBAC — Foundry / Azure AI Services (Cognitive Services User for vision multimodal embeddings)
resource foundryAssignment 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(foundryAccount.id, cognitiveServicesUserRoleId, functionApp.id)
  scope: foundryAccount
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', cognitiveServicesUserRoleId)
    principalId: functionApp.identity.principalId
    principalType: 'ServicePrincipal'
  }
}

// RBAC — Document Intelligence (conditional, new)
resource docIntelAssignmentNew 'Microsoft.Authorization/roleAssignments@2022-04-01' = if (provisionDocIntel) {
  name: guid(docIntel.id, cognitiveServicesUserRoleId, functionApp.id)
  scope: docIntel
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', cognitiveServicesUserRoleId)
    principalId: functionApp.identity.principalId
    principalType: 'ServicePrincipal'
  }
}

// RBAC — Document Intelligence (conditional, existing same-RG)
resource docIntelAssignmentExisting 'Microsoft.Authorization/roleAssignments@2022-04-01' = if (!provisionDocIntel && !empty(docIntelResourceId) && contains(docIntelResourceId, resourceGroup().name)) {
  name: guid(docIntelResourceId, cognitiveServicesUserRoleId, functionApp.id)
  scope: existingDocIntel
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', cognitiveServicesUserRoleId)
    principalId: functionApp.identity.principalId
    principalType: 'ServicePrincipal'
  }
}

// RBAC — Storage (blob / queue / table)
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

// RBAC — Key Vault (conditional)
resource keyVaultSecretsUserAssignment 'Microsoft.Authorization/roleAssignments@2022-04-01' = if (useClientSecret) {
  name: guid(keyVault.id, keyVaultSecretsUserRoleId, functionApp.id)
  scope: keyVault
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', keyVaultSecretsUserRoleId)
    principalId: functionApp.identity.principalId
    principalType: 'ServicePrincipal'
  }
}

output functionAppName string = functionApp.name
output functionAppPrincipalId string = functionApp.identity.principalId
output storageAccountName string = storageAccount.name
output keyVaultName string = useClientSecret ? keyVault!.name : ''
output docIntelEndpoint string = effectiveDocIntelEndpoint
output multimodalEndpoint string = foundryEndpoint
