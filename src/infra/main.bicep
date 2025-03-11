@description('The location of the service (API) resources.')
param serviceLocation string = resourceGroup().location

@description('The failover location of the service (API) resources.')
param secondaryServiceLocation string = ''

@description('The AKS node cluster configuration for the service API')
param aksConfig array

@description('The network configuration of the service API')
param networkConfig array

@description('The suffix to be used for the name of resources')
param resourceSuffixUID string = ''

@description('Specifies the cross-regional routing strategy. Allowed values are "active-active" and "active-passive".')
@allowed([
  'active-active'
  'active-passive'
  '' // keeping it empty in case of regular 1 region deployment
])
param crossRegionalRouting string = ''

var secondaryLocation = trim(secondaryServiceLocation) // trim to remove any tailing spaces
var isGeoReplicated = !empty(secondaryLocation)

// The app identity (service pods managed identity)
// Assigned to a service location, but used globally: https://learn.microsoft.com/en-us/entra/identity/managed-identities-azure-resources/managed-identities-faq#can-the-same-managed-identity-be-used-across-multiple-regions
resource managedIdentity 'Microsoft.ManagedIdentity/userAssignedIdentities@2018-11-30' = {
  name: 'app-identity-${resourceSuffixUID}'
  location: serviceLocation
}

// The list of regions where to deploy the service API resources.
// Currently containing the primary and secondary locations - in future can be extended to multiple regions.
var serviceDeploymentRegions = secondaryLocation != '' ? [serviceLocation, secondaryLocation] : [serviceLocation]

module monitoringStacks './monitoring/monitoringStack.bicep' = [
  for (region, idx) in serviceDeploymentRegions: {
    name: 'monitoringStack-${region}'
    params: {
      location: region
      resourceSuffixUID: '${region}-${resourceSuffixUID}'
    }
  }
]

// The network stack containing the VNet, subnets, and other network resources
module networkStacks './network/networkStack.bicep' = [
  for (region, idx) in serviceDeploymentRegions: {
    name: 'networkStack-${region}'
    params: {
      location: region
      resourceSuffixUID: '${region}-${resourceSuffixUID}'
      networkConfig: networkConfig[idx]
      workspaceId: monitoringStacks[idx].outputs.workspaceId
    }
  }
]

module networkPeerings './network/networkPeerings.bicep' = if (isGeoReplicated) {
  name: 'networkPeerings'
  params: {
    resourceSuffixUID: resourceSuffixUID
    primaryVnetName: networkStacks[0].outputs.vnetName
    secondaryVnetName: networkStacks[1].outputs.vnetName
  }
}


// The compute stack containing the AKS cluster and other compute resources
module computeStacks './compute/computeStack.bicep' = [
  for (region, idx) in serviceDeploymentRegions: {
    name: 'computeStack-${region}'
    params: {
      serviceLocation: region
      resourceSuffixUID: '${region}-${resourceSuffixUID}'
      networkConfig: networkConfig[idx]
      workspaceId: monitoringStacks[idx].outputs.workspaceId
      aksConfig: aksConfig[idx]
      appGatewaySubnetId: networkStacks[idx].outputs.appGatewaySubnetId
      vnetId: networkStacks[idx].outputs.vnetId
      vnetName: networkStacks[idx].outputs.vnetName
      aksSubnetId: networkStacks[idx].outputs.aksSubnetId
      infraSubnetId: networkStacks[idx].outputs.infraSubnetId
    }
    dependsOn: [
      networkStacks[idx]
      monitoringStacks[idx]
    ]
  }
]

// The storage stack containing the SQL, KeyVault, and Redis resources
module storageStack './storage/storageStack.bicep' = {
  name: 'storageStack'
  params: {
    // location-agnostic parameters
    resourceSuffixUID: resourceSuffixUID
    managedIdentityName: managedIdentity.name
    managedIdentityPrincipalId: managedIdentity.properties.principalId
    managedIdentityCliendId: managedIdentity.properties.clientId

    // primary location paramters
    primaryLocation: serviceLocation

    // The resources are mandatory to be hardcoded due to issue checking the size of the array dynamically in the expression.
    // "Directly referencing a resource or module collection isn't currently supported here. Apply an array indexer to the expression." - but the indexer can't be checked to prevent out of bound.
    // https://learn.microsoft.com/en-us/azure/azure-resource-manager/bicep/bicep-core-diagnostics#BCP144
    // EG: length(computeStacks) > 1 ? computeStacks[1].outputs.appGatewayIP : '' -> The language expression property array index '1' is out of bounds
    // Alternativelly to be considered to refactor the storageStack to work similar as the other modules.
    primaryLocationLogAnalyticsWorkspaceId: '/subscriptions/${subscription().subscriptionId}/resourceGroups/${resourceGroup().name}/providers/Microsoft.OperationalInsights/workspaces/insights-ws-${serviceLocation}-${resourceSuffixUID}'
    primaryLocationInfraSubnetId: '/subscriptions/${subscription().subscriptionId}/resourceGroups/${resourceGroup().name}/providers/Microsoft.Network/virtualNetworks/vnet-${serviceLocation}-${resourceSuffixUID}/subnets/InfraSubnet'
    primaryLocationAKSSubnetId: '/subscriptions/${subscription().subscriptionId}/resourceGroups/${resourceGroup().name}/providers/Microsoft.Network/virtualNetworks/vnet-${serviceLocation}-${resourceSuffixUID}/subnets/AKSSubnet'

    // secondary location parameters
    secondaryLocation: secondaryLocation
    secondaryLocationLogAnalyticsWorkspaceId: empty(secondaryLocation)
      ? ''
      : '/subscriptions/${subscription().subscriptionId}/resourceGroups/${resourceGroup().name}/providers/Microsoft.OperationalInsights/workspaces/insights-ws-${secondaryLocation}-${resourceSuffixUID}'
    secondaryLocationInfraSubnetId: empty(secondaryLocation)
      ? ''
      : '/subscriptions/${subscription().subscriptionId}/resourceGroups/${resourceGroup().name}/providers/Microsoft.Network/virtualNetworks/vnet-${secondaryLocation}-${resourceSuffixUID}/subnets/InfraSubnet'
    secondaryLocationAKSSubnetId: empty(secondaryLocation)
      ? ''
      : '/subscriptions/${subscription().subscriptionId}/resourceGroups/${resourceGroup().name}/providers/Microsoft.Network/virtualNetworks/vnet-${secondaryLocation}-${resourceSuffixUID}/subnets/AKSSubnet'
  }
  dependsOn: [
    networkStacks
    networkPeerings
    monitoringStacks
  ]
}


