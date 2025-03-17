// common parameters
param resourceSuffixUID string
param workspaceId string

// primary location
param primaryLocation string
param primaryLocationInfraSubnetId string
param primaryLocationAKSSubnetId string

// secondary location
param secondaryLocation string = ''
param secondaryLocationInfraSubnetId string = ''
param secondaryLocationAKSSubnetId string = ''

var subnetIds = empty(secondaryLocation)
  ? [primaryLocationInfraSubnetId, primaryLocationAKSSubnetId]
  : [primaryLocationInfraSubnetId, primaryLocationAKSSubnetId, secondaryLocationInfraSubnetId, secondaryLocationAKSSubnetId]

var locations = empty(secondaryLocation) ? [primaryLocation] : [primaryLocation, secondaryLocation]

// Note: no specific configuration for Zone Redundancy
// See: https://learn.microsoft.com/en-us/Azure/key-vault/general/disaster-recovery-guidance
resource keyVault 'Microsoft.KeyVault/vaults@2022-07-01' = {
  name: 'keyvault-${resourceSuffixUID}'
  location: primaryLocation
  properties: {
    sku: {
      name: 'standard'
      family: 'A'
    }
    tenantId: tenant().tenantId
    enableRbacAuthorization: true
    enableSoftDelete: true
    publicNetworkAccess: 'Enabled'  // Enabled for selected networks from vnet rules
    networkAcls: {
      bypass: 'AzureServices'
      defaultAction: 'Deny'
      ipRules: []
      virtualNetworkRules: [for subnetId in subnetIds: { id: subnetId }]
    }
  }
}

resource diagnosticLogs 'Microsoft.Insights/diagnosticSettings@2021-05-01-preview' = {
  name: keyVault.name
  scope: keyVault
  properties: {
    workspaceId: workspaceId
    logs: [
      //{
      //  categoryGroup: 'audit'
      //  enabled: true
      //}
      {
        categoryGroup: 'allLogs'
        enabled: true
      }
    ]
    metrics: [
      {
        category: 'AllMetrics'
        enabled: true
      }
    ]
  }
}

output keyvaultId string = keyVault.id
output keyvaultName string = keyVault.name
