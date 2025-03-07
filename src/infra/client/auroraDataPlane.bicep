@description('''
  The suffix of the unique identifier for the resources of the current deployment.
  Used to avoid name collisions and to link resources part of the same deployment together.
''')
param resourceSuffixUID string

@description('The name of the Azure Load Testing resource to which the data plane VM(s) will be associated with.')
param azureLoadTestingResourceName string

@description('The size of the data plane VM.')
param vmSize string = 'Standard_D2s_v3'

@description('The name of the data plane manifest associated with the VM(s).')
param manifestName string

@description('''
  The list of regions where to deploy the data plane infrastructure.
  For each region, a separate VNet with a VM will be deployed, along with all other necessary resources (VNet, NSG, NIC etc.).
  Use region names, not display names. E.g. use "eastus" instead of "East US"
''')
param regions string[] = ['westus3']

@description('''
  If given, a JSON file with the contents of this JSON parameter will reside
  inside each of the data plane VMs, under the "/etc/config.json" path.
''')
param configFileContents object = {}

@description('The Linux root user name of the data plane VM.')
var vmAdminUserName = 'azureuser'

@description('''
  View, create, update, delete and execute load tests. View and list load test resources but can not make any changes.
  See: https://learn.microsoft.com/en-us/azure/role-based-access-control/built-in-roles/devops#load-test-contributor
''')
var loadTestContributorRoleDefinitionId = resourceId(
  'Microsoft.Authorization/roleDefinitions',
  '749a398d-560b-491b-bb21-08924219302e'
)

@description('The list of resource configurations for each region.')
var resourceConfigs = [
  for (region, idx) in regions: {
    region: region
    vmName: 'dataplane-vm-${resourceSuffixUID}-${replace(region, ' ', '')}'
    vmSshPublicKeyName: 'dataplane-vm-ssh-key-${resourceSuffixUID}-${replace(region, ' ', '')}'
    vmNetworkInterfaceName: 'dataplane-nic-${resourceSuffixUID}-${replace(region, ' ', '')}'
    vmExtensionName: 'dataplane-vm-extension-${resourceSuffixUID}-${replace(region, ' ', '')}'
    vNet: {
      name: 'dataplane-vnet-${resourceSuffixUID}-${replace(region, ' ', '')}'
      addressSpace: '10.${idx}.0.0/16'
      subnet: {
        name: 'dataplane-subnet-${resourceSuffixUID}-${replace(region, ' ', '')}'
        addressSpace: '10.${idx}.0.0/24'
      }
    }
    nsgName: 'dataplane-nsg-${resourceSuffixUID}-${replace(region, ' ', '')}'
  }
]

// One user-assigned identity for all data plane VMs
resource dataPlaneVMIdentity 'Microsoft.ManagedIdentity/userAssignedIdentities@2023-01-31' = {
  name: 'dataplane-vm-identity-${resourceSuffixUID}'
  location: regions[0]
}

// One network configuration per VM (per region)
resource dataPlaneNSG 'Microsoft.Network/networkSecurityGroups@2023-11-01' = [
  for resourceConfig in resourceConfigs: {
    name: resourceConfig.nsgName
    location: resourceConfig.region
    properties: {
      securityRules: []
    }
  }
]

resource dataPlaneVNet 'Microsoft.Network/virtualNetworks@2023-11-01' = [
  for resourceConfig in resourceConfigs: {
    name: resourceConfig.vNet.name
    location: resourceConfig.region
    properties: {
      addressSpace: {
        addressPrefixes: [
          resourceConfig.vNet.addressSpace
        ]
      }
    }
  }
]

resource dataPlaneSubnet 'Microsoft.Network/virtualNetworks/subnets@2023-11-01' = [
  for (resourceConfig, idx) in resourceConfigs: {
    parent: dataPlaneVNet[idx]
    name: resourceConfig.vNet.subnet.name
    properties: {
      addressPrefix: resourceConfig.vNet.subnet.addressSpace
      networkSecurityGroup: {
        id: dataPlaneNSG[idx].id
      }
    }
  }
]

