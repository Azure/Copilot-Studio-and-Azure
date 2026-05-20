// =============================================================================
// Azure AI Search behind Private Endpoint + VNet
// for use with Power Platform (via Enterprise Policy / VNet integration)
// Scope: resourceGroup
//
// Features:
//   - Optional AI Search provisioning (provisionAiSearch=false → PE only)
//   - Single Private DNS zone: privatelink.search.windows.net
//   - Primary VNet (pe-subnet + pp-delegated-subnet)
//   - Secondary VNet with pp-delegated-subnet (skipped for single-region PP geos)
//   - Power Platform Enterprise Policy (kind: NetworkInjection)
// =============================================================================
targetScope = 'resourceGroup'

@description('Base name (3–11 chars, lowercase alphanumerics) used to derive resource names.')
@minLength(3)
@maxLength(11)
param baseName string = 'pvsrch'

@description('Power Platform geography. Drives primary/secondary Azure regions and Enterprise Policy location.')
@allowed([
  'unitedstates'
  'europe'
  'unitedkingdom'
  'japan'
  'australia'
  'asia'
  'singapore'
  'sweden'
])
param powerPlatformRegion string = 'unitedstates'

@description('GUID of the target Power Platform environment (not the org URL).')
param powerPlatformEnvironmentId string

@description('Set true (default) to provision a new Azure AI Search service. Set false to use an existing service — supply existingAiSearchResourceId.')
param provisionAiSearch bool = true

@description('Full ARM resource ID of an existing Azure AI Search service. Used only when provisionAiSearch=false.')
param existingAiSearchResourceId string = ''

@description('SKU for the new Azure AI Search service. Free tier is excluded — it does not support private endpoints.')
@allowed([
  'basic'
  'standard'
  'standard2'
  'standard3'
  'storage_optimized_l1'
  'storage_optimized_l2'
])
param aiSearchSku string = 'basic'

@description('Primary VNet address space. Ignored when provisionVnet=false.')
param vnetAddressPrefix string = '10.60.0.0/16'

@description('Private Endpoint subnet address prefix (/24 recommended). Ignored when provisionVnet=false.')
param peSubnetPrefix string = '10.60.1.0/24'

@description('Power Platform delegated subnet address prefix (must be /24, no NSG, no route table). Ignored when provisionVnet=false.')
param ppSubnetPrefix string = '10.60.2.0/24'

@description('Secondary VNet address space. Must not overlap primary. Ignored for single-region PP geos or when provisionVnet=false.')
param secondaryVnetAddressPrefix string = '10.61.0.0/16'

@description('Secondary Power Platform delegated subnet prefix (/24). Ignored for single-region PP geos or when provisionVnet=false.')
param secondaryPpSubnetPrefix string = '10.61.2.0/24'

@description('Set true (default) to create new VNets with subnets. Set false to use existing VNets — supply the existing resource IDs below.')
param provisionVnet bool = true

@description('Full ARM resource ID of the existing primary VNet. Used only when provisionVnet=false. Must already contain a PE subnet and a PP-delegated subnet.')
param existingVnetId string = ''

@description('Name of the existing PE subnet in the primary VNet. Used only when provisionVnet=false. Must have privateEndpointNetworkPolicies=Disabled.')
param existingPeSubnetName string = 'snet-pe'

@description('Name of the existing Power Platform delegated subnet in the primary VNet. Used only when provisionVnet=false. Must be /24, delegated to Microsoft.PowerPlatform/enterprisePolicies.')
param existingPpSubnetName string = 'snet-powerplatform'

@description('Full ARM resource ID of the existing secondary VNet. Used only when provisionVnet=false and the PP geo is multi-region. Must contain a PP-delegated subnet.')
param existingSecondaryVnetId string = ''

@description('Name of the existing PP-delegated subnet in the secondary VNet. Used only when provisionVnet=false and the PP geo is multi-region.')
param existingSecondaryPpSubnetName string = 'snet-powerplatform'

@description('Tags applied to all provisioned resources.')
param tags object = {
  workload: 'aisearch-pe'
  managedBy: 'bicep'
}

// ---------------------------------------------------------------------------
// Region mapping: PP geo → Azure regions
// ---------------------------------------------------------------------------
var regionMap = {
  unitedstates:  { primary: 'westus',        secondary: 'eastus',             singleRegion: false }
  europe:        { primary: 'westeurope',     secondary: 'northeurope',        singleRegion: false }
  unitedkingdom: { primary: 'uksouth',        secondary: 'ukwest',             singleRegion: false }
  japan:         { primary: 'japaneast',      secondary: 'japanwest',          singleRegion: false }
  australia:     { primary: 'australiaeast',  secondary: 'australiasoutheast', singleRegion: false }
  asia:          { primary: 'southeastasia',  secondary: 'eastasia',           singleRegion: false }
  singapore:     { primary: 'southeastasia',  secondary: '',                   singleRegion: true  }
  sweden:        { primary: 'swedencentral',  secondary: '',                   singleRegion: true  }
}