// Front Door routing resources
var frontDoorSkuName = 'Premium_AzureFrontDoor'

resource frontDoorProfile 'Microsoft.Cdn/profiles@2022-11-01-preview' = {
  name: 'cdn-profile-${resourceSuffixUID}'
  location: 'global'
  sku: {
    name: frontDoorSkuName
  }
  properties: {
    originResponseTimeoutSeconds: 90
  }
}

resource frontDoorEndpoint 'Microsoft.Cdn/profiles/afdEndpoints@2022-11-01-preview' = {
  name: 'afd-endpoint-${resourceSuffixUID}'
  parent: frontDoorProfile
  location: 'global'
  properties: {
    enabledState: 'Enabled'
  }
}

resource frontDoorOriginGroup 'Microsoft.Cdn/profiles/originGroups@2022-11-01-preview' = {
  name: 'default-origin-group'
  parent: frontDoorProfile
  properties: {
    loadBalancingSettings: {
      sampleSize: 4
      successfulSamplesRequired: 3
      additionalLatencyInMilliseconds: 50
    }
    healthProbeSettings: {
      probePath: '/api/live'
      probeRequestType: 'GET'
      probeProtocol: 'Http'
      probeIntervalInSeconds: 100
    }
  }
}

resource frontDoorOrigins 'Microsoft.Cdn/profiles/originGroups/origins@2022-11-01-preview' = [
  for (region, idx) in serviceDeploymentRegions: {
    name: 'default-origin-${region}'
    parent: frontDoorOriginGroup
    properties: {
      hostName: computeStacks[idx].outputs.appGatewayIP
      httpPort: 80
      httpsPort: 443
      originHostHeader: computeStacks[idx].outputs.appGatewayIP
      // active-passive: First region will be active (priority 1), the rest will be passive (priority > 1)
      // active-active: All regions have priority 1
      priority: crossRegionalRouting == 'active-passive' ? min(1 + idx, 5) : 1
      weight: 1000
      enabledState: 'Enabled'
      enforceCertificateNameCheck: false
    }
  }
]

resource frontDoorRoute 'Microsoft.Cdn/profiles/afdEndpoints/routes@2022-11-01-preview' = {
  name: 'default-route'
  parent: frontDoorEndpoint
  dependsOn: [
    frontDoorOrigins // This explicit dependency is required to ensure that the origin group is not empty when the route is created.
  ]
  properties: {
    originGroup: {
      id: frontDoorOriginGroup.id
    }
    supportedProtocols: [
      'Http'
      'Https'
    ]
    patternsToMatch: [
      '/*'
    ]
    forwardingProtocol: 'HttpOnly'
    linkToDefaultDomain: 'Enabled'
    httpsRedirect: 'Enabled'
    enabledState: 'Enabled'
  }
}

resource diagnosticLogs 'Microsoft.Insights/diagnosticSettings@2021-05-01-preview' = {
  name: frontDoorProfile.name
  scope: frontDoorProfile
  properties: {
    workspaceId: monitoringStacks[0].outputs.workspaceId // TODO: Consider using other workspaceID for global resources
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

var wafPolicyName = replace('waf${resourceSuffixUID}', '-', '')

resource frontdoorFirewallPolicy 'Microsoft.Network/FrontDoorWebApplicationFirewallPolicies@2022-05-01' = {
  name: wafPolicyName
  location: 'Global'
  sku: {
    name: frontDoorSkuName
  }
  properties: {
    managedRules: {
      managedRuleSets: [
        {
          ruleSetType: 'Microsoft_BotManagerRuleSet'
          ruleSetVersion: '1.1'
          ruleGroupOverrides: []
          exclusions: []
        }
      ]
    }
    policySettings: {
      enabledState: 'Enabled'
      mode: 'Prevention'
    }
  }
}
resource cdn_waf_security_policy 'Microsoft.Cdn/profiles/securitypolicies@2021-06-01' = {
  parent: frontDoorProfile
  name: wafPolicyName
  properties: {
    parameters: {
      wafPolicy: {
        id: frontdoorFirewallPolicy.id
      }
      associations: [
        {
          domains: [
            {
              id: frontDoorEndpoint.id
            }
          ]
          patternsToMatch: [
            '/*'
          ]
        }
      ]
      type: 'WebApplicationFirewall'
    }
  }
}

output frontDoorEndpointHostName string = frontDoorEndpoint.properties.hostName
