param grafanaParams object

targetScope = 'subscription'

resource rg 'Microsoft.Resources/resourceGroups@2020-10-01' = {
  name: grafanaParams.resourceGroup
  location: grafanaParams.location
}

module managedGrafana 'managedGrafana.bicep' = {
  name: 'managedGrafana'
  scope: rg
  params: { 
    name: grafanaParams.name
    sku: grafanaParams.sku
  }
}
