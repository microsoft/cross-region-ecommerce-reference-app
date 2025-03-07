#!/usr/bin/env bash

# Exit on errors
set -o errexit -o pipefail -o noclobber

# Parse command line arguments
for ARG in "$@"; do
    case $ARG in
        -rg=*|--resource-group=*)
            RESOURCE_GROUP_NAME="${ARG#*=}"
            shift
            ;;
        -r=*|--region=*)
            REGION="${ARG#*=}"
            shift
            ;;
        -c=*|--command=*)
            COMMAND="${ARG#*=}"
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

if [ -z $REGION ]; then
    echo "No region provided. Please provide a region as command line argument. E.g. '$0 -r=uscentral'" >&2
    exit 1
fi

if [ -z $COMMAND ]; then
    echo "No command provided. Please provide a command as command line argument. E.g. '$0 -c=STOP'" >&2
    exit 1
fi

# Get the AKS cluster name dynamically
CLUSTER_NAME=$(az aks list --resource-group "$RESOURCE_GROUP_NAME" --query "[?location=='$REGION'].name" -o tsv)

if [ -z $CLUSTER_NAME ]; then
    echo "No AKS cluster found in resource group '$RESOURCE_GROUP_NAME' and region '$REGION'" >&2
    exit 1
fi

# Stop the AKS cluster
echo "Applying '$COMMAND' command to AKS cluster '$CLUSTER_NAME' in resource group '$RESOURCE_GROUP_NAME' and region '$REGION'..."

case $COMMAND in
    STOP)
        STATUS=$(az aks show --resource-group "$RESOURCE_GROUP_NAME" --name "$CLUSTER_NAME" --query "powerState.code" -o tsv)
        if [ "$STATUS" == "Stopped" ]; then
            echo "AKS cluster '$CLUSTER_NAME' is already stopped."
            exit 0
        fi

        az aks stop --resource-group "$RESOURCE_GROUP_NAME" --name "$CLUSTER_NAME"
        echo "AKS cluster stopped successfully."
        ;;
    START)
        STATUS=$(az aks show --resource-group "$RESOURCE_GROUP_NAME" --name "$CLUSTER_NAME" --query "powerState.code" -o tsv)
        if [ "$STATUS" == "Running" ]; then
            echo "AKS cluster '$CLUSTER_NAME' is already running."
            exit 0
        fi

        az aks start --resource-group "$RESOURCE_GROUP_NAME" --name "$CLUSTER_NAME"
        echo "AKS cluster started successfully."
        ;;
    *)
        echo "Unknown command '$COMMAND'. Please provide a valid command (START or STOP)." >&2
        exit 1
        ;;
esac

echo "AKS command executed successfully."
