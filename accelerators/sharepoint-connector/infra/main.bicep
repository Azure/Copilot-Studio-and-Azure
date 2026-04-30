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
//   * Entra app registration for the /api/search endpoint — declared via the
//     Microsoft Graph Bicep extension, so no separate script runs
//   * Every RBAC role assignment on the MI
//
// Required parameters kept to the minimum that's genuinely user-specific.
// All operational tuning knobs (schedules, concurrency, retention, extensions,
// processing modes) are set to sensible defaults in this file and can be
// tweaked post-deployment via Function App settings if needed.
//
// Prerequisite permissions on the deployer:
//   * Azure RBAC: Owner or User Access Administrator on the target RG
//   * Microsoft Graph: Application.ReadWrite.OwnedBy (so the template can
//     declare the app registration). Built into Cloud Application
//     Administrator and Application Administrator directory roles.

extension microsoftGraphV1_0

// ============================================================================
// Required parameters — user-supplied
// ============================================================================

@description('Base name for every resource. Lowercase letters / digits / hyphens. Used as a prefix; a short uniqueness hash is appended where Azure requires globally-unique names.')
@minLength(3)
@maxLength(16)
param baseName string

@description('Azure region. Pick one that supports Azure AI Vision multimodal 4.0 (see Microsoft Learn for the current list).')
param location string = resourceGroup().location

@description('Full SharePoint site URL the connector will monitor, e.g. https://contoso.sharepoint.com/sites/YourSite')
param sharePointSiteUrl string

@description('Per-user security trimming. Default false: Copilot Studio queries Azure AI Search directly as a Knowledge Source — simplest deployment, no Entra app registration, no Power Platform connection. Set true to also create the /api/search Entra app registration that the OnKnowledgeRequested topic uses to enforce SharePoint ACLs at query time. Requires `Application Administrator` Entra role unless `apiAudience` is supplied. See the README section "Extending with Per-User Security Trimming" for the full opt-in walkthrough.')
param enableSecurityTrimming bool = false

@description('Optional escape hatch — only relevant when enableSecurityTrimming = true. When empty, the template creates the Entra app registration itself via the Microsoft Graph Bicep extension (deployer needs `Application Administrator`). When non-empty, the template skips creating the app and uses this client ID instead — useful when the deployer lacks Graph privileges and an admin has pre-created the app via infra/create-api-app-registration.ps1. Accepts a bare GUID or an `api://<clientId>` URI.')
param apiAudience string = ''

var shouldCreateAppRegistration = enableSecurityTrimming && empty(apiAudience)

// ============================================================================
// Operational defaults — baked in; override post-deployment via app settings
// ============================================================================

