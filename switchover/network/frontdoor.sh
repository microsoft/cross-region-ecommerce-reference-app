#!/usr/bin/env bash

# Exit on errors
set -o errexit -o pipefail -o noclobber

# Parse command line arguments
for ARG in "$@"; do
  case $ARG in
  -rg=* | --resource-group=*)
    RESOURCE_GROUP_NAME="${ARG#*=}"
    shift
    ;;
  -f=* | --from=*)
    FROM_REGION="${ARG#*=}"
    shift
    ;;
  -t=* | --to=*)
    TO_REGION="${ARG#*=}"
    shift
    ;;
  -h | --help)
    echo "
Usage: $0 [-rg=rg-name] [--from=region] [--to=region]

  -rg, --resource-group                 Name of the resource group
  -f, --from                            The region from which to switchover
  -t, --to                              The region to which to switchover
  -h, --help                            Show this help message

Examples:
  $0 -rg=rg-name --from=eastus --to=westus
"
    exit 0
    ;;
  -* | --*)
    echo "Unknown argument '$ARG'" >&2
    exit 1
    ;;
  *) ;;
  esac
done

# Validate inputs
if [ -z "$RESOURCE_GROUP_NAME" ]; then
  echo "No resource group provided. Please provide a resource group name as command line argument. E.g. '$0 -rg=my-rg-name'" >&2
  exit 1
fi

if [ -z "$FROM_REGION" ]; then
  echo "No region to switchover from provided. Please provide it using the --from or -f argument." >&2
  exit 1
fi

if [ -z "$TO_REGION" ]; then
  echo "No region to switchover to provided. Please provide it using the --to or -t argument." >&2
  exit 1
fi

# Retrieve the Front Door profile name
FRONT_DOOR_NAME=$(az afd profile list --resource-group $RESOURCE_GROUP_NAME --query "[0].name" -o tsv | tr -d '\r')

# Retrieve the origin group name
ORIGIN_GROUP_NAME=$(az afd origin-group list --resource-group $RESOURCE_GROUP_NAME --profile-name $FRONT_DOOR_NAME --query "[0].name" -o tsv | tr -d '\r')

# Get all origins in the origin group
ORIGINS=$(az afd origin list --resource-group $RESOURCE_GROUP_NAME --profile-name $FRONT_DOOR_NAME --origin-group-name $ORIGIN_GROUP_NAME --query "[].{Name:name, HostName:hostName}")

echo "Switching over Front Door from $FROM_REGION to $TO_REGION..."

# Loop through each origin to get its app gateway and region
for ORIGIN in $(echo "$ORIGINS" | jq -c '.[]'); do
  ORIGIN_NAME=$(echo "$ORIGIN" | jq -r '.Name')
  ORIGIN_HOSTNAME=$(echo "$ORIGIN" | jq -r '.HostName')

  # Retrieve the public IP address associated with the origin hostname
  PUBLIC_IP_NAME=$(az network public-ip list --resource-group $RESOURCE_GROUP_NAME --query "[?ipAddress=='$ORIGIN_HOSTNAME'].name" -o tsv | tr -d '\r')

  # Retrieve the region of the app gateway
  PUBLIC_IP_REGION=$(az network public-ip show --resource-group $RESOURCE_GROUP_NAME --name $PUBLIC_IP_NAME --query "location" -o tsv | tr -d '\r')

  # Set the priority based on the region
  if [ "$PUBLIC_IP_REGION" == "$FROM_REGION" ]; then
    NEW_PRIORITY=2
  elif [ "$PUBLIC_IP_REGION" == "$TO_REGION" ]; then
    NEW_PRIORITY=1
  fi

  # Update the origin priority
  az afd origin update --resource-group $RESOURCE_GROUP_NAME --profile-name $FRONT_DOOR_NAME --origin-group-name $ORIGIN_GROUP_NAME --origin-name $ORIGIN_NAME --priority $NEW_PRIORITY
done

echo "Updated origin priorities for Front Door profile '$FRONT_DOOR_NAME' in resource group '$RESOURCE_GROUP_NAME'."
