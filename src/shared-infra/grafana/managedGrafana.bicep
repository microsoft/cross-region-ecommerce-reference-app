@description('Managed Grafana Resource Name')
param name string

@description('Managed Grafana Resource SKU')
param sku string

resource managedGrafana 'Microsoft.Dashboard/grafana@2023-09-01' = {
  name: name
  location: resourceGroup().location
  sku: {
    name: sku
  }
  identity: {
    type: 'SystemAssigned'
  }
  properties:{
    zoneRedundancy:'Enabled'
  }
}

