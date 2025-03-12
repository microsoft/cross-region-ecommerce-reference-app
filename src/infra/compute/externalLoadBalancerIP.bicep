param location string
param resourceSuffixUID string
param workspaceId string

resource publicIP 'Microsoft.Network/publicIPAddresses@2022-01-01' = {
  name: 'elb-pip-${resourceSuffixUID}'
  location: location
  zones: ['1', '2', '3']
  sku: {
    name: 'Standard'
  }
  properties: {
    publicIPAllocationMethod: 'Static'
    publicIPAddressVersion: 'IPv4'
  }
}

resource diagnosticLogs 'Microsoft.Insights/diagnosticSettings@2021-05-01-preview' = {
  name: publicIP.name
  scope: publicIP
  properties: {
    workspaceId: workspaceId
    logs: [
      // FIXME: spaincentral only supports allLogs
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

output externalLoadBalancerIP string = publicIP.properties.ipAddress
output externalLoadBalancerIPId string = publicIP.id