var primaryLocation   = regionMap[powerPlatformRegion].primary
var secondaryLocation = regionMap[powerPlatformRegion].secondary
var isSingleRegionGeo = regionMap[powerPlatformRegion].singleRegion

// ---------------------------------------------------------------------------
// Resource name derivation
// ---------------------------------------------------------------------------
var vnetName          = 'vnet-${baseName}-srch'
var vnetSecName       = 'vnet-${baseName}-srch-sec'
var peSubnetName      = 'snet-pe'
var ppSubnetName      = 'snet-powerplatform'
var searchName        = 'srch-${baseName}-${uniqueString(resourceGroup().id)}'
var peName            = 'pe-${searchName}'
var peNicName         = 'nic-${peName}'
var privateDnsZone    = 'privatelink.search.windows.net'

// Resolve the target search service resource ID for the private endpoint.
// When provisionAiSearch=false the caller must supply existingAiSearchResourceId.
var searchResourceId  = provisionAiSearch
  ? resourceId('Microsoft.Search/searchServices', searchName)
  : existingAiSearchResourceId

// Resolve VNet and subnet IDs — new or existing
var resolvedVnetId          = provisionVnet ? vnet.id : existingVnetId
var resolvedPeSubnetName    = provisionVnet ? peSubnetName : existingPeSubnetName
var resolvedPpSubnetName    = provisionVnet ? ppSubnetName : existingPpSubnetName
var resolvedSecVnetId       = provisionVnet ? (isSingleRegionGeo ? '' : vnetSec.id) : existingSecondaryVnetId
var resolvedSecPpSubnetName = provisionVnet ? ppSubnetName : existingSecondaryPpSubnetName

// ---------------------------------------------------------------------------
// Primary VNet (pe-subnet + pp-delegated-subnet) — skipped when provisionVnet=false
// ---------------------------------------------------------------------------
resource vnet 'Microsoft.Network/virtualNetworks@2024-05-01' = if (provisionVnet) {
  name: vnetName
  location: primaryLocation
  tags: tags
  properties: {
    addressSpace: {
      addressPrefixes: [ vnetAddressPrefix ]
    }
    subnets: [
      {
        name: peSubnetName
        properties: {
          addressPrefixes: [ peSubnetPrefix ]
          // Required: disable PE network policies so NSG/UDR don't block the PE NIC.
          privateEndpointNetworkPolicies: 'Disabled'
        }
      }
      {
        // Delegated subnet for Power Platform Enterprise Policy (VNet injection).
        // Requirements: exactly /24, no NSG, no route table, no other delegations.
        name: ppSubnetName
        properties: {
          addressPrefixes: [ ppSubnetPrefix ]
          delegations: [
            {
              name: 'Microsoft.PowerPlatform.enterprisePolicies'
              properties: {
                serviceName: 'Microsoft.PowerPlatform/enterprisePolicies'
              }
            }
          ]
        }
      }
    ]
  }
}

// ---------------------------------------------------------------------------
// Secondary VNet — skipped for single-region PP geos (singapore, sweden)
// Also skipped when provisionVnet=false.
// Required by PP Enterprise Policy in multi-region geographies.
// ---------------------------------------------------------------------------
resource vnetSec 'Microsoft.Network/virtualNetworks@2024-05-01' = if (provisionVnet && !isSingleRegionGeo) {
  name: vnetSecName
  location: secondaryLocation
  tags: tags
  properties: {
    addressSpace: {
      addressPrefixes: [ secondaryVnetAddressPrefix ]
    }
    subnets: [
      {
        name: ppSubnetName
        properties: {
          addressPrefixes: [ secondaryPpSubnetPrefix ]
          delegations: [
            {
              name: 'Microsoft.PowerPlatform.enterprisePolicies'
              properties: {
                serviceName: 'Microsoft.PowerPlatform/enterprisePolicies'
              }
            }
          ]
        }
      }
    ]
  }
}

