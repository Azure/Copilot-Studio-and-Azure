// ============================================================================
// BYO storage role assignments.
//
// Cross-RG role assignments must live in a module whose targetScope matches
// the storage account's resource group. The parent template invokes this
// module with `scope: resourceGroup(<byoRg>)` only when the customer brings
// their own storage account.
// ============================================================================

@description('Name of the existing (BYO) storage account in this resource group.')
param storageAccountName string

@description('Principal ID of the Function App system-assigned managed identity.')
param principalId string

@description('Role definition ID (GUID only) for Storage Blob Data Owner.')
param storageBlobDataOwnerRoleId string

@description('Role definition ID (GUID only) for Storage Account Contributor.')
param storageAccountContributorRoleId string

@description('Role definition ID (GUID only) for Storage Queue Data Contributor.')
param storageQueueDataContributorRoleId string

@description('Role definition ID (GUID only) for Storage Table Data Contributor.')
param storageTableDataContributorRoleId string

resource byoStorage 'Microsoft.Storage/storageAccounts@2023-05-01' existing = {
  name: storageAccountName
}

resource blobDataOwner 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(byoStorage.id, storageBlobDataOwnerRoleId, principalId)
  scope: byoStorage
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', storageBlobDataOwnerRoleId)
    principalId: principalId
    principalType: 'ServicePrincipal'
  }
}

resource accountContributor 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(byoStorage.id, storageAccountContributorRoleId, principalId)
  scope: byoStorage
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', storageAccountContributorRoleId)
    principalId: principalId
    principalType: 'ServicePrincipal'
  }
}

resource queueDataContributor 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(byoStorage.id, storageQueueDataContributorRoleId, principalId)
  scope: byoStorage
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', storageQueueDataContributorRoleId)
    principalId: principalId
    principalType: 'ServicePrincipal'
  }
}

resource tableDataContributor 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(byoStorage.id, storageTableDataContributorRoleId, principalId)
  scope: byoStorage
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', storageTableDataContributorRoleId)
    principalId: principalId
    principalType: 'ServicePrincipal'
  }
}
