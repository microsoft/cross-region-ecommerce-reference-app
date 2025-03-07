// location-agnostic parameters
@description('A unique identifier for resource naming.')
param resourceSuffixUID string

@description('The managed identity name.')
param managedIdentityName string

@description('The managed identity principal ID.')
param managedIdentityPrincipalId string

@description('The managed identity client ID.')
param managedIdentityCliendId string

// primary location parameters
@description('The primary location for the resources.')
param primaryLocation string

@description('The primary workspace ID of the Log Analytics workspace.')
param primaryLocationLogAnalyticsWorkspaceId string

@description('The primary infra subnet ID.')
param primaryLocationInfraSubnetId string

@description('The primary AKS subnet ID.')
param primaryLocationAKSSubnetId string

// secondary location parameters
@description('The secondary location for the resources.')
param secondaryLocation string

@description('The secondary workspace ID of the Log Analytics workspace.')
param secondaryLocationLogAnalyticsWorkspaceId string

@description('The secondary infra subnet ID.')
param secondaryLocationInfraSubnetId string

@description('The secondary AKS subnet ID.')
param secondaryLocationAKSSubnetId string

module keyVault './keyvault.bicep' = {
  name: 'keyvault'
  params: {
    primaryLocation: primaryLocation
    primaryLocationInfraSubnetId: primaryLocationInfraSubnetId
    primaryLocationAKSSubnetId: primaryLocationAKSSubnetId
    secondaryLocation: secondaryLocation
    secondaryLocationInfraSubnetId: secondaryLocationInfraSubnetId
    secondaryLocationAKSSubnetId: secondaryLocationAKSSubnetId
    resourceSuffixUID: resourceSuffixUID
    workspaceId: primaryLocationLogAnalyticsWorkspaceId
  }
}

module keyVaultAppRbacGrants './rbacGrantKeyVault.bicep' = {
  name: 'rbacGrantsKeyVault'
  params: {
    keyVaultName: keyVault.outputs.keyvaultName
    appManagedIdentityPrincipalId: managedIdentityPrincipalId
  }
}

module sqlDatabase './azureSqlDatabase.bicep' = {
  name: 'sqlDatabase'
  params: {
    primaryLocation: primaryLocation
    secondaryLocation: secondaryLocation
    primaryLocationInfraSubnetId: primaryLocationInfraSubnetId
    primaryLocationAKSSubnetId: primaryLocationAKSSubnetId
    secondaryLocationInfraSubnetId: secondaryLocationInfraSubnetId
    secondaryLocationAKSSubnetId: secondaryLocationAKSSubnetId
    resourceSuffixUID: resourceSuffixUID
    primaryLocationLogAnalyticsWorkspaceId: primaryLocationLogAnalyticsWorkspaceId
    secondaryLocationLogAnalyticsWorkspaceId: secondaryLocationLogAnalyticsWorkspaceId
    managedIdentityClientId: managedIdentityCliendId
    azureSqlZoneRedundant: true
    keyVaultName: keyVault.outputs.keyvaultName
  }
}

module redis './redisCache.bicep' = {
  name: 'redis'
  params: {
    primaryLocation: primaryLocation
    primaryLocationInfraSubnetId: primaryLocationInfraSubnetId
    secondaryLocation: secondaryLocation
    secondaryLocationInfraSubnetId: secondaryLocationInfraSubnetId
    resourceSuffixUID: resourceSuffixUID
    primaryLocationLogAnalyticsWorkspaceId: primaryLocationLogAnalyticsWorkspaceId
    secondaryLocationLogAnalyticsWorkspaceId: secondaryLocationLogAnalyticsWorkspaceId
    appManagedIdentityName: managedIdentityName
    appManagedIdentityPrincipalId: managedIdentityPrincipalId
    keyVaultName: keyVault.outputs.keyvaultName
  }
}

output keyvaultName string = keyVault.outputs.keyvaultName
