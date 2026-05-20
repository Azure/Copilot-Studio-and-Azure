// =============================================================================
// One-click deployable: VNets (primary + paired secondary) + AI Services with
// Private Endpoint + Private DNS + Power Platform Enterprise Policy.
//
// Pick a Power Platform region; the template derives:
//   * the primary Azure region (must be Content Understanding-supported)
//   * the paired secondary Azure region (delegated subnet for PP failover)
//   * the Enterprise Policy `location` (PP geo string)
//
// Only PP regions that have at least one Content Understanding-supported
// Azure region are exposed. Single-region PP geos (Sweden, Singapore) skip
// the secondary VNet.
//
// Sources:
//   PP supported regions: https://learn.microsoft.com/power-platform/admin/vnet-support-overview#supported-regions
//   CU supported regions: https://learn.microsoft.com/azure/ai-services/content-understanding/language-region-support#region-support
//
// Linking the policy to a Power Platform environment is NOT done here
// (requires PP admin auth). Run scripts/link-enterprise-policy.ps1 after.
// =============================================================================
targetScope = 'resourceGroup'

@description('Base name (3-11 chars, lowercase alphanumerics) used to derive resource names.')
@minLength(3)
@maxLength(11)
param baseName string = 'prvendcu'

@description('Power Platform region. Determines primary Azure region (Content Understanding-supported), paired secondary Azure region, and Enterprise Policy location. Only PP regions where at least one paired Azure region supports Content Understanding are listed.')
@allowed([
  'unitedstates'   // westus  (CU) + eastus    (paired)
  'europe'         // westeurope (CU) + northeurope (CU)
  'unitedkingdom'  // uksouth (CU) + ukwest
  'japan'          // japaneast (CU) + japanwest
  'australia'      // australiaeast (CU) + australiasoutheast
  'asia'           // southeastasia (CU) + eastasia
  'singapore'      // southeastasia (CU) - single-region geo
  'sweden'         // swedencentral (CU) - single-region geo
])
param powerPlatformRegion string = 'unitedstates'

@description('Power Platform environment GUID (NOT the org URL). Persisted as a deployment output for downstream linking.')
param powerPlatformEnvironmentId string

@description('Primary VNet address space.')
param vnetAddressPrefix string = '10.50.0.0/16'

@description('Private Endpoint subnet prefix (must be inside vnetAddressPrefix).')
param peSubnetPrefix string = '10.50.1.0/24'

@description('Power Platform delegated subnet prefix (must be /24, no NSG, no route table).')
param ppSubnetPrefix string = '10.50.2.0/24'

@description('Secondary VNet address space (must NOT overlap primary). Ignored for single-region PP geos (singapore, sweden).')
param secondaryVnetAddressPrefix string = '10.51.0.0/16'

@description('Secondary PP-delegated subnet prefix (/24, must be inside secondaryVnetAddressPrefix). Ignored for single-region PP geos.')
param secondaryPpSubnetPrefix string = '10.51.2.0/24'

@description('Name for the Enterprise Policy resource.')
param enterprisePolicyName string = 'ep-vnet-prvendcu'

@description('Tags applied to all resources.')
param tags object = {
  workload: 'content-understanding-pe'
  managedBy: 'arm-one-click'
}

// -----------------------------------------------------------------------------
// Region mapping: PP region -> { primary Azure region (CU), secondary Azure
// region (paired for delegated subnet), PP geo string for enterprisePolicies }.
// Single-region PP geos set secondary = '' to skip the secondary VNet.
// -----------------------------------------------------------------------------
var regionMap = {
  unitedstates:  { primary: 'westus',         secondary: 'eastus',              ppGeo: 'unitedstates'  }
  europe:        { primary: 'westeurope',     secondary: 'northeurope',         ppGeo: 'europe'        }
  unitedkingdom: { primary: 'uksouth',        secondary: 'ukwest',              ppGeo: 'unitedkingdom' }
  japan:         { primary: 'japaneast',      secondary: 'japanwest',           ppGeo: 'japan'         }
  australia:     { primary: 'australiaeast',  secondary: 'australiasoutheast',  ppGeo: 'australia'     }
  asia:          { primary: 'southeastasia',  secondary: 'eastasia',            ppGeo: 'asia'          }
  singapore:     { primary: 'southeastasia',  secondary: '',                    ppGeo: 'singapore'     }
  sweden:        { primary: 'swedencentral',  secondary: '',                    ppGeo: 'sweden'        }
}

