#!/usr/bin/env bash

# Exit on errors
set -o errexit -o pipefail -o noclobber

SCRIPT_PATH=$( cd "$(dirname "${BASH_SOURCE[0]}")" ; pwd -P )
cd $SCRIPT_PATH

# Parse command line arguments
for ARG in "$@"; do
  case $ARG in
    -rg=*|--resource-group=*)
      RESOURCE_GROUP_NAME="${ARG#*=}"
      shift
      ;;
    -cl=*|--client-location=*)
      CLIENT_LOCATION="${ARG#*=}"
      shift
      ;;
    -sl=*|--service-location=*)
      SERVICE_LOCATION="${ARG#*=}"
      shift
      ;;
    -mn=*|--manifest-name=*)
      MANIFEST_NAME="${ARG#*=}"
      shift
      ;;
    -ssl=*|--secondary-service-location=*)
      SECONDARY_SERVICE_LOCATION="${ARG#*=}"
      shift
      ;;
    -pac=*|--primary-aks-capacity=*)
      PRIMARY_AKS_CAPACITY="${ARG#*=:-full}"
      shift
      ;;
    -sac=*|--secondary-aks-capacity=*)
      SECONDARY_AKS_CAPACITY="${ARG#*=:-reduced}"
      shift
      ;;
    -crr=*|--cross-regional-routing=*)
      CROSS_REGIONAL_ROUTING="${ARG#*=}"
      shift
      ;;
    --what-if)
      ADDITONAL_PARAMS="--what-if"
      shift
      ;;
    -h|--help)
      echo "
Usage: $0 [-rg=rg-name] [-cl=client-location] [-sl=service-location] [--what-if]

  -rg, --resource-group                 Name of the existing resource group to deploy to. Takes precedence over service location. If not provided, a new resource group will be created
  -sl, --service-location               Location to deploy the service to. A new resource group will be created in this location if no resource group is provided. If a resource group is provided,
                                                this is ignored and the location of the resource group will be used
  -cl, --client-location                Location to deploy the client (JMeter) to. Default: westus3
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
    -*|--*)
      echo "Unknown argument '$ARG'" >&2
      exit 1
      ;;
    *)
      ;;
  esac
done

# Validate input, set defaults, and create resource group if needed
if [ -z $RESOURCE_GROUP_NAME ]; then
  if [ -z $SERVICE_LOCATION ]; then
    echo "No resource group or service location provided. Provide at least one. E.g. '$0 -rg=rg-name' or '$0 -sl=eastus'. Run with '--help' for more information" >&2
    exit 1
  fi
  if [ -z $SECONDARY_SERVICE_LOCATION ]; then
    echo "No secondary service location provided. Deploying a regional version" >&2
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

if [ -z $CLIENT_LOCATION ]; then
  echo "Client location not provided. Defaulting to West US 3"
  CLIENT_LOCATION="westus3"
fi

if [ -z $PRIMARY_AKS_CAPACITY ]; then
  echo "Primary AKS capacity not provided. Defaulting to full"
  PRIMARY_AKS_CAPACITY="full"
fi

if [ -z $SECONDARY_AKS_CAPACITY ]; then
  echo "Secondary AKS capacity not provided. Defaulting to reduced"
  SECONDARY_AKS_CAPACITY="reduced"
fi

PRIMARY_AKS_CONFIG_FILE="config/aks_config_$PRIMARY_AKS_CAPACITY.json"
PRIMARY_AKS_CONFIG=$(cat "$PRIMARY_AKS_CONFIG_FILE")
PRIMARY_AKS_CONFIG=$(echo "$PRIMARY_AKS_CONFIG" | sed "s/\"/'/g") # replace " -> ' for string interpolation

AKS_CONFIG_ARRAY="[$PRIMARY_AKS_CONFIG]"


if [ -n "$SECONDARY_SERVICE_LOCATION" ]; then
  SECONDARY_AKS_CONFIG_FILE="config/aks_config_$SECONDARY_AKS_CAPACITY.json"
  SECONDARY_AKS_CONFIG=$(cat "$SECONDARY_AKS_CONFIG_FILE")
  SECONDARY_AKS_CONFIG=$(echo "$SECONDARY_AKS_CONFIG" | sed "s/\"/'/g") # replace " -> ' for string interpolation

  AKS_CONFIG_ARRAY="[$PRIMARY_AKS_CONFIG, $SECONDARY_AKS_CONFIG]"
fi

# Deploy Az Ref App to the specified resource group
RESOURCES_SUFFIX_UID=${RESOURCE_GROUP_NAME: -6}
DEPLOYMENT_NAME=refapp-deploy

az deployment group create \
  --resource-group $RESOURCE_GROUP_NAME \
  --name $DEPLOYMENT_NAME \
  --template-file main.bicep \
  --parameters main.bicepparam \
  --parameters serviceLocation=$SERVICE_LOCATION \
  --parameters secondaryServiceLocation=$SECONDARY_SERVICE_LOCATION \
  --parameters crossRegionalRouting=$CROSS_REGIONAL_ROUTING \
  --parameters aksConfig="$AKS_CONFIG_ARRAY"\
  --parameters clientLocation=$CLIENT_LOCATION \
  --parameters resourceSuffixUID=$RESOURCES_SUFFIX_UID \
  --parameters manifestName=$MANIFEST_NAME \
  $ADDITONAL_PARAMS \
  --verbose

# Output ADO variables to be used throughout the pipeline definition
if [ -n $ADO_DEPLOYMENT ]; then
  echo "##vso[task.setvariable variable=resourceGroupName;isOutput=true]$RESOURCE_GROUP_NAME"

  # exit in case of --what-if parameter - no deployment output needed
  if [[ "$ADDITONAL_PARAMS" == *"--what-if"* ]]; then
      exit 0
  fi

  # Retrieve the deployment outputs
  deployment_outputs=$(
    az deployment group show \
      --resource-group "$RESOURCE_GROUP_NAME" \
      --name $DEPLOYMENT_NAME \
      --query properties.outputs -o json
  )

  # Loop through the JSON to extract key-value pairs
  echo "$deployment_outputs" | \
    jq -r 'to_entries[] | "##vso[task.setvariable variable=\(.key);isOutput=true]\(.value.value)"'
fi