resource dataPlaneVMNetworkInterface 'Microsoft.Network/networkInterfaces@2023-11-01' = [
  for (resourceConfig, idx) in resourceConfigs: {
    name: resourceConfig.vmNetworkInterfaceName
    location: resourceConfig.region
    properties: {
      ipConfigurations: [
        {
          name: 'ipconfig1'
          properties: {
            privateIPAllocationMethod: 'Dynamic'
            subnet: {
              id: dataPlaneSubnet[idx].id
            }
          }
        }
      ]
    }
  }
]

// Create the data plane VMs themselves, one per region
resource publicKey 'Microsoft.Compute/sshPublicKeys@2023-09-01' existing = {
  name: 'aurora-dataplane-pubkey'
  scope: resourceGroup('rg-azref-core-devops-1es-dev')
}

resource dataPlaneVM 'Microsoft.Compute/virtualMachines@2023-09-01' = [
  for (resourceConfig, idx) in resourceConfigs: {
    name: resourceConfig.vmName
    location: resourceConfig.region
    tags: {
      DataplaneDriver: manifestName
    }
    zones: ['1']
    identity: {
      type: 'UserAssigned'
      userAssignedIdentities: {
        '${dataPlaneVMIdentity.id}': {}
      }
    }
    properties: {
      hardwareProfile: {
        vmSize: vmSize
      }
      networkProfile: {
        networkInterfaces: [
          {
            id: dataPlaneVMNetworkInterface[idx].id
            properties: {
              deleteOption: 'Delete'
            }
          }
        ]
      }
      storageProfile: {
        osDisk: {
          createOption: 'FromImage'
          diskSizeGB: 30
          managedDisk: {
            storageAccountType: 'StandardSSD_ZRS'
          }
        }
        imageReference: {
          publisher: 'Canonical'
          offer: '0001-com-ubuntu-server-jammy'
          sku: '22_04-LTS'
          version: 'latest'
        }
      }
      osProfile: {
        computerName: take(resourceConfig.vmName, 64)
        #disable-next-line adminusername-should-not-be-literal
        adminUsername: vmAdminUserName
        allowExtensionOperations: true
        linuxConfiguration: {
          disablePasswordAuthentication: true
          provisionVMAgent: true
          ssh: {
            publicKeys: [
              {
                keyData: publicKey.properties.publicKey
                path: '/home/${vmAdminUserName}/.ssh/authorized_keys'
              }
            ]
          }
        }
      }
    }
  }
]

// Write, to each VM, the contents of the "configFileContents" parameter to "/etc/config.json"
var configFileContentsWithDefaults = union(
  {
    IdentityClientId: dataPlaneVMIdentity.properties.clientId
  },
  configFileContents
)

resource vmExtension 'Microsoft.Compute/virtualMachines/extensions@2023-09-01' = [
  for (resourceConfig, idx) in resourceConfigs: if (!empty(configFileContents)) {
    parent: dataPlaneVM[idx]
    name: resourceConfig.vmExtensionName
    location: resourceConfig.region
    properties: {
      publisher: 'Microsoft.Azure.Extensions'
      type: 'CustomScript'
      typeHandlerVersion: '2.1'
      autoUpgradeMinorVersion: true
      protectedSettings: {
        commandToExecute: 'echo "${json(string(configFileContentsWithDefaults))}" > /etc/config.json'
      }
    }
  }
]

// Assign the required roles to the data plane VMs identity (shared across all VMs)
resource azureLoadTesting 'Microsoft.LoadTestService/loadTests@2022-12-01' existing = {
  name: azureLoadTestingResourceName
}

resource dataPlaneLoadTestContributorRoleAssignment 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(loadTestContributorRoleDefinitionId, resourceSuffixUID)
  scope: azureLoadTesting
  properties: {
    roleDefinitionId: loadTestContributorRoleDefinitionId
    principalId: dataPlaneVMIdentity.properties.principalId
    principalType: 'ServicePrincipal'
  }
}
