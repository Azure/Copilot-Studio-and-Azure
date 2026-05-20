// =============================================================================
// Power Platform Enterprise Policy (Network Injection / VNet Integration)
// Allows Power Platform to inject ENIs into the delegated subnet so that
// connectors / flows reach private endpoints inside the VNet.
//
// Prereqs:
//  - Resource provider Microsoft.PowerPlatform must be registered
//  - Subnet must be /24, delegated to Microsoft.PowerPlatform/enterprisePolicies
//  - Target Power Platform environment must be a *Managed Environment*
// =============================================================================
targetScope = 'resourceGroup'

@description('Name of the Enterprise Policy resource.')
param policyName string = 'ep-vnet-prvendcu'

@description('Primary region (must match the VNet region and be a PP-supported region).')
param location string = 'westus'

@description('Resource ID of the primary delegated subnet.')
param primarySubnetId string

@description('Optional resource ID of a secondary (failover) delegated subnet in the paired region.')
param secondarySubnetId string = ''

@description('Tags.')
param tags object = {}

resource enterprisePolicy 'Microsoft.PowerPlatform/enterprisePolicies@2020-10-30-preview' = {
  name: policyName
  location: location
  tags: tags
  kind: 'NetworkInjection'
  properties: {
    networkInjection: {
      virtualNetworks: empty(secondarySubnetId) ? [
        {
          id: split(primarySubnetId, '/subnets/')[0]
          subnet: {
            name: split(primarySubnetId, '/subnets/')[1]
          }
        }
      ] : [
        {
          id: split(primarySubnetId, '/subnets/')[0]
          subnet: {
            name: split(primarySubnetId, '/subnets/')[1]
          }
        }
        {
          id: split(secondarySubnetId, '/subnets/')[0]
          subnet: {
            name: split(secondarySubnetId, '/subnets/')[1]
          }
        }
      ]
    }
  }
}

output policyId   string = enterprisePolicy.id
output policyName string = enterprisePolicy.name
