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

  -rg, --resource-group                 Name of the resource group containing the services to switchover
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

# Validate input
if [ -z $RESOURCE_GROUP_NAME ]; then
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

# Get the directory of the script
SCRIPT_PATH=$( cd "$(dirname "${BASH_SOURCE[0]}")" ; pwd -P )

echo "Starting switchover from $FROM_REGION to $TO_REGION for resource group '$RESOURCE_GROUP_NAME'..."

# Start the AKS cluster in the failover region
echo "Starting AKS cluster in the failover region..."
bash $SCRIPT_PATH/../aks/aks-cluster-control.sh --resource-group=$RESOURCE_GROUP_NAME --region=$TO_REGION --command='START'

AKS_EXIT_STATUS=$?
if [ $AKS_EXIT_STATUS -ne 0 ]; then
  echo "AKS cluster start failed with exit status $AKS_EXIT_STATUS. Aborting..." >&2
  exit 1
fi

# Start the switchover for the storage services in parallel
bash $SCRIPT_PATH/storage/redis.sh --resource-group=$RESOURCE_GROUP_NAME --from=$FROM_REGION --to=$TO_REGION &
REDIS_PID=$!
bash $SCRIPT_PATH/storage/sql.sh --resource-group=$RESOURCE_GROUP_NAME --from=$FROM_REGION --to=$TO_REGION &
SQL_PID=$!

# Disable errexit to handle exit statuses manually
set +o errexit

# Wait for the scripts to complete and check their exit statuses
wait $REDIS_PID
REDIS_EXIT_STATUS=$?
wait $SQL_PID
SQL_EXIT_STATUS=$?

if [ $REDIS_EXIT_STATUS -ne 0 ]; then
  echo "Redis switchover failed with exit status $REDIS_EXIT_STATUS. Aborting..." >&2

  if [ $REDIS_EXIT_STATUS -eq 0 ]; then
    echo "Rolling back SQL switchover..."
    bash $SCRIPT_PATH/storage/sql.sh --resource-group=$RESOURCE_GROUP_NAME --from=$TO_REGION --to=$FROM_REGION
  fi

  exit 1
fi

if [ $SQL_EXIT_STATUS -ne 0 ]; then
  echo "SQL switchover failed with exit status $SQL_EXIT_STATUS. Aborting..." >&2

  if [ $REDIS_EXIT_STATUS -eq 0 ]; then
    echo "Rolling back Redis switchover..."
    bash $SCRIPT_PATH/storage/redis.sh --resource-group=$RESOURCE_GROUP_NAME --from=$TO_REGION --to=$FROM_REGION
  fi

  exit 1
fi

echo "Storage services switchover completed!"

bash $SCRIPT_PATH/network/frontdoor.sh --resource-group=$RESOURCE_GROUP_NAME --from=$FROM_REGION --to=$TO_REGION &
FRONTDOOR_PID=$!

wait $FRONTDOOR_PID
FRONTDOOR_EXIT_STATUS=$?

if [ $FRONTDOOR_EXIT_STATUS -ne 0 ]; then
  echo "Front Door switchover failed with exit status $FRONTDOOR_EXIT_STATUS. Aborting..." >&2
  echo "Rolling back storage services switchover..."
  
  bash $SCRIPT_PATH/storage/sql.sh --resource-group=$RESOURCE_GROUP_NAME --from=$TO_REGION --to=$FROM_REGION &
  bash $SCRIPT_PATH/storage/redis.sh --resource-group=$RESOURCE_GROUP_NAME --from=$TO_REGION --to=$FROM_REGION &
  wait

  exit 1
fi

echo "Switchover completed for all services!"