// ---------------------------------------------------------------------------
// Azure AI Search service (optional — skipped when provisionAiSearch=false)
// publicNetworkAccess=disabled: only reachable through the private endpoint.
// ---------------------------------------------------------------------------
resource searchService 'Microsoft.Search/searchServices@2024-06-01-preview' = if (provisionAiSearch) {
  name: searchName
  location: primaryLocation
  tags: tags
  sku: {
    name: aiSearchSku
  }
  identity: {
    type: 'SystemAssigned'
  }
  properties: {
    replicaCount: 1
    partitionCount: 1
    // Disable public network access — only the private endpoint can reach the data plane.
    publicNetworkAccess: 'disabled'
    networkRuleSet: {
      // AzurePortal bypass allows Azure Portal to reach the service for management.
      // Power Platform runtime calls do NOT benefit from this bypass.
      bypass: 'AzurePortal'
      ipRules: []
    }
    disableLocalAuth: false
    authOptions: {
      // Supports both Entra ID tokens and API keys.
      aadOrApiKey: {
        aadAuthFailureMode: 'http401WithBearerChallenge'
      }
    }
  }
}

// ---------------------------------------------------------------------------
// Private DNS zone for AI Search
// Only one zone needed: privatelink.search.windows.net
// ---------------------------------------------------------------------------
resource dnsZone 'Microsoft.Network/privateDnsZones@2024-06-01' = {
  name: privateDnsZone
  location: 'global'
  tags: tags
}

resource dnsLink 'Microsoft.Network/privateDnsZones/virtualNetworkLinks@2024-06-01' = {
  name: '${vnetName}-link'
  parent: dnsZone
  location: 'global'
  properties: {
    registrationEnabled: false
    virtualNetwork: { id: resolvedVnetId }
  }
}

// ---------------------------------------------------------------------------
// Private Endpoint → AI Search
// Group ID 'searchService' is the only supported group for search services.
// ---------------------------------------------------------------------------
resource privateEndpoint 'Microsoft.Network/privateEndpoints@2024-05-01' = {
  name: peName
  location: primaryLocation
  tags: tags
  properties: {
    customNetworkInterfaceName: peNicName
    subnet: {
      id: '${resolvedVnetId}/subnets/${resolvedPeSubnetName}'
    }
    privateLinkServiceConnections: [
      {
        name: 'plsc-${searchName}'
        properties: {
          privateLinkServiceId: searchResourceId
          groupIds: [ 'searchService' ]
        }
      }
    ]
  }
  dependsOn: provisionAiSearch ? [ searchService ] : []
}

resource peDnsGroup 'Microsoft.Network/privateEndpoints/privateDnsZoneGroups@2024-05-01' = {
  name: 'default'
  parent: privateEndpoint
  properties: {
    privateDnsZoneConfigs: [
      {
        name: replace(privateDnsZone, '.', '-')
        properties: {
          privateDnsZoneId: dnsZone.id
        }
      }
    ]
  }
  dependsOn: [ dnsLink ]
}

// ---------------------------------------------------------------------------
// Power Platform Enterprise Policy (Network Injection / VNet integration)
// location must be the PP geo string (e.g. 'unitedstates'), NOT an Azure region.
// ---------------------------------------------------------------------------
resource enterprisePolicy 'Microsoft.PowerPlatform/enterprisePolicies@2020-10-30-preview' = {
  name: 'ep-vnet-${baseName}-srch'
  // IMPORTANT: location must be the PP geography string, not an Azure region name.
  location: powerPlatformRegion
  tags: tags
  kind: 'NetworkInjection'
  properties: {
    networkInjection: {
      virtualNetworks: isSingleRegionGeo
        ? [
            {
              id: resolvedVnetId
              subnet: { name: resolvedPpSubnetName }
            }
          ]
        : [
            {
              id: resolvedVnetId
              subnet: { name: resolvedPpSubnetName }
            }
            {
              id: resolvedSecVnetId
              subnet: { name: resolvedSecPpSubnetName }
            }
          ]
    }
  }
  dependsOn: [ peDnsGroup ]
}

// ---------------------------------------------------------------------------
// Outputs (consumed by downstream scripts)
// ---------------------------------------------------------------------------
output searchServiceName string = provisionAiSearch
  ? searchService.name
  : last(split(existingAiSearchResourceId, '/'))

output searchServiceEndpoint string = 'https://${provisionAiSearch ? searchService.name : last(split(existingAiSearchResourceId, '/'))}.search.windows.net/'

output enterprisePolicyId        string = enterprisePolicy.id
output ppSubnetResourceId        string = '${resolvedVnetId}/subnets/${resolvedPpSubnetName}'
output ppSubnetSecondaryResourceId string = isSingleRegionGeo ? '' : '${resolvedSecVnetId}/subnets/${resolvedSecPpSubnetName}'
output vnetId                    string = resolvedVnetId
output peSubnetResourceId        string = '${resolvedVnetId}/subnets/${resolvedPeSubnetName}'
output privateDnsZoneId          string = dnsZone.id
