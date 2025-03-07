@description('The location of the client (JMeter) resources.')
param clientLocation string = 'westus3'

@description('''
  The name of the Aurora data plane manifest name. Represents the Aurora "check tool"
  to provision and run on dedicated VMs. If none provided, skip the creation
  of the data plane infrastructure required by Aurora long-haul workloads.
  Usually provided when deploying from the Aurora manifest.
''')
param manifestName string = ''

@description('The suffix to be used for the name of resources')
param resourceSuffixUID string = ''

resource clientLogAnalyticsWorkspace 'Microsoft.OperationalInsights/workspaces@2021-06-01' = {
  name: 'client-ws-${resourceSuffixUID}'
  location: clientLocation
  properties: {
    retentionInDays: 90
    sku: {
      name: 'PerGB2018'
    }
  }
  tags: {
    'Privacy.Asset.NonPersonal': '{}'
  }
}

module azureLoadTesting './azureLoadTesting.bicep' = {
  name: 'azureLoadTesting'
  params: {
    resourceSuffixUID: resourceSuffixUID
    clientLocation: clientLocation
    logAnalyticsWorkspaceID: clientLogAnalyticsWorkspace.id
  }
}

module auroraDataPlane './auroraDataPlane.bicep' = if (!empty(trim(manifestName))) {
  name: 'auroraDataPlane'
  params: {
    resourceSuffixUID: resourceSuffixUID
    azureLoadTestingResourceName: azureLoadTesting.outputs.loadTestingResourceName
    manifestName: manifestName
    regions: [clientLocation] // TODO: Currently use the client location as it's guaranteed to be a stable region. Update this to be configurable from Aurora manifest
    configFileContents: {
      resourceGroupName: resourceGroup().name
      loadTestResourceName: azureLoadTesting.outputs.loadTestingResourceName
      loadTestId: loadYamlContent('../../load/load-test-config.yaml').testId
      appInsightsResourceName: azureLoadTesting.outputs.loadTestingAppInsightsResourceName
    }
  }
}

output loadTestingAppInsightsConnection string = azureLoadTesting.outputs.loadTestingAppInsightsConnection
output loadTestingResourceName string = azureLoadTesting.outputs.loadTestingResourceName
output logAnalyticsWorkspaceId string = clientLogAnalyticsWorkspace.id
