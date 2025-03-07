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

# Retrieve the SQL server names and the failover group
FROM_SQL_NAME=$(az sql server list --resource-group $RESOURCE_GROUP_NAME --query "[?location=='$FROM_REGION'].name" -o tsv | tr -d '\r')
TO_SQL_NAME=$(az sql server list --resource-group $RESOURCE_GROUP_NAME --query "[?location=='$TO_REGION'].name" -o tsv | tr -d '\r')

FAILOVER_GROUP=$(az sql failover-group list --resource-group $RESOURCE_GROUP_NAME --server $FROM_SQL_NAME --query "[0].name" -o tsv | tr -d '\r')

echo "Switching over SQL from $FROM_REGION to $TO_REGION..."

az sql failover-group set-primary --resource-group $RESOURCE_GROUP_NAME --name $FAILOVER_GROUP --server $TO_SQL_NAME

echo "SQL switchover completed."
