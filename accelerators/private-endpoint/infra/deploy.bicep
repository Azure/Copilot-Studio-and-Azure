// =============================================================================
// One-click deployable: VNets (primary + paired secondary) + AI Services with
// Private Endpoint + Private DNS + Power Platform Enterprise Policy.
//
// Linking the policy to a Power Platform environment is NOT done here
// (requires PP admin auth). Run scripts/link-enterprise-policy.ps1 after.
// =============================================================================
targetScope = 'resourceGroup'

@description('Base name (3-11 chars, lowercase alphanumerics) used to derive resource names.')
@minLength(3)
@maxLength(11)
param baseName string = 'prvendcu'

@description('Primary Azure region. Content Understanding supported regions only.')
@allowed([ 'westus', 'swedencentral', 'australiaeast' ])
param location string = 'westus'

@description('Paired secondary Azure region (used for the second PP-delegated subnet).')
param secondaryLocation string = 'eastus'

@description('Power Platform geo for the Enterprise Policy resource. Examples: unitedstates, europe, asia, australia. NOT an Azure region.')
param powerPlatformGeo string = 'unitedstates'

@description('Power Platform environment GUID (NOT the org URL). Persisted as a deployment output for downstream linking.')
param powerPlatformEnvironmentId string

@description('Primary VNet address space.')
param vnetAddressPrefix string = '10.50.0.0/16'

@description('Private Endpoint subnet prefix (must be inside vnetAddressPrefix).')
param peSubnetPrefix string = '10.50.1.0/24'

@description('Power Platform delegated subnet prefix (must be /24, no NSG, no route table).')
param ppSubnetPrefix string = '10.50.2.0/24'

@description('Secondary VNet address space (must NOT overlap primary).')
param secondaryVnetAddressPrefix string = '10.51.0.0/16'

@description('Secondary PP-delegated subnet prefix (/24, must be inside secondaryVnetAddressPrefix).')
param secondaryPpSubnetPrefix string = '10.51.2.0/24'

@description('Name for the Enterprise Policy resource.')
param enterprisePolicyName string = 'ep-vnet-prvendcu'

@description('Tags applied to all resources.')
param tags object = {
  workload: 'content-understanding-pe'
  managedBy: 'arm-one-click'
}

var vnetName     = 'vnet-${baseName}'
var vnetNameSec  = 'vnet-${baseName}-sec'
var peSubnetName = 'snet-pe'
var ppSubnetName = 'snet-powerplatform'
var aiName       = 'ais-${baseName}-${uniqueString(resourceGroup().id)}'
var peName       = 'pe-${aiName}'
var peNicName    = 'nic-${peName}'

var privateDnsZoneNames = [
  'privatelink.cognitiveservices.azure.com'
  'privatelink.openai.azure.com'
  'privatelink.services.ai.azure.com'
]

resource vnet 'Microsoft.Network/virtualNetworks@2024-05-01' = {
  name: vnetName
  location: location
  tags: tags
  properties: {
    addressSpace: { addressPrefixes: [ vnetAddressPrefix ] }
    subnets: [
      {
        name: peSubnetName
        properties: {
          addressPrefixes: [ peSubnetPrefix ]
          privateEndpointNetworkPolicies: 'Disabled'
        }
      }
      {
        name: ppSubnetName
        properties: {
          addressPrefixes: [ ppSubnetPrefix ]
          delegations: [
            {
              name: 'Microsoft.PowerPlatform.enterprisePolicies'
              properties: { serviceName: 'Microsoft.PowerPlatform/enterprisePolicies' }
            }
          ]
        }
      }
    ]
  }
}

resource vnetSec 'Microsoft.Network/virtualNetworks@2024-05-01' = {
  name: vnetNameSec
  location: secondaryLocation
  tags: tags
  properties: {
    addressSpace: { addressPrefixes: [ secondaryVnetAddressPrefix ] }
    subnets: [
      {
        name: ppSubnetName
        properties: {
          addressPrefixes: [ secondaryPpSubnetPrefix ]
          delegations: [
            {
              name: 'Microsoft.PowerPlatform.enterprisePolicies'
              properties: { serviceName: 'Microsoft.PowerPlatform/enterprisePolicies' }
            }
          ]
        }
      }
    ]
  }
}

resource aiServices 'Microsoft.CognitiveServices/accounts@2024-10-01' = {
  name: aiName
  location: location
  tags: tags
  kind: 'AIServices'
  sku: { name: 'S0' }
  identity: { type: 'SystemAssigned' }
  properties: {
    customSubDomainName: aiName
    publicNetworkAccess: 'Disabled'
    networkAcls: {
      defaultAction: 'Deny'
      bypass: 'AzureServices'
      ipRules: []
      virtualNetworkRules: []
    }
    disableLocalAuth: false
  }
}

resource dnsZones 'Microsoft.Network/privateDnsZones@2024-06-01' = [for zoneName in privateDnsZoneNames: {
  name: zoneName
  location: 'global'
  tags: tags
}]

resource dnsLinks 'Microsoft.Network/privateDnsZones/virtualNetworkLinks@2024-06-01' = [for (zoneName, i) in privateDnsZoneNames: {
  name: '${vnetName}-link'
  parent: dnsZones[i]
  location: 'global'
  properties: {
    registrationEnabled: false
    virtualNetwork: { id: vnet.id }
  }
}]

resource privateEndpoint 'Microsoft.Network/privateEndpoints@2024-05-01' = {
  name: peName
  location: location
  tags: tags
  properties: {
    customNetworkInterfaceName: peNicName
    subnet: { id: '${vnet.id}/subnets/${peSubnetName}' }
    privateLinkServiceConnections: [
      {
        name: 'plsc-${aiName}'
        properties: {
          privateLinkServiceId: aiServices.id
          groupIds: [ 'account' ]
        }
      }
    ]
  }
}

resource peDnsGroup 'Microsoft.Network/privateEndpoints/privateDnsZoneGroups@2024-05-01' = {
  name: 'default'
  parent: privateEndpoint
  properties: {
    privateDnsZoneConfigs: [for (zoneName, i) in privateDnsZoneNames: {
      name: replace(zoneName, '.', '-')
      properties: { privateDnsZoneId: dnsZones[i].id }
    }]
  }
  dependsOn: [ dnsLinks ]
}

resource enterprisePolicy 'Microsoft.PowerPlatform/enterprisePolicies@2020-10-30-preview' = {
  name: enterprisePolicyName
  location: powerPlatformGeo
  tags: tags
  kind: 'NetworkInjection'
  properties: {
    networkInjection: {
      virtualNetworks: [
        {
          id: vnet.id
          subnet: { name: ppSubnetName }
        }
        {
          id: vnetSec.id
          subnet: { name: ppSubnetName }
        }
      ]
    }
  }
}

output aiAccountName             string = aiServices.name
output aiAccountEndpoint         string = aiServices.properties.endpoint
output aiAccountResourceId       string = aiServices.id
output vnetResourceId            string = vnet.id
output vnetSecondaryResourceId   string = vnetSec.id
output ppSubnetResourceId        string = '${vnet.id}/subnets/${ppSubnetName}'
output ppSubnetSecondaryResourceId string = '${vnetSec.id}/subnets/${ppSubnetName}'
output peSubnetResourceId        string = '${vnet.id}/subnets/${peSubnetName}'
output privateEndpointId         string = privateEndpoint.id
output enterprisePolicyId        string = enterprisePolicy.id
output powerPlatformEnvironmentId string = powerPlatformEnvironmentId
output location                  string = location
output secondaryLocation         string = secondaryLocation
output powerPlatformGeo          string = powerPlatformGeo
