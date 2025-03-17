// common parameters
param resourceSuffixUID string
param keyVaultName string
param managedIdentityClientId string
param azureSqlZoneRedundant bool

// primary location
param primaryLocation string
param primaryLocationInfraSubnetId string
param primaryLocationAKSSubnetId string
param primaryLocationLogAnalyticsWorkspaceId string

// secondary location
param secondaryLocation string = ''
param secondaryLocationInfraSubnetId string = ''
param secondaryLocationAKSSubnetId string = ''
param secondaryLocationLogAnalyticsWorkspaceId string

var infraSubnetIds = empty(secondaryLocation)
  ? [primaryLocationInfraSubnetId]
  : [primaryLocationInfraSubnetId, secondaryLocationInfraSubnetId]

var locations = empty(secondaryLocation) ? [primaryLocation] : [primaryLocation, secondaryLocation]

resource sqlServerPrimary 'Microsoft.Sql/servers@2024-05-01-preview' = {
  name: 'sql-${primaryLocation}-${resourceSuffixUID}'
  location: primaryLocation
  properties: {
    // setting up as AAD group where members can do admin via AAD login 
    administrators: {
      azureADOnlyAuthentication: true
      login: 'ManagedIdentityAdmin'
      administratorType: 'ActiveDirectory'
      sid: managedIdentityClientId
      tenantId: subscription().tenantId
      principalType: 'Application'
    }
    minimalTlsVersion: '1.2'
    publicNetworkAccess: 'Enabled'  // Enabled for selected network from vnet rule
    version: '12.0'
  }

  resource infraVnetRule 'virtualNetworkRules@2024-05-01-preview' = {
    name: 'primary-infra-vnet-rule'
    properties: {
      virtualNetworkSubnetId: primaryLocationInfraSubnetId
    }
  }

  resource AKSVnetRule 'virtualNetworkRules@2024-05-01-preview' = {
    name: 'primary-aks-vnet-rule'
    properties: {
      virtualNetworkSubnetId: primaryLocationAKSSubnetId
    }
  }
}

resource sqlServerSecondary 'Microsoft.Sql/servers@2024-05-01-preview' = if (!empty(secondaryLocation)) {
  name: 'sql-${secondaryLocation}-${resourceSuffixUID}'
  location: secondaryLocation
  properties: {
    // setting up as AAD group where members can do admin via AAD login 
    administrators: {
      azureADOnlyAuthentication: true
      login: 'ManagedIdentityAdmin'
      administratorType: 'ActiveDirectory'
      sid: managedIdentityClientId
      tenantId: subscription().tenantId
      principalType: 'Application'
    }
    minimalTlsVersion: '1.2'
    publicNetworkAccess: 'Enabled'  // Enabled for selected network from vnet rule
    version: '12.0'
  }

  resource infraVnetRule 'virtualNetworkRules@2024-05-01-preview' = {
    name: 'secondary-infra-vnet-rule'
    properties: {
      virtualNetworkSubnetId: secondaryLocationInfraSubnetId
    }
  }

  resource AKSVnetRule 'virtualNetworkRules@2024-05-01-preview' = {
    name: 'secondary-aks-vnet-rule'
    properties: {
      virtualNetworkSubnetId: secondaryLocationAKSSubnetId
    }
  }
}

var sqlAppDatabaseName = 'az-ref-app'
var sqlCatalogName = sqlAppDatabaseName
var skuTierName = 'Premium'
var dtuCapacity = 125
var requestedBackupStorageRedundancy = empty(secondaryLocation) ? 'Local' : 'Geo'
var readScale = 'Enabled'

resource sqlDatabase 'Microsoft.Sql/servers/databases@2024-05-01-preview' = {
  parent: sqlServerPrimary
  name: 'az-ref-app'
  location: primaryLocation
  tags: {
    displayName: sqlCatalogName
  }
  sku: {
    name: skuTierName
    tier: skuTierName
    capacity: dtuCapacity
  }
  properties: {
    requestedBackupStorageRedundancy: requestedBackupStorageRedundancy
    readScale: readScale
    zoneRedundant: azureSqlZoneRedundant
  }
}