// CI-built function-app package. Not exposed as a parameter because 99 %
// of deployers should use the official release; fork-users can edit this
// line directly OR flip the app setting `WEBSITE_RUN_FROM_PACKAGE`-style
// override post-deploy.
var packageReleaseUrl = 'https://github.com/gokseloral/Copilot-Studio-and-Azure/releases/download/sharepoint-connector-latest/sharepoint-connector.zip'

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
var storageAccountContributorRoleId = '17d1049b-9a84-46fb-8f53-869881c3d3ab'
var storageQueueDataContributorRoleId = '974c5e8b-45b9-4653-ba55-5f855dd0fb88'
var storageTableDataContributorRoleId = '0a9a7e1f-b9d0-4cc4-a60d-0319b160aaa3'
var keyVaultSecretsUserRoleId = '4633458b-17de-408a-b874-0445c86b69e6'
var websiteContributorRoleId = 'de139f84-1756-47ae-9be6-808fbbe84772'

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
  // System-assigned MI so the registered aiServicesVision vectorizer can
  // authenticate to the Foundry endpoint at QUERY TIME (when Copilot Studio
  // or Search Explorer submits text and AI Search vectorizes it server-side).
  identity: {
    type: 'SystemAssigned'
  }
  properties: {
    replicaCount: 1
    partitionCount: 1
    hostingMode: 'default'
    publicNetworkAccess: 'enabled'
    semanticSearch: 'standard'
    // Accept BOTH AAD bearer tokens AND API keys. Without this, the data-plane
    // rejects AAD tokens with 403 even when the caller has the right RBAC role
    // — which silently breaks the worker's upload to the index.
    authOptions: {
      aadOrApiKey: {
        aadAuthFailureMode: 'http403'
      }
    }
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
// Entra app registration for /api/search (declarative via Microsoft Graph
// Bicep extension — no deploymentScript / helper PowerShell needed).
//
// Declares:
//   * `access_as_user` delegated scope (Copilot Studio's custom connector
//     OAuth2 reference requests this at runtime).
//   * `GroupMember.Read.All` Microsoft Graph application permission in
//     requiredResourceAccess — needed by /api/search to resolve transitive
//     group memberships at query time. Admin consent is a post-deploy
//     step because consenting to Graph app permissions requires Cloud
//     Application Administrator or Global Administrator.
//
// The deployer needs the Entra role `Application Administrator` (or
// equivalent — anything that includes `microsoft.directory/applications/
// createAsOwner` or Graph `Application.ReadWrite.OwnedBy`).
// ============================================================================

var apiAppUniqueName = 'sharepoint-connector-api-${nameSuffix}'
var accessAsUserScopeId = guid(resourceGroup().id, 'access_as_user')
var graphAppId = '00000003-0000-0000-c000-000000000000'
var groupMemberReadAllRoleId = '98830695-27a2-44f7-8c18-0c3ebc9698f6'

resource apiApp 'Microsoft.Graph/applications@v1.0' = if (shouldCreateAppRegistration) {
  uniqueName: apiAppUniqueName
  displayName: '${baseName} SharePoint Connector API'
  signInAudience: 'AzureADMyOrg'
  identifierUris: [
    'api://${apiAppUniqueName}'
  ]
  api: {
    oauth2PermissionScopes: [
      {
        id: accessAsUserScopeId
        value: 'access_as_user'
        type: 'User'
        isEnabled: true
        adminConsentDisplayName: 'Access SharePoint search on behalf of the signed-in user'
        adminConsentDescription: 'Allows Copilot Studio (or another delegated caller) to query the SharePoint Connector /api/search endpoint on behalf of the signed-in user. Per-user security trimming is enforced server-side.'
        userConsentDisplayName: 'Search SharePoint on your behalf'
        userConsentDescription: 'Allows the app to query the SharePoint Connector as you, returning only documents you have access to.'
      }
    ]
  }
  requiredResourceAccess: [
    {
      resourceAppId: graphAppId
      resourceAccess: [
        {
          id: groupMemberReadAllRoleId
          type: 'Role'
        }
      ]
    }
  ]
}

// Normalise `api://<clientId>` → `<clientId>` so either form works for apiAudience.
var suppliedClientId = startsWith(apiAudience, 'api://') ? substring(apiAudience, 6) : apiAudience
// Resolves to '' when security trimming is disabled — /api/search treats that as "auth disabled / endpoint unused".
var effectiveApiClientId = enableSecurityTrimming ? (shouldCreateAppRegistration ? apiApp!.appId : suppliedClientId) : ''

// ============================================================================
// One-shot code seeding — user-assigned MI + deploymentScript that downloads
// the CI-built package from GitHub Releases and writes it to the function's
// deploy container. No post-deploy `func publish` needed.
// ============================================================================

resource deployerIdentity 'Microsoft.ManagedIdentity/userAssignedIdentities@2023-01-31' = {
  name: '${baseName}-deployer-${nameSuffix}'
  location: location
}

resource deployerSearchRole 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(searchService.id, searchServiceContributorRoleId, deployerIdentity.id)
  scope: searchService
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', searchServiceContributorRoleId)
    principalId: deployerIdentity.properties.principalId
    principalType: 'ServicePrincipal'
  }
}

