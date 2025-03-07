param resourceSuffixUID string
param clientLocation string
param logAnalyticsWorkspaceID string

// The managed identity for AzureLoadTesting
resource managedIdentity 'Microsoft.ManagedIdentity/userAssignedIdentities@2018-11-30' = {
  name: 'load-testing-identity-${resourceSuffixUID}'
  location: clientLocation
}

resource loadTesting 'Microsoft.LoadTestService/loadTests@2022-12-01' = {
  name: 'load-testing-${resourceSuffixUID}'
  location: clientLocation
  identity: {
    type: 'UserAssigned'
    userAssignedIdentities: {
      '${managedIdentity.id}': {}
    }
  }
  properties: {
    description: 'refapp-load-testing'
  }
}

resource loadTestingAppInsights 'Microsoft.Insights/components@2020-02-02' = {
  name: 'load-testing-app-insights-${resourceSuffixUID}'
  location: clientLocation
  kind: 'load-testing'
  properties: {
    Application_Type: 'other'
    WorkspaceResourceId: logAnalyticsWorkspaceID
  }
}

output loadTestingResourceName string = loadTesting.name
output loadTestingAppInsightsResourceName string = loadTestingAppInsights.name
output loadTestingAppInsightsConnection string = loadTestingAppInsights.properties.ConnectionString
