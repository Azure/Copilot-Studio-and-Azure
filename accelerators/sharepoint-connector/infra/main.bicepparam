using './main.bicep'

param baseName = 'sp-indexer'
param location = 'swedencentral'

param tenantId = '00000000-0000-0000-0000-000000000000'
param sharePointSiteUrl = 'https://yourcompany.sharepoint.com/sites/YourSite'

param searchEndpoint = 'https://your-search.search.windows.net'
param searchResourceId = '/subscriptions/<sub-id>/resourceGroups/<rg>/providers/Microsoft.Search/searchServices/your-search'
param searchIndexName = 'sharepoint-index'

param foundryEndpoint = 'https://your-foundry.cognitiveservices.azure.com'
param foundryResourceId = '/subscriptions/<sub-id>/resourceGroups/<rg>/providers/Microsoft.CognitiveServices/accounts/your-foundry'
param multimodalModelVersion = '2023-04-15'

param processingMode = 'since-last-run'
param startDate = ''
param indexerSchedule = '0 0 * * * *'

param provisionDocIntel = false
param docIntelEndpoint = ''
param docIntelResourceId = ''

param useClientSecret = false
param clientSecretValue = ''

param apiAudience = ''
param alwaysAllowedIds = ''

param imagesContainerName = 'images'
param extractImages = true
param forceRecreateIndex = false

param sharePointRootPaths = ''
param vectoriseConcurrency = 8
param multimodalMaxInFlight = 8
param reconcileEveryNRuns = 24

param backupSchedule = '0 0 3 * * *'
param backupRetentionDays = 7
