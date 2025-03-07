// common parameters
param resourceSuffixUID string
param appManagedIdentityName string
param appManagedIdentityPrincipalId string
param redisZones array = ['1', '2', '3']
param keyVaultName string

var redisCacheSkuName = 'Premium'
var redisCacheFamilyName = 'P'
var redisCacheCapacity = 2

// primary location
param primaryLocation string
param primaryLocationInfraSubnetId string
param primaryLocationLogAnalyticsWorkspaceId string

// secondary location
param secondaryLocation string = ''
param secondaryLocationInfraSubnetId string = ''
param secondaryLocationLogAnalyticsWorkspaceId string

var isGeoReplicated = !empty(secondaryLocation)

var infraSubnetIds = isGeoReplicated
  ? [primaryLocationInfraSubnetId, secondaryLocationInfraSubnetId]
  : [primaryLocationInfraSubnetId]

var logAnalyticsWorkspaceIds = empty(secondaryLocation)
  ? [primaryLocationLogAnalyticsWorkspaceId]
  : [primaryLocationLogAnalyticsWorkspaceId, secondaryLocationLogAnalyticsWorkspaceId]

var locations = isGeoReplicated ? [primaryLocation, secondaryLocation] : [primaryLocation]

resource redisCaches 'Microsoft.Cache/redis@2024-11-01' = [
  for (location, idx) in locations: {
    name: 'redis-${location}-${resourceSuffixUID}'
    location: location
    properties: {
      redisVersion: '6.0'
      minimumTlsVersion: '1.2'
      sku: {
        name: redisCacheSkuName
        family: redisCacheFamilyName
        capacity: redisCacheCapacity
      }
      enableNonSslPort: false
      publicNetworkAccess: 'Disabled'
      redisConfiguration: {
        'maxmemory-reserved': '30'
        'maxfragmentationmemory-reserved': '30'
        'maxmemory-delta': '30'
        'aad-enabled': 'True'
      }
      subnetId: infraSubnetIds[idx]
    }
    // Zone redundancy is not supported for geo-replicated caches
    // https://learn.microsoft.com/en-us/azure/azure-cache-for-redis/cache-how-to-geo-replication#geo-replication-prerequisites
    zones: isGeoReplicated ? null : redisZones
  }
]

// Assign Data Contributor to our App Managed Identity
resource rbacAssignments 'Microsoft.Cache/redis/accessPolicyAssignments@2023-08-01' = [
  for (location, idx) in locations: {
    parent: redisCaches[idx]
    name: appManagedIdentityName
    properties: {
      accessPolicyName: 'Data Contributor'
      objectId: appManagedIdentityPrincipalId
      objectIdAlias: appManagedIdentityName
    }
  }
]

resource diagnosticLogs 'Microsoft.Insights/diagnosticSettings@2021-05-01-preview' = [
  for (location, idx) in locations: {
    name: redisCaches[idx].name
    scope: redisCaches[idx]
    properties: {
      #disable-next-line use-resource-id-functions
      workspaceId: logAnalyticsWorkspaceIds[idx]
      logs: [
        //{
        //  categoryGroup: 'audit'
        //  enabled: true
        //}
        //{
        //  categoryGroup: 'allLogs'
        //  enabled: true
        //}
      ]
      metrics: [
        {
          category: 'AllMetrics'
          enabled: true
        }
      ]
    }
  }
]

resource redisCacheLink 'Microsoft.Cache/Redis/linkedServers@2024-11-01' = if (isGeoReplicated) {
  parent: redisCaches[0]
  name: redisCaches[1].name
  properties: {
    linkedRedisCacheId: redisCaches[1].id
    linkedRedisCacheLocation: secondaryLocation
    serverRole: 'Secondary'
  }
  dependsOn: [redisCaches, rbacAssignments, diagnosticLogs]
}

// put redis properties into key vault
resource keyVault 'Microsoft.KeyVault/vaults@2021-11-01-preview' existing = {
  name: keyVaultName
}

resource redisEndpointSecret 'Microsoft.KeyVault/vaults/secrets@2023-07-01' = {
  parent: keyVault
  name: 'redis-endpoint'
  properties: {
    value: isGeoReplicated ? '${redisCaches[0].name}.geo.redis.cache.windows.net' : redisCaches[0].properties.hostName
  }
}

output redisCacheId string = redisCaches[0].id
output redisCacheName string = redisCaches[0].name
