param location string
param resourceSuffixUID string
param appGatewaySubnetId string
param loadBalancerPrivateIp string
param workspaceId string
param minAppGatewayCapacity int = 3
param maxAppGatewayCapacity int = 125

var appGatewayName = 'appgw-${resourceSuffixUID}'

// See: https://learn.microsoft.com/en-us/azure/application-gateway/quick-create-bicep?tabs=CLI
resource publicIPAddress 'Microsoft.Network/publicIPAddresses@2021-05-01' = {
  name: 'appgw-pip-${resourceSuffixUID}'
  location: location
  zones: ['1', '2', '3']
  sku: {
    name: 'Standard'
  }
  properties: {
    publicIPAddressVersion: 'IPv4'
    publicIPAllocationMethod: 'Static'
    idleTimeoutInMinutes: 4
    ipTags: [
      {
        ipTagType: 'FirstPartyUsage'
        tag: '/SyntheticLoad'
      }
    ]
  }
}

resource applicationGateWay 'Microsoft.Network/applicationGateways@2021-05-01' = {
  name: appGatewayName
  location: location
  zones: ['1', '2', '3']
  properties: {
    sku: {
      name: 'Standard_v2'
      tier: 'Standard_v2'
    }
    autoscaleConfiguration: {
      maxCapacity: maxAppGatewayCapacity
      minCapacity: minAppGatewayCapacity
    }
    gatewayIPConfigurations: [
      {
        name: 'appGatewayIpConfig'
        properties: {
          subnet: {
            id: appGatewaySubnetId
          }
        }
      }
    ]
    frontendIPConfigurations: [
      {
        name: 'appGwPublicFrontendIp'
        properties: {
          privateIPAllocationMethod: 'Dynamic'
          publicIPAddress: {
            id: publicIPAddress.id
          }
        }
      }
    ]
    frontendPorts: [
      {
        name: 'port_80'
        properties: {
          port: 80
        }
      }
    ]
    backendAddressPools: [
      {
        name: 'myBackendPool'
        properties: {
          backendAddresses: [
            {
              ipAddress: loadBalancerPrivateIp
            }
          ]
        }
      }
    ]
    backendHttpSettingsCollection: [
      {
        name: 'webAppSettings'
        properties: {
          port: 80
          protocol: 'Http'
          cookieBasedAffinity: 'Disabled'
          pickHostNameFromBackendAddress: false
          requestTimeout: 20
          probe: {
            id: resourceId('Microsoft.Network/applicationGateways/probes', appGatewayName, 'app-health')
          }
        }
      }
    ]
    httpListeners: [
      {
        name: 'httpListener'
        properties: {
          frontendIPConfiguration: {
            id: resourceId(
              'Microsoft.Network/applicationGateways/frontendIPConfigurations',
              appGatewayName,
              'appGwPublicFrontendIp'
            )
          }
          frontendPort: {
            id: resourceId('Microsoft.Network/applicationGateways/frontendPorts', appGatewayName, 'port_80')
          }
          protocol: 'Http'
          requireServerNameIndication: false
        }
      }
    ]
    urlPathMaps: [
      {
        name: 'httpRule'
        properties: {
          defaultBackendAddressPool: {
            id: resourceId('Microsoft.Network/applicationGateways/backendAddressPools', appGatewayName, 'myBackendPool')
          }
          defaultBackendHttpSettings: {
            id: resourceId(
              'Microsoft.Network/applicationGateways/backendHttpSettingsCollection',
              appGatewayName,
              'webAppSettings'
            )
          }
          pathRules: [
            {
              name: 'cart'
              properties: {
                paths: [
                  '/api/*'
                ]
                backendAddressPool: {
                  id: resourceId(
                    'Microsoft.Network/applicationGateways/backendAddressPools',
                    appGatewayName,
                    'myBackendPool'
                  )
                }
                backendHttpSettings: {
                  id: resourceId(
                    'Microsoft.Network/applicationGateways/backendHttpSettingsCollection',
                    appGatewayName,
                    'webAppSettings'
                  )
                }
              }
            }
          ]
        }
      }
    ]
    requestRoutingRules: [
      {
        name: 'httpRule'
        properties: {
          ruleType: 'PathBasedRouting'
          priority: 1
          httpListener: {
            id: resourceId('Microsoft.Network/applicationGateways/httpListeners', appGatewayName, 'httpListener')
          }
          urlPathMap: {
            id: resourceId('Microsoft.Network/applicationGateways/urlPathMaps', appGatewayName, 'httpRule')
          }
        }
      }
    ]
    probes: [
      {
        name: 'app-health'
        properties: {
          protocol: 'Http'
          host: '127.0.0.1'
          path: '/api/live'
          interval: 30
          timeout: 30
          unhealthyThreshold: 3
          pickHostNameFromBackendHttpSettings: false
          minServers: 0
          match: {}
        }
      }
    ]
    enableHttp2: false
  }
}

resource diagnosticLogs 'Microsoft.Insights/diagnosticSettings@2021-05-01-preview' = {
  name: applicationGateWay.name
  scope: applicationGateWay
  properties: {
    workspaceId: workspaceId
    logs: [
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

resource diagnosticLogsPublicIP 'Microsoft.Insights/diagnosticSettings@2021-05-01-preview' = {
  name: publicIPAddress.name
  scope: publicIPAddress
  properties: {
    workspaceId: workspaceId
    logs: [
      // FIXME: not supported in spaincentral
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

output publicIpAddress string = publicIPAddress.properties.ipAddress