// Index schema lives in infra/sharepoint-index.json — single source of truth.
// Bicep substitutes the two runtime placeholders (foundry endpoint + model
// version) at compile time so the script doesn't need a multi-line env var
// (multi-line env vars caused empty-log container failures earlier).
var indexSchema = replace(
  replace(loadTextContent('sharepoint-index.json'), '__MULTIMODAL_ENDPOINT__', foundryEndpoint),
  '__MULTIMODAL_MODEL_VERSION__',
  multimodalModelVersion
)

var createIndexScriptTemplate = '''
set -eu
set -o pipefail
echo "=== createSearchIndex starting ==="
echo "SEARCH_NAME=$SEARCH_NAME RESOURCE_GROUP=$RESOURCE_GROUP INDEX_NAME=$INDEX_NAME"

cat > /tmp/index.json <<'BICEPJSONEOF'
__INDEX_SCHEMA_PLACEHOLDER__
BICEPJSONEOF
echo "Wrote /tmp/index.json ($(wc -c < /tmp/index.json) bytes)"
head -c 400 /tmp/index.json; echo

echo "=== Fetching admin key (with RBAC-propagation retries) ==="
ADMIN_KEY=""
for i in 1 2 3 4 5 6; do
  echo "Attempt $i: az search admin-key show --service-name $SEARCH_NAME"
  if K=$(az search admin-key show \
            --service-name "$SEARCH_NAME" \
            --resource-group "$RESOURCE_GROUP" \
            --query primaryKey -o tsv 2>&1); then
    if [ -n "$K" ] && [ "${#K}" -gt 20 ]; then
      ADMIN_KEY="$K"
      echo "Admin key retrieved on attempt $i (length=${#ADMIN_KEY})"
      break
    fi
  else
    echo "az returned non-zero: $K"
  fi
  echo "Sleeping 20s before retry"
  sleep 20
done
if [ -z "$ADMIN_KEY" ]; then
  echo "ERROR: failed to fetch admin key after retries" >&2
  exit 1
fi

echo "=== PUT $SEARCH_ENDPOINT/indexes/$INDEX_NAME ==="
HTTP=$(curl -sS -o /tmp/resp.json -w "%{http_code}" -X PUT \
       "$SEARCH_ENDPOINT/indexes/$INDEX_NAME?api-version=2024-11-01-preview" \
       -H "api-key: $ADMIN_KEY" \
       -H "Content-Type: application/json" \
       --data @/tmp/index.json)
echo "Returned HTTP $HTTP"
echo "Response body:"
cat /tmp/resp.json; echo
if [ "$HTTP" != "200" ] && [ "$HTTP" != "201" ] && [ "$HTTP" != "204" ]; then
  echo "ERROR: index creation failed" >&2
  exit 1
fi
echo "Index '$INDEX_NAME' is ready"
'''

