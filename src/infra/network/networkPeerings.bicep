param resourceSuffixUID string
param primaryVnetName string
param secondaryVnetName string

resource primaryVnet 'Microsoft.Network/virtualNetworks@2022-01-01' existing = {
  name: primaryVnetName
}

resource secondaryVnet 'Microsoft.Network/virtualNetworks@2022-01-01' existing = {
  name: secondaryVnetName
}

resource primaryToSecondaryVnetPeering 'Microsoft.Network/virtualNetworks/virtualNetworkPeerings@2022-01-01' = {
  name: 'vnetPeering-${resourceSuffixUID}'
  parent: primaryVnet
  properties: {
    remoteVirtualNetwork: {
      id: secondaryVnet.id
    }
    allowVirtualNetworkAccess: true
    allowForwardedTraffic: true
    allowGatewayTransit: false
    useRemoteGateways: false
  }
}

resource secondaryToPrimaryVnetPeering 'Microsoft.Network/virtualNetworks/virtualNetworkPeerings@2022-01-01' = {
  name: 'vnetPeering-${resourceSuffixUID}'
  parent: secondaryVnet
  properties: {
    remoteVirtualNetwork: {
      id: primaryVnet.id
    }
    allowVirtualNetworkAccess: true
    allowForwardedTraffic: true
    allowGatewayTransit: false
    useRemoteGateways: false
  }
}

output primaryToSecondaryPeeringId string = primaryToSecondaryVnetPeering.id
output secondaryToPrimaryPeeringId string = secondaryToPrimaryVnetPeering.id
