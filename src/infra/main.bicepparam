using 'main.bicep'

param aksConfig = [
  // Config for Region1
  {
    sharedAcrResourceGroupName: 'rg-azref-shared'
    sharedAcrName: 'azrefsharedlz2a'
    systemNodeCount: 3
    userNodeCount: 3
    userMinNodeCount: 3
    userMaxNodeCount: 6
    maxUserPodsCount: 10
    nodeVMSize: 'standard_d4_v5'
    nodeOsSKU: 'Ubuntu'
    availabilityZones: ['1', '2', '3']
  }
  // Config for Region2
  {
    sharedAcrResourceGroupName: 'rg-azref-shared'
    sharedAcrName: 'azrefsharedlz2a'
    systemNodeCount: 3
    userNodeCount: 3
    userMinNodeCount: 3
    userMaxNodeCount: 6
    maxUserPodsCount: 10
    nodeVMSize: 'standard_d4_v5'
    nodeOsSKU: 'Ubuntu'
    availabilityZones: ['1', '2', '3']
  }
]

param networkConfig = [
  // Config for Region1
  {
    vnet: {
      cidr: '10.0.0.0/22'
    }
    subnets: {
      DnsResolverSubnet: {
        cidr: '10.0.0.32/27'
      }
      AppGatewaySubnet: {
        cidr: '10.0.1.0/24'
      }
      InfraSubnet: {
        cidr: '10.0.2.0/24'
      }
      AKSSubnet: {
        cidr: '10.0.3.0/24'
      }
    }
    dnsResolverPrivateIP: '10.0.0.40'
    loadBalancerPrivateIP: '10.0.3.250'
  }
  // Config for Region2
  {
    vnet: {
      cidr: '10.0.4.0/22'
    }
    subnets: {
      DnsResolverSubnet: {
        cidr: '10.0.4.32/27'
      }
      AppGatewaySubnet: {
        cidr: '10.0.5.0/24'
      }
      InfraSubnet: {
        cidr: '10.0.6.0/24'
      }
      AKSSubnet: {
        cidr: '10.0.7.0/24'
      }
    }
    dnsResolverPrivateIP: '10.0.4.40'
    loadBalancerPrivateIP: '10.0.7.250'
  }
]
