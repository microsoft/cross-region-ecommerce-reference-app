param location string
param resourceSuffixUID string

resource logAnalyticsWorkspace 'Microsoft.OperationalInsights/workspaces@2021-06-01' = {
  name: 'insights-ws-${resourceSuffixUID}'
  location: location
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

resource insights 'Microsoft.Insights/components@2020-02-02' = {
  name: 'insights-${resourceSuffixUID}'
  location: location
  kind: 'web'
  properties: {
    Application_Type: 'web'
    DisableLocalAuth: false
    ForceCustomerStorageForProfiler: false
    IngestionMode: 'LogAnalytics'
    publicNetworkAccessForIngestion: 'Enabled'
    publicNetworkAccessForQuery: 'Enabled'
    RetentionInDays: 30
    SamplingPercentage: json('100')
    WorkspaceResourceId: logAnalyticsWorkspace.id
  }
}

output appInsightsName string = insights.name
output appInsightsId string = insights.id
output workspaceId string = logAnalyticsWorkspace.id
output workspaceName string = logAnalyticsWorkspace.name
output connectionString string = logAnalyticsWorkspace.name