resource createSearchIndex 'Microsoft.Resources/deploymentScripts@2023-08-01' = {
  name: '${baseName}-create-index'
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
      { name: 'SEARCH_ENDPOINT', value: searchEndpoint }
      { name: 'SEARCH_NAME', value: searchServiceName }
      { name: 'RESOURCE_GROUP', value: resourceGroup().name }
      { name: 'INDEX_NAME', value: searchIndexName }
    ]
    scriptContent: replace(createIndexScriptTemplate, '__INDEX_SCHEMA_PLACEHOLDER__', indexSchema)
  }
  dependsOn: [
    deployerSearchRole
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
        // Explicit service URIs are required for Flex Consumption's scale
        // controller to poll the queue/table endpoints when AzureWebJobsStorage
        // uses MI auth — without these the scale controller never discovers
        // queue depth and queue-trigger functions stay idle.
        { name: 'AzureWebJobsStorage__queueServiceUri', value: storageAccount.properties.primaryEndpoints.queue }
        { name: 'AzureWebJobsStorage__blobServiceUri', value: storageAccount.properties.primaryEndpoints.blob }
        { name: 'AzureWebJobsStorage__tableServiceUri', value: storageAccount.properties.primaryEndpoints.table }
        { name: 'FUNCTIONS_EXTENSION_VERSION', value: '~4' }
        // Python v2 (decorator-based) programming model — without this the host
        // falls back to the legacy v1 model that needs a function.json per
        // function and finds 0 functions in our decorator-only package.
        { name: 'AzureWebJobsFeatureFlags', value: 'EnableWorkerIndexing' }
        { name: 'PYTHON_ENABLE_INIT_INDEXING', value: '1' }
        { name: 'APPLICATIONINSIGHTS_CONNECTION_STRING', value: appInsights.properties.ConnectionString }

        // Connector config
        { name: 'TENANT_ID', value: subscription().tenantId }
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

        // Query-time security trimming (/api/search, called from OnKnowledgeRequested topic)
        { name: 'API_AUDIENCE', value: effectiveApiClientId }
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

// Foundry / AI Services (Vision multimodal) — Function App's MI for indexing-time
// embeddings, AND the Search service's MI for query-time vectorization (the
// registered aiServicesVision vectorizer on the index calls Foundry as the
// search service's MI when Copilot Studio submits text-only queries).
resource foundryAssignment 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(foundryAccount.id, cognitiveServicesUserRoleId, functionApp.id)
  scope: foundryAccount
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', cognitiveServicesUserRoleId)
    principalId: functionApp.identity.principalId
    principalType: 'ServicePrincipal'
  }
}

resource searchToFoundryAssignment 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(foundryAccount.id, cognitiveServicesUserRoleId, searchService.id)
  scope: foundryAccount
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', cognitiveServicesUserRoleId)
    principalId: searchService.identity.principalId
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
// One-shot code deploy via Flex Consumption's /api/publish endpoint.
//
// Why /api/publish (and not raw blob upload to deployment.storage)?
//   On Flex Consumption, the deployment.storage container is a *cache* the
//   runtime reads on first provisioning / scale-out. Writing the zip there
//   bypasses the publish-notification mechanism that signals the runtime to
//   recreate workers and sync triggers. The result: the package sits in
//   storage but the runtime never reloads, and the host reports `0 functions`.
//   `/api/publish` is the same path `func azure functionapp publish` and the
//   VS Code Azure Functions extension use; it stages the zip AND notifies
//   the runtime atomically.
//
// The deployerIdentity needs `Website Contributor` on the Function App so
// it can call /api/publish (Microsoft.Web/sites/publish/action).
// ============================================================================

