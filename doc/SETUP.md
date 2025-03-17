# Setting up the Cross-Region ECommerce Application

The Cross-Region ECommerce Reference Application is a synthetic workload that mirrors a simple, bare-bones, e-commerce platform. The purpose of it is to demonstrate how to use Azure Resiliency best practices to achieve availability during regional outages or components outages.

## Getting Started

The automated deployment is designed to work with Linux/MACOS/WSL as all scripts are written in bash. Before running the deployment, the following prerequisites have to be met:

* Install Az Cli <https://learn.microsoft.com/en-us/cli/azure/install-azure-cli-linux>

* Install docker <https://docs.docker.com/engine/install/ubuntu/> or <https://docs.docker.com/desktop/wsl/>

* Azure subscription where you have owner permissions

## Deploy test App

Clone the git repo

`git clone https://github.com/microsoft/cross-region-ecommerce-reference-app`

Login using Az Cli: `az login` (or any other variation, depending how you authenticate, e.g. --use-device-code)

Select a subscription where you have owner permissions

Ensure the OperationsManagement resource provider is registered

`az provider register --namespace 'Microsoft.OperationsManagement'`

### Deploy

Deploy using:

`./1-deploy-service.sh --service-location=primary-region --secondary-service-location=secondary-region`

Region code mapping can be found by running: `az account list-locations -o table`

The output format looks like this:

| DisplayName  | Name       | RegionalDisplayName         |
|--------------|------------|-----------------------------|
| East US      | eastus     | (US) East US                |
| West Europe  | westeurope | (Europe) West Europe        |

The script will take the name (e.g. westus, westeurope) as input.

You can customize deployment options such as the capacity of the AKS clusters and the cross regional routing stategy using parameters.

We have two AKS configurations located in `src/infra/config`, namely ***full*** and ***reduced***. The primary AKS cluster uses the ***full*** configuration by default and the secondary one defaults to the ***reduced*** configuration.
To change this you can specify the `--primary-aks-capacity` and `--secondary-aks-capacity` arguments.

The routing strategy can be specified using the `--cross-regional-routing` argument. The allowed values are ***active-active*** and ***active-passive*** and this determines wether the traffic is distributed evenly between regions (active-active) or if the primary one has priority over the secondary one (active-passive). The default configuration is ***active-passive***.
### Switchover

Start the Switchover procedure that migrates the services to the secondary region:
`./2-switchover.sh -rg=rg-name --from=primary-region --to=secondary-region`

Find more info abuot the switchover in the [switchover document](./SWITCHOVER.md).

The app saves the resource group where everything was deployed in a .env file which will be cleand-up at the end.

### Cleanup

To clean up the deployed resources:

`./3-cleanup.sh -rg=rg-name`

The cleanup script deletes the resource group created. But before doing that, it removes the Redis cache link as it would prevent the resource group deletion.
