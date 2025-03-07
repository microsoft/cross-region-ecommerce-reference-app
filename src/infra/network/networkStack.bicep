param resourceSuffixUID string
param location string
param networkConfig object
param workspaceId string

var infraSubnetName = 'InfraSubnet'
var infraSubnetCidr = networkConfig.subnets[infraSubnetName].cidr

var dnsResolverSubnetName = 'DnsResolverSubnet'
var dnsResolverSubnetCidr = networkConfig.subnets[dnsResolverSubnetName].cidr

var appGatewaySubnetName = 'AppGatewaySubnet'
var appGatewaySubnetCidr = networkConfig.subnets[appGatewaySubnetName].cidr

var aksSubnetName = 'AKSSubnet'
var aksSubnetCidr = networkConfig.subnets[aksSubnetName].cidr

resource vnet 'Microsoft.Network/virtualNetworks@2022-01-01' = {
  name: 'vnet-${resourceSuffixUID}'
  location: location
  properties: {
    addressSpace: {
      addressPrefixes: [
        networkConfig.vnet.cidr
      ]
    }
    subnets: [
      {
        name: infraSubnetName
        properties: {
          addressPrefix: infraSubnetCidr
          networkSecurityGroup: {
            id: infraSubnetNsg.id
          }
          serviceEndpoints: [
            {
              service: 'Microsoft.KeyVault'
            }
            {
              service: 'Microsoft.Sql'
            }
          ]
        }
      }
      {
        name: appGatewaySubnetName
        properties: {
          addressPrefix: appGatewaySubnetCidr
          networkSecurityGroup: {
            id: appGatewaySubnetNsg.id
          }
        }
      }
      {
        name: dnsResolverSubnetName
        properties: {
          addressPrefix: dnsResolverSubnetCidr
          networkSecurityGroup: {
            id: dnsResolverSubnetNsg.id
          }
          delegations: [
            {
              name: 'Microsoft.Network.dnsResolvers'
              properties: {
                serviceName: 'Microsoft.Network/dnsResolvers'
              }
              type: 'Microsoft.Network/virtualNetworks/subnets/delegations'
            }
          ]
        }
      }
      {
        name: aksSubnetName
        properties: {
          addressPrefix: aksSubnetCidr
          networkSecurityGroup: {
            id: aksSubnetNsg.id
          }
          serviceEndpoints: [
            {
              service: 'Microsoft.KeyVault'
            }
            {
              service: 'Microsoft.Sql'
            }
          ]
        }
      }
    ]
  }

  resource infraSubnet 'subnets' existing = {
    name: infraSubnetName
  }
  resource dnsResolverSubnet 'subnets' existing = {
    name: dnsResolverSubnetName
  }
  resource appGatewaySubnet 'subnets' existing = {
    name: appGatewaySubnetName
  }
  resource aksSubnet 'subnets' existing = {
    name: aksSubnetName
  }
}

// Define NSGs
resource infraSubnetNsg 'Microsoft.Network/networkSecurityGroups@2022-01-01' = {
  name: 'vnet-nsg-${resourceSuffixUID}'
  location: location
  properties: {}
}

resource appGatewaySubnetNsg 'Microsoft.Network/networkSecurityGroups@2022-01-01' = {
  name: 'appgateway-subnet-nsg-${resourceSuffixUID}'
  location: location
  properties: {
    securityRules: [
      {
        name: 'OFP-rule-300'
        properties: {
          description: 'OFP-rule-300 - RequiredPortsForAppGateway'
          protocol: '*'
          sourcePortRange: '*'
          destinationPortRange: '65200-65535'
          sourceAddressPrefix: 'GatewayManager'
          destinationAddressPrefix: '*'
          access: 'Allow'
          priority: 300
          direction: 'Inbound'
        }
      }
      {
        name: 'OFP-rule-301'
        properties: {
          description: 'OFP-rule-301 - Allow FrontDoor to talk to AppGateway'
          protocol: 'TCP'
          sourcePortRange: '*'
          sourceAddressPrefix: 'AzureFrontDoor.Backend'
          destinationAddressPrefix: 'VirtualNetwork'
          access: 'Allow'
          priority: 301
          direction: 'Inbound'
          sourcePortRanges: []
          destinationPortRanges: [
            '443'
            '80'
          ]
          sourceAddressPrefixes: []
          destinationAddressPrefixes: []
        }
      }
    ]
  }
}

resource dnsResolverSubnetNsg 'Microsoft.Network/networkSecurityGroups@2022-01-01' = {
  name: 'dnsresolver-subnet-nsg-${resourceSuffixUID}'
  location: location
  properties: {
    securityRules: [
      {
        name: 'OFP-rule-303'
        properties: {
          description: 'OFP-rule-303 - Allow DNS TCP'
          protocol: 'Tcp'
          sourcePortRange: '*'
          destinationPortRange: '53'
          sourceAddressPrefix: 'VirtualNetwork'
          destinationAddressPrefix: '*'
          access: 'Allow'
          priority: 303
          direction: 'Inbound'
        }
      }
      {
        name: 'OFP-rule-304'
        properties: {
          description: 'OFP-rule-304 - Allow DNS UDP'
          protocol: 'Udp'
          sourcePortRange: '*'
          destinationPortRange: '53'
          sourceAddressPrefix: 'VirtualNetwork'
          destinationAddressPrefix: '*'
          access: 'Allow'
          priority: 304
          direction: 'Inbound'
        }
      }
    ]
  }
}

resource aksSubnetNsg 'Microsoft.Network/networkSecurityGroups@2022-01-01' = {
  name: 'aks-subnet-nsg-${resourceSuffixUID}'
  location: location
  properties: {
    securityRules: [
      {
        name: 'OFP-rule-302'
        properties: {
          description: 'OFP-rule-302 - Allow port 80 to the subnet from the virtual network'
          protocol: 'Tcp'
          sourcePortRange: '*'
          destinationPortRange: '80'
          sourceAddressPrefix: 'VirtualNetwork'
          destinationAddressPrefix: '*'
          access: 'Allow'
          priority: 302
          direction: 'Inbound'
        }
      }
    ]
  }
}

resource diagnosticLogs 'Microsoft.Insights/diagnosticSettings@2021-05-01-preview' = {
  name: vnet.name
  scope: vnet
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

output vnetName string = vnet.name
output vnetId string = vnet.id
output infraSubnetId string = vnet::infraSubnet.id
output dnsResolverSubnetId string = vnet::dnsResolverSubnet.id
output appGatewaySubnetId string = vnet::appGatewaySubnet.id
output aksSubnetId string = vnet::aksSubnet.id