resource deployerWebsiteRole 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(functionApp.id, websiteContributorRoleId, deployerIdentity.id)
  scope: functionApp
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', websiteContributorRoleId)
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
    timeout: 'PT30M'
    retentionInterval: 'PT1H'
    // Keep the script container around on failure so logs are recoverable
    // via `az deployment-scripts show-log` instead of being purged with the resource.
    cleanupPreference: 'OnExpiration'
    environmentVariables: [
      { name: 'PACKAGE_URL', value: packageReleaseUrl }
      { name: 'FUNCTION_APP_NAME', value: functionApp.name }
      { name: 'RESOURCE_GROUP', value: resourceGroup().name }
      { name: 'SUBSCRIPTION_ID', value: subscription().subscriptionId }
    ]
    scriptContent: '''
      set -eu
      set -o pipefail

      echo "=== Downloading package zip from $PACKAGE_URL ==="
      curl -sSL --fail -o /tmp/package.zip "$PACKAGE_URL"
      SIZE=$(stat -c%s /tmp/package.zip)
      echo "Downloaded $SIZE bytes"

      # ----------------------------------------------------------------
      # Wait for the Function App's runtime to finish its first-time
      # provisioning. Until siteProperties.state == "Running" any deploy
      # call (front-end /api/publish OR ARM onedeploy) returns 404. We
      # poll the ARM resource directly because it's reachable even when
      # the data-plane host is still cold.
      # ----------------------------------------------------------------
      ARM_BASE="https://management.azure.com/subscriptions/$SUBSCRIPTION_ID/resourceGroups/$RESOURCE_GROUP/providers/Microsoft.Web/sites/$FUNCTION_APP_NAME"
      echo "=== Waiting for $FUNCTION_APP_NAME state == Running ==="
      STATE=""
      for i in $(seq 1 60); do
        STATE=$(az rest --method get --url "$ARM_BASE?api-version=2024-04-01" --query "properties.state" -o tsv 2>/dev/null || echo "")
        echo "Probe $i: state=$STATE"
        if [ "$STATE" = "Running" ]; then
          break
        fi
        sleep 10
      done
      if [ "$STATE" != "Running" ]; then
        echo "WARNING: site state never became Running (last=$STATE); will still attempt deploy"
      fi
      # Belt-and-braces: even after state=Running, give the host another
      # 30s to wire up the deploy route — saves an unnecessary first 404.
      sleep 30

      # ----------------------------------------------------------------
      # Primary path: az functionapp deployment source config-zip
      #
      # On Flex Consumption this calls the publish endpoint via the
      # control plane, handling auth, polling, and ARM-side retries
      # internally. It's the same path `func azure functionapp publish`
      # uses on Flex.
      # ----------------------------------------------------------------
      echo "=== Deploying via 'az functionapp deployment source config-zip' ==="
      DEPLOY_OK=""
      for i in 1 2 3 4 5; do
        echo "Deploy attempt $i"
        if az functionapp deployment source config-zip \
              --resource-group "$RESOURCE_GROUP" \
              --name "$FUNCTION_APP_NAME" \
              --src /tmp/package.zip \
              --build-remote true \
              --timeout 600 2>&1; then
          DEPLOY_OK="yes"
          break
        fi
        echo "Attempt $i failed; sleeping 30s"
        sleep 30
      done

      # ----------------------------------------------------------------
      # Fallback: direct POST to <site>/api/publish with the management
      # bearer token. Some Flex regions/SDKs route this differently than
      # the CLI, so it's worth trying when the CLI path didn't take.
      # ----------------------------------------------------------------
      if [ -z "$DEPLOY_OK" ]; then
        echo "=== Fallback: POST https://$FUNCTION_APP_NAME.azurewebsites.net/api/publish ==="
        TOKEN=$(az account get-access-token --resource https://management.azure.com --query accessToken -o tsv)
        HTTP=""
        for i in 1 2 3 4 5; do
          echo "Fallback attempt $i"
          HTTP=$(curl -sS -o /tmp/resp.txt -w "%{http_code}" \
                 -X POST "https://$FUNCTION_APP_NAME.azurewebsites.net/api/publish?RemoteBuild=true" \
                 -H "Authorization: Bearer $TOKEN" \
                 -H "Content-Type: application/zip" \
                 --data-binary @/tmp/package.zip || echo "000")
          echo "HTTP $HTTP"
          if [ "$HTTP" = "200" ] || [ "$HTTP" = "202" ]; then
            DEPLOY_OK="yes"
            break
          fi
          echo "Response body:"; cat /tmp/resp.txt; echo
          sleep 30
        done
      fi

      if [ -z "$DEPLOY_OK" ]; then
        echo "ERROR: code deploy failed via both 'az functionapp deployment source config-zip' and POST /api/publish." >&2
        echo "Resources are provisioned correctly — finish the deploy manually:" >&2
        echo "  cd accelerators/sharepoint-connector" >&2
        echo "  func azure functionapp publish $FUNCTION_APP_NAME --python --build remote" >&2
        echo "See README section S1 for details." >&2
        exit 1
      fi
      echo "Code deploy succeeded — Flex will recreate workers and sync triggers."
    '''
  }
  dependsOn: [
    deployerWebsiteRole
  ]
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
output securityTrimmingEnabled bool = enableSecurityTrimming
output apiAudience string = effectiveApiClientId
output apiAppDisplayName string = shouldCreateAppRegistration ? apiApp!.displayName : (enableSecurityTrimming ? 'pre-created (apiAudience parameter supplied)' : 'security trimming disabled — no app registration')
