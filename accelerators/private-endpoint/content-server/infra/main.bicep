// =============================================================================
// Azure Content Understanding behind Private Endpoint + VNet
// for use with Power Platform (via Enterprise Policy / VNet integration)
// Scope: resourceGroup
// =============================================================================
targetScope = 'resourceGroup'

@description('Base name used to derive resource names. 3-11 chars, lowercase alphanumerics.')
@minLength(3)
@maxLength(11)
param baseName string = 'prvendcu'

@description('Azure region. Content Understanding is supported in westus, swedencentral, australiaeast.')
@allowed([ 'westus', 'swedencentral', 'australiaeast' ])
param location string = 'westus'

@description('VNet address space.')
param vnetAddressPrefix string = '10.50.0.0/16'

@description('Private Endpoint subnet prefix.')
param peSubnetPrefix string = '10.50.1.0/24'

@description('Power Platform delegated subnet prefix (must be /24, no NSG, no route table).')
param ppSubnetPrefix string = '10.50.2.0/24'

@description('Secondary (paired) Azure region for the second PP-delegated subnet. Required by PP enterprise policy in multi-region geographies (e.g. unitedstates needs westus + eastus).')
param secondaryLocation string = 'eastus'

@description('Secondary VNet address space (different from primary).')
param secondaryVnetAddressPrefix string = '10.51.0.0/16'

@description('Secondary PP delegated subnet prefix (/24).')
param secondaryPpSubnetPrefix string = '10.51.2.0/24'

@description('Tags applied to all resources.')
param tags object = {
  workload: 'content-understanding-pe'
  managedBy: 'bicep'
}

var vnetName       = 'vnet-${baseName}'
var vnetNameSec    = 'vnet-${baseName}-sec'
var peSubnetName   = 'snet-pe'
var ppSubnetName   = 'snet-powerplatform'
var aiName         = 'ais-${baseName}-${uniqueString(resourceGroup().id)}'
var peName         = 'pe-${aiName}'
var peNicName      = 'nic-${peName}'

// Private DNS zones required for AI Services account (covers Content Understanding,
// OpenAI, and AI Services data-plane endpoints surfaced through the same account)
var privateDnsZoneNames = [
  'privatelink.cognitiveservices.azure.com'
  'privatelink.openai.azure.com'
  'privatelink.services.ai.azure.com'
]

// ---------------------------------------------------------------------------
// Virtual Network with two subnets
// ---------------------------------------------------------------------------
resource vnet 'Microsoft.Network/virtualNetworks@2024-05-01' = {
  name: vnetName
  location: location
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
          privateEndpointNetworkPolicies: 'Disabled'
        }
      }
      {
        // Subnet delegated to Power Platform Enterprise Policy (VNet injection).
        // Requirements: /24, no NSG, no route table, no other delegations,
        // no service endpoints. Power Platform injects ENIs here.
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
// Secondary VNet in paired region (eastus) for the second PP-delegated subnet.
// Required because PP enterprise policies in multi-region geographies (e.g.
// 'unitedstates') need delegated subnets in two different Azure regions.
// ---------------------------------------------------------------------------
resource vnetSec 'Microsoft.Network/virtualNetworks@2024-05-01' = {
  name: vnetNameSec
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
// Azure AI Services account (Content Understanding is surfaced via AIServices kind)
// Public network access disabled; only the private endpoint can reach the data plane.
// `bypass: AzureServices` allows trusted Azure services (Azure ML, Search, etc.).
// NOTE: Power Platform is NOT in the trusted-services list -> reach via PE only.
// ---------------------------------------------------------------------------
resource aiServices 'Microsoft.CognitiveServices/accounts@2024-10-01' = {
  name: aiName
  location: location
  tags: tags
  kind: 'AIServices'
  sku: {
    name: 'S0'
  }
  identity: {
    type: 'SystemAssigned'
  }
  properties: {
    // custom subdomain is REQUIRED for private endpoints on Cognitive Services
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

// ---------------------------------------------------------------------------
// Private DNS zones + VNet links
// ---------------------------------------------------------------------------
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

// ---------------------------------------------------------------------------
// Private Endpoint to AI Services account
// ---------------------------------------------------------------------------
resource privateEndpoint 'Microsoft.Network/privateEndpoints@2024-05-01' = {
  name: peName
  location: location
  tags: tags
  properties: {
    customNetworkInterfaceName: peNicName
    subnet: {
      id: '${vnet.id}/subnets/${peSubnetName}'
    }
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
      properties: {
        privateDnsZoneId: dnsZones[i].id
      }
    }]
  }
  dependsOn: [ dnsLinks ]
}

// ---------------------------------------------------------------------------
// Outputs (consumed by deploy + connector scripts)
// ---------------------------------------------------------------------------
output aiAccountName        string = aiServices.name
output aiAccountEndpoint    string = aiServices.properties.endpoint
output aiAccountResourceId  string = aiServices.id
output vnetResourceId       string = vnet.id
output vnetSecondaryResourceId    string = vnetSec.id
output ppSubnetResourceId   string = '${vnet.id}/subnets/${ppSubnetName}'
output ppSubnetSecondaryResourceId string = '${vnetSec.id}/subnets/${ppSubnetName}'
output peSubnetResourceId   string = '${vnet.id}/subnets/${peSubnetName}'
output privateEndpointId    string = privateEndpoint.id
output location             string = location
output secondaryLocation    string = secondaryLocation