var location          = regionMap[powerPlatformRegion].primary
var secondaryLocation = regionMap[powerPlatformRegion].secondary
var powerPlatformGeo  = regionMap[powerPlatformRegion].ppGeo
var deploySecondary   = !empty(secondaryLocation)

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

resource vnetSec 'Microsoft.Network/virtualNetworks@2024-05-01' = if (deploySecondary) {
  name: vnetNameSec
  location: deploySecondary ? secondaryLocation : location
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

// Bidirectional VNet peering between primary and secondary VNets. Required so
// that PP-injected runners egressing through the SECONDARY delegated subnet
// can reach the Private Endpoint NIC, which lives in the PRIMARY VNet.
// Without this, name resolution succeeds (DNS zones are linked to both VNets)
// but the connection times out at the IP layer.
resource peerPriToSec 'Microsoft.Network/virtualNetworks/virtualNetworkPeerings@2024-05-01' = if (deploySecondary) {
  name: 'peer-pri-to-sec'
  parent: vnet
  properties: {
    allowVirtualNetworkAccess: true
    allowForwardedTraffic: false
    allowGatewayTransit: false
    useRemoteGateways: false
    remoteVirtualNetwork: { id: vnetSec.id }
  }
}

resource peerSecToPri 'Microsoft.Network/virtualNetworks/virtualNetworkPeerings@2024-05-01' = if (deploySecondary) {
  name: 'peer-sec-to-pri'
  parent: vnetSec
  properties: {
    allowVirtualNetworkAccess: true
    allowForwardedTraffic: false
    allowGatewayTransit: false
    useRemoteGateways: false
    remoteVirtualNetwork: { id: vnet.id }
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

// Link the same Private DNS zones to the SECONDARY VNet too. PP-injected
// runners can egress through either delegated subnet (primary OR secondary);
// without this link, requests landing on the secondary subnet hit NODATA on
// privatelink.*.azure.com and fail with "Proxy could not connect to target
// service ... no data of the requested type was found".
resource dnsLinksSec 'Microsoft.Network/privateDnsZones/virtualNetworkLinks@2024-06-01' = [for (zoneName, i) in privateDnsZoneNames: if (deploySecondary) {
  name: '${vnetNameSec}-link'
  parent: dnsZones[i]
  location: 'global'
  properties: {
    registrationEnabled: false
    virtualNetwork: { id: vnetSec.id }
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
      virtualNetworks: deploySecondary ? [
        {
          id: vnet.id
          subnet: { name: ppSubnetName }
        }
        {
          id: vnetSec.id
          subnet: { name: ppSubnetName }
        }
      ] : [
        {
          id: vnet.id
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
output vnetSecondaryResourceId   string = deploySecondary ? vnetSec.id : ''
output ppSubnetResourceId        string = '${vnet.id}/subnets/${ppSubnetName}'
output ppSubnetSecondaryResourceId string = deploySecondary ? '${vnetSec.id}/subnets/${ppSubnetName}' : ''
output peSubnetResourceId        string = '${vnet.id}/subnets/${peSubnetName}'
output privateEndpointId         string = privateEndpoint.id
output enterprisePolicyId        string = enterprisePolicy.id
output powerPlatformEnvironmentId string = powerPlatformEnvironmentId
output powerPlatformRegion       string = powerPlatformRegion
output location                  string = location
output secondaryLocation         string = secondaryLocation
output powerPlatformGeo          string = powerPlatformGeo
