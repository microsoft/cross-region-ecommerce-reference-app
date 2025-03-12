#!/usr/bin/env bash

# Exit on errors
set -o errexit -o pipefail -o noclobber
SCRIPT_PATH=$( cd "$(dirname "${BASH_SOURCE[0]}")" ; pwd -P )

ORIGINAL_ARGS="$@"

# Parse command line arguments
for ARG in "$@"; do
  case $ARG in
    -sl=*|--service-location=*)
      SERVICE_LOCATION="${ARG#*=}"
      shift
      ;;
    -h|--help)
      echo "
Usage: $0 [-rg=rg-name] [-sl=service-location] [--what-if]

  -rg, --resource-group                 Name of the existing resource group to deploy to. Takes precedence over service location
  -sl, --service-location               Location to deploy the service to. A new resource group will be created in this location if no resource group is provided. If a resource group is provided,
                                                this is ignored and the location of the resource group will be used
  -ssl, --secondary-service-location    Location to deploy the secondary service to. Required for geo-replicated deployments
  -pac, --primary-aks-capacity          Capacity configuration for the primary AKS cluster. Options: full, reduced. Default: full
  -sac, --secondary-aks-capacity        Capacity configuration for the secondary AKS cluster. Options: full, reduced. Default: reduced
  -crr, --cross-regional-routing        Specify the routing strategy between regions
  --manifest-name                       Name of the Aurora data-plane manifest to deploy. Default: no manifest deployed. Skips the deployment of the Aurora data-plane VMs
  --what-if                             Show what would happen if the deployment were run, but do not actually run it
  -h, --help                            Show this help message

Examples:
  $0 -rg=rg-name -cl=eastus -pac=full -sac=reduced
  $0 -sl=eastus -cl=westus3 -pac=full -sac=full
"
      exit 0
      ;;
    *)
      ;;
  esac
done


# Validate resource group and service location. Generate resource group name if not provided
if [ -z $RESOURCE_GROUP_NAME ]; then
  if [ -z $SERVICE_LOCATION ]; then
    echo "No resource group or service location provided. Provide at least one. E.g. '$0 -rg=rg-name' or '$0 -sl=eastus'. Run with '--help' for more information" >&2
    exit 1
  fi

  # No resource group provided, but service location is provided. Create new RG in given location
  GUID=$(uuidgen)
  USER_ALIAS="${REQUESTED_FOR:-$(whoami)}"
  USER_ALIAS=${USER_ALIAS%@*} 
  USER_ALIAS=${USER_ALIAS##*\\}

  RESOURCE_GROUP_NAME="refapp-${USER_ALIAS}-${GUID}"
  RESOURCE_GROUP_NAME="${RESOURCE_GROUP_NAME:0:30}" # Keep first 30 characters - due to naming length limitations for some resources

  echo "Resource group not provided, deploying to new resource group: '$RESOURCE_GROUP_NAME'"
  az group create --name $RESOURCE_GROUP_NAME --location $SERVICE_LOCATION
else
  echo "Deploying to existing resource group '$RESOURCE_GROUP_NAME'"
  SERVICE_LOCATION=$(az group show --name $RESOURCE_GROUP_NAME --query location -o tsv)
fi

# Deploy the infrastructure
bash $SCRIPT_PATH/src/infra/deploy.sh $ORIGINAL_ARGS -rg=$RESOURCE_GROUP_NAME


echo "Fetching ACR URI and Id"

ACR_URI=$(az acr list --resource-group $RESOURCE_GROUP_NAME --query "[0].loginServer" -o tsv)
ACR_ID=$(az acr list --resource-group $RESOURCE_GROUP_NAME --query "[0].id" -o tsv)
LOGGED_IN_USER=$(az ad signed-in-user show --query "id" -o tsv)
echo "ACR URI: $ACR_URI"


echo "Adding Container Registry Repository Contributor role to user"

az role assignment create --assignee "$LOGGED_IN_USER" \
        --role "Container Registry Repository Contributor" \
        --scope "$ACR_ID"


echo "Adding AKS Azure Kubernetes Service RBAC Cluster Admin to user"
AKS_ID=$(az aks list --resource-group $RESOURCE_GROUP_NAME --query "[0].id" -o tsv)

az role assignment create --assignee "$LOGGED_IN_USER" \
        --role "Azure Kubernetes Service RBAC Cluster Admin" \
        --scope "$AKS_ID"


echo "Push the image to ACR"

bash $SCRIPT_PATH/src/app/Api/push-image.sh -tag=latest -acr=$ACR_URI

echo "Deploy AKS services to cluster"

bash $SCRIPT_PATH/src/aks/aksdeployment/deploy.sh -rg=$RESOURCE_GROUP_NAME

echo "Fetching Azure Front Door endpoint"
FRONT_DOOR_PROFILE=$(az afd profile list --resource-group $RESOURCE_GROUP_NAME --query "[0].name" -o tsv)
FRONT_DOOR_HOSTNAME=$(az afd endpoint list --profile-name $FRONT_DOOR_PROFILE --resource-group $RESOURCE_GROUP_NAME --query "[0].hostName" -o tsv)

echo "Health check for $FRONT_DOOR_HOSTNAME"

bash $SCRIPT_PATH/tests/run-health-checks.sh --host=$FRONT_DOOR_HOSTNAME

echo "Deployment completed successfully"


