#!/bin/bash

# Exit on errors
set -o errexit -o pipefail -o noclobber

# Parse command line arguments
for ARG in "$@"; do
    case $ARG in
        -rg=*|--resource-group=*)
            RESOURCE_GROUP_NAME="${ARG#*=}"
            shift
            ;;
        -*|--*)
            echo "Unknown argument '$ARG'" >&2
            exit 1
            ;;
        *)
            ;;
    esac
done

# Validate command line arguments
if [ -z $RESOURCE_GROUP_NAME ]; then
    echo "No resource group name provided. Please provide a resource group name as command line argument. E.g. '$0 -rg=my-resource-group'" >&2
    exit 1
fi

echo "Removing Redis Geo-replication link..."
# Get the first Redis cache name from the resource group
CACHE_NAME=$(az redis list --resource-group $RESOURCE_GROUP_NAME --query "[0].name" -o tsv)

# Check if the resource group has any Redis caches
if [ -n "$CACHE_NAME" ]; then
    # Check if geo-replication link exists
    LINKED_SERVER_NAME=$(az redis server-link list --name $CACHE_NAME --resource-group $RESOURCE_GROUP_NAME --query "[0].name" -o tsv)
fi

if [ -n "$LINKED_SERVER_NAME" ]; then
    # Remove geo-replication link
    az redis server-link delete --resource-group $RESOURCE_GROUP_NAME --name $CACHE_NAME --linked-server-name $LINKED_SERVER_NAME
    echo "Geo-replication link removed."
else
    echo "No geo-replication link found."
fi

echo "Deleting the resource group..."
az group delete --resource-group $RESOURCE_GROUP_NAME --yes
echo "Resource group deleted..."
