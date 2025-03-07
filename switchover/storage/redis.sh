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

FROM_REGION_DISPLAY_NAME=$(az account list-locations --query "[?name=='$FROM_REGION'].displayName" -o tsv | tr -d '\r')
TO_REGION_DISPLAY_NAME=$(az account list-locations --query "[?name=='$TO_REGION'].displayName" -o tsv | tr -d '\r')

# Retrieve the Redis cache names
FROM_REDIS_NAME=$(az redis list --resource-group $RESOURCE_GROUP_NAME --query "[?location=='$FROM_REGION_DISPLAY_NAME'].name" -o tsv | tr -d '\r')
TO_REDIS_NAME=$(az redis list --resource-group $RESOURCE_GROUP_NAME --query "[?location=='$TO_REGION_DISPLAY_NAME'].name" -o tsv | tr -d '\r')

echo "Switching over Redis cache from $FROM_REGION to $TO_REGION..."

az redis server-link create --resource-group $RESOURCE_GROUP_NAME \
  --name $TO_REDIS_NAME \
  --server-to-link $FROM_REDIS_NAME \
  --replication-role Secondary

echo "Redis cache switchover completed."
