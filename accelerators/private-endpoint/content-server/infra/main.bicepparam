using './main.bicep'

param baseName = 'prvendcu'
param location = 'westus'
param vnetAddressPrefix = '10.50.0.0/16'
param peSubnetPrefix    = '10.50.1.0/24'
param ppSubnetPrefix    = '10.50.2.0/24'
param tags = {
  workload: 'content-understanding-pe'
  managedBy: 'bicep'
}