/*
// To allow applications hosted inside Azure to connect to your SQL server, Azure connections must be enabled. 
// To enable Azure connections, there must be a firewall rule with starting and ending IP addresses set to 0.0.0.0. 
// This recommended rule is only applicable to Azure SQL Database.
// Ref: https://learn.microsoft.com/azure/azure-sql/database/firewall-configure?view=azuresql#connections-from-inside-azure
resource allowAllWindowsAzureIps 'Microsoft.Sql/servers/firewallRules@2021-11-01-preview' = {
  name: 'AllowAllWindowsAzureIps'
  parent: sqlServer
  properties: {
    endIpAddress: '0.0.0.0'
    startIpAddress: '0.0.0.0'
  }
}

*/

resource failoverGroup 'Microsoft.Sql/servers/failoverGroups@2023-05-01-preview' = if (!empty(secondaryLocation)) {
  name: 'failover-group-${resourceSuffixUID}'
  parent: sqlServerPrimary
  properties: {
    readWriteEndpoint: {
      failoverPolicy: 'Manual'
    }
    databases: [
      sqlDatabase.id
    ]
    partnerServers: [
      {
        id: sqlServerSecondary.id
      }
    ]
  }
}

resource diagnosticLogsPrimary 'Microsoft.Insights/diagnosticSettings@2021-05-01-preview' = {
  name: sqlDatabase.name
  scope: sqlDatabase
  properties: {
    workspaceId: primaryLocationLogAnalyticsWorkspaceId
    logs: [
      {
        categoryGroup: 'allLogs'
        enabled: true
      }
    ]
    metrics: [
      {
        category: 'Basic'
        enabled: true
      }
      {
        category: 'InstanceAndAppAdvanced'
        enabled: true
      }
      {
        category: 'WorkloadManagement'
        enabled: true
      }
    ]
  }
}


//add a 2 min wait to allow the failover group to create the secondary database. Using deployment script with 2 min wait time

resource waitScript 'Microsoft.Resources/deploymentScripts@2023-08-01' = if (!empty(secondaryLocation)) {
  name: 'wait-for-failover-group'
  location: primaryLocation
  kind: 'AzurePowerShell'
  properties: {
    azPowerShellVersion: '12.3'
    scriptContent: '''
      Start-Sleep -Seconds 120
    '''
    cleanupPreference: 'Always'
    retentionInterval: 'PT1H'
  }
  dependsOn: [
    failoverGroup
  ]
}


resource sqlDatabaseSecondary 'Microsoft.Sql/servers/databases@2023-05-01-preview' existing = if (!empty(secondaryLocation)) {
  parent: sqlServerSecondary
  name: sqlDatabase.name
  dependsOn: [
    failoverGroup
    waitScript
  ]
}

resource diagnosticLogsSecondary 'Microsoft.Insights/diagnosticSettings@2021-05-01-preview' = if (!empty(secondaryLocation)) {
  name: sqlDatabase.name
  scope: sqlDatabaseSecondary
  properties: {
    workspaceId: secondaryLocationLogAnalyticsWorkspaceId
    logs: [
      {
        categoryGroup: 'allLogs'
        enabled: true
      }
    ]
    metrics: [
      {
        category: 'Basic'
        enabled: true
      }
      {
        category: 'InstanceAndAppAdvanced'
        enabled: true
      }
      {
        category: 'WorkloadManagement'
        enabled: true
      }
    ]
  }
  dependsOn: [
    failoverGroup
  ]
}

// put connection properties into key vault
resource keyVault 'Microsoft.KeyVault/vaults@2021-11-01-preview' existing = {
  name: keyVaultName
}
// application database name
resource sqlAppDatabaseNameSecret 'Microsoft.KeyVault/vaults/secrets@2023-07-01' = {
  parent: keyVault
  name: 'sql-app-database-name'
  properties: {
    value: sqlAppDatabaseName
  }
}
// Azure SQL Endpoints (auth is via AAD)
resource AzureSqlEndpointSecret 'Microsoft.KeyVault/vaults/secrets@2023-07-01' = {
  parent: keyVault
  name: 'azure-sql-endpoint'
  properties: {
    value: empty(secondaryLocation)
      ? sqlServerPrimary.properties.fullyQualifiedDomainName
      : '${failoverGroup.name}${environment().suffixes.sqlServerHostname}'
  }
}

output sqlServerFqdn string = empty(secondaryLocation)
  ? sqlServerPrimary.properties.fullyQualifiedDomainName
  : '${failoverGroup.name}${environment().suffixes.sqlServerHostname}'
output sqlCatalogName string = sqlCatalogName
output sqlDatabaseName string = sqlDatabase.name
