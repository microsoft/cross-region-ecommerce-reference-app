#!/usr/bin/env bash

# Exit on errors
set -o errexit -o pipefail -o noclobber

# Get the directory of the script
SCRIPT_PATH=$( cd "$(dirname "${BASH_SOURCE[0]}")" ; pwd -P )

#import common functions
source "${SCRIPT_PATH}/../common/common-bash-functions.sh"

# Parse command line arguments
for ARG in "$@"; do
  case $ARG in
    -rg=*|--resource-group-name=*)
      RESOURCE_GROUP_NAME="${ARG#*=}"
      shift
      ;;
    -sl=*|--service-location=*)
      SERVICE_LOCATION="${ARG#*=}"
      shift
      ;;
    -ssl=*|--secondary-service-location=*)
      SECONDARY_SERVICE_LOCATION="${ARG#*=}"
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
if [ -z "$RESOURCE_GROUP_NAME" ]; then
  echo "No Resource Group Name provided. Please provide it as command line argument. E.g. '$0 -rg=my-app-rg'" >&2
  exit 1
fi
if [ -z "$SERVICE_LOCATION" ]; then
    echo "No service location provided. Provide one '$0 -sl=eastus'." >&2
    exit 1
fi


GRAFANA_RG=$(cat ${SCRIPT_PATH}/../shared-infra/sharedInfraParams.json | jq .parameters.grafanaParams.value.resourceGroup | tr -d '"')
GRAFANA_NAME=$(cat ${SCRIPT_PATH}/../shared-infra/sharedInfraParams.json | jq .parameters.grafanaParams.value.name | tr -d '"')
GRAFANA_FOLDER=$(cat ${SCRIPT_PATH}/../shared-infra/sharedInfraParams.json | jq .parameters.grafanaParams.value.grafanaFolder | tr -d '"')

CLIENT_LOG_ANALYTICS_WORKSPACE_ID=$(az monitor log-analytics workspace list -g $RESOURCE_GROUP_NAME --query "[?contains(name,'client')] | [0].id" -o tsv)
FIRST_APP_LOG_ANALYTICS_WORKSPACE_ID=$(az monitor log-analytics workspace list -g $RESOURCE_GROUP_NAME --query "[?contains(name,'insights-ws') && location=='$SERVICE_LOCATION'] | [0].id" -o tsv)
FIRST_REGION=$SERVICE_LOCATION

if [ -z "$SECONDARY_SERVICE_LOCATION" ]; then
  echo "Skipping checking for Second Region"
  SECOND_APP_LOG_ANALYTICS_WORKSPACE_ID="N/A"
  SECOND_REGION="N/A"
else
  SECOND_APP_LOG_ANALYTICS_WORKSPACE_ID=$(az monitor log-analytics workspace list -g $RESOURCE_GROUP_NAME --query "[?contains(name,'insights-ws') && location=='$SECONDARY_SERVICE_LOCATION'] | [0].id" -o tsv)
  SECOND_REGION=$SECONDARY_SERVICE_LOCATION
fi

# remove .tmp file in case of residual files from previous runs
rm -rf $SCRIPT_PATH/.tmp
mkdir $SCRIPT_PATH/.tmp
cp ${SCRIPT_PATH}/reportTemplate.json ${SCRIPT_PATH}/.tmp/reportTemplate.json

replace_var_in_files ${SCRIPT_PATH}/.tmp/reportTemplate.json

az grafana dashboard create -g $GRAFANA_RG -n $GRAFANA_NAME \
    --title "Ref App Dashboard ${RESOURCE_GROUP_NAME}" \
    --folder "${GRAFANA_FOLDER}" \
    --definition "${SCRIPT_PATH}/.tmp/reportTemplate.json"
    