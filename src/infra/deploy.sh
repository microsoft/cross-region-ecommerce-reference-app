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
      PRIMARY_AKS_CAPACITY="${ARG#*=}"
      shift
      ;;
    -sac=*|--secondary-aks-capacity=*)
      SECONDARY_AKS_CAPACITY="${ARG#*=}"
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
      echo "Check the \"1-deploy-service.sh\" script for usage instructions."
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

# Validate input
if [ -z $RESOURCE_GROUP_NAME ]; then
  echo "No resource group provided. Provide a resource group name. E.g. '$0 -rg=rg-name'" >&2
  exit 1
fi
if [ -z $SERVICE_LOCATION ]; then
  echo "No service location provided. Provide a service location. E.g. '$0 -sl=eastus'" >&2
  exit 1
fi
if [ -z $SECONDARY_SERVICE_LOCATION ]; then
  echo "No secondary service location provided. Deploying a regional version" >&2
fi

if [ -z $PRIMARY_AKS_CAPACITY ]; then
  echo "Primary AKS capacity not provided. Defaulting to full"
  PRIMARY_AKS_CAPACITY="full"
fi

PRIMARY_AKS_CONFIG_FILE="config/aks_config_$PRIMARY_AKS_CAPACITY.json"
PRIMARY_AKS_CONFIG=$(cat "$PRIMARY_AKS_CONFIG_FILE")
PRIMARY_AKS_CONFIG=$(echo "$PRIMARY_AKS_CONFIG" | sed "s/\"/'/g") # replace " -> ' for string interpolation

AKS_CONFIG_ARRAY="[$PRIMARY_AKS_CONFIG]"


if [ -n "$SECONDARY_SERVICE_LOCATION" ]; then
  if [ -z $SECONDARY_AKS_CAPACITY ]; then
    echo "Secondary AKS capacity not provided. Defaulting to reduced"
    SECONDARY_AKS_CAPACITY="reduced"
  fi

  SECONDARY_AKS_CONFIG_FILE="config/aks_config_$SECONDARY_AKS_CAPACITY.json"
  SECONDARY_AKS_CONFIG=$(cat "$SECONDARY_AKS_CONFIG_FILE")
  SECONDARY_AKS_CONFIG=$(echo "$SECONDARY_AKS_CONFIG" | sed "s/\"/'/g") # replace " -> ' for string interpolation

  AKS_CONFIG_ARRAY="[$PRIMARY_AKS_CONFIG, $SECONDARY_AKS_CONFIG]"
fi

# Deploy Az Ref App to the specified resource group
RESOURCES_SUFFIX_UID=${RESOURCE_GROUP_NAME: -6}
DEPLOYMENT_NAME=refapp-deploy

echo RESOURCE_GROUP_NAME $RESOURCE_GROUP_NAME

az deployment group create \
  --resource-group $RESOURCE_GROUP_NAME \
  --name $DEPLOYMENT_NAME \
  --template-file main.bicep \
  --parameters main.bicepparam \
  --parameters serviceLocation=$SERVICE_LOCATION \
  --parameters secondaryServiceLocation=$SECONDARY_SERVICE_LOCATION \
  --parameters crossRegionalRouting=$CROSS_REGIONAL_ROUTING \
  --parameters aksConfig="$AKS_CONFIG_ARRAY"\
  --parameters resourceSuffixUID=$RESOURCES_SUFFIX_UID \
  --verbose \
  $ADDITONAL_PARAMS
