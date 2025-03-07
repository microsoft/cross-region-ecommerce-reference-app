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
  echo "No resource group provided. Please provide a resource group name as command line argument. E.g. '$0 -rg=my-rg-name'" >&2
  exit 1
fi

# Getting the AKS Clusters names
export AKS_CLUSTERS=$(az aks list --resource-group $RESOURCE_GROUP_NAME --query '[].name' -o tsv)

if [ -z "$AKS_CLUSTERS" ]; then
  echo "No AKS cluster found in resource group '$RESOURCE_GROUP_NAME'" >&2
  exit 1
fi

# Exporting common parameters
export APP_IDENTITY_NAME=$(az identity list --resource-group $RESOURCE_GROUP_NAME --query "[?contains(name,'app-identity')] | [0].name" -o tsv)
export CLIENT_ID=$(az identity show --resource-group $RESOURCE_GROUP_NAME --name $APP_IDENTITY_NAME --query "clientId" -o tsv)
export KEYVAULT_NAME=$(az keyvault list --resource-group $RESOURCE_GROUP_NAME --query "[0].name" -o tsv)
export USER_ASSIGNED_CLIENT_ID=$(az identity show --resource-group $RESOURCE_GROUP_NAME --name $APP_IDENTITY_NAME --query "clientId" -o tsv)
export IDENTITY_TENANT=$(az account show --query "tenantId" -o tsv)
export ACR_URI=azrefsharedlz2a.azurecr.io

SCRIPT_PATH=$( cd "$(dirname "${BASH_SOURCE[0]}")" ; pwd -P )
# remove .tmp file in case of residual files from previous runs
rm -rf $SCRIPT_PATH/.tmp

function deploy_to_aks_cluster() {
  local AKS_CLUSTER_NAME=$1
  local LOCATION=$(az aks show --resource-group $RESOURCE_GROUP_NAME --name $AKS_CLUSTER_NAME --query "location" -o tsv)
  export ILB_IP=$(az network application-gateway list --resource-group $RESOURCE_GROUP_NAME --query "[?location=='$LOCATION'] | [0].backendAddressPools[0].backendAddresses[0].ipAddress" -o tsv)

  mkdir $SCRIPT_PATH/.tmp

  echo "Logging into AKS cluster '$AKS_CLUSTER_NAME'"
  az aks get-credentials --resource-group $RESOURCE_GROUP_NAME --name $AKS_CLUSTER_NAME --overwrite-existing

  if ! command -v kubelogin &> /dev/null; then
    echo "kubelogin could not be found, please install it to proceed." >&2
    exit 1
  fi

  kubelogin convert-kubeconfig -l azurecli

  # Exporting cluster specific parameters
  export AKS_OIDC_ISSUER=$(az aks show -n ${AKS_CLUSTER_NAME} -g $RESOURCE_GROUP_NAME --query "oidcIssuerProfile.issuerUrl" -o tsv)

  echo "Step 1 - Creating ingress"
  envsubst < $SCRIPT_PATH/controller-ingress-nginx.yaml > $SCRIPT_PATH/.tmp/controller-ingress-nginx-processed.yaml
  az aks command invoke --name $AKS_CLUSTER_NAME \
      --resource-group $RESOURCE_GROUP_NAME \
      --command 'helm upgrade --install ingress-nginx ingress-nginx \
            --repo https://kubernetes.github.io/ingress-nginx \
            --namespace ingress-controller \
            --version 4.9.1 \
            --wait-for-jobs \
            --debug \
            --create-namespace \
            -f controller-ingress-nginx-processed.yaml' \
      --file $SCRIPT_PATH/.tmp/controller-ingress-nginx-processed.yaml

  echo "Step 2 - Creating app namespace"
  envsubst < $SCRIPT_PATH/app-namespace.yaml > $SCRIPT_PATH/.tmp/app-namespace-processed.yaml
  az aks command invoke --name $AKS_CLUSTER_NAME \
      --resource-group $RESOURCE_GROUP_NAME \
      --command 'kubectl apply -f app-namespace-processed.yaml' \
      --file $SCRIPT_PATH/.tmp/app-namespace-processed.yaml

  az identity federated-credential create \
    --name $APP_IDENTITY_NAME-$AKS_CLUSTER_NAME \
    --identity-name $APP_IDENTITY_NAME \
    --resource-group $RESOURCE_GROUP_NAME \
    --issuer $AKS_OIDC_ISSUER \
    --subject system:serviceaccount:app:workload

  echo "Step 3 - Container insights config"
  az aks command invoke --name $AKS_CLUSTER_NAME \
      --resource-group $RESOURCE_GROUP_NAME \
      --command 'kubectl apply -f container-azm-ms-agentconfig.yaml' \
      --file $SCRIPT_PATH/container-azm-ms-agentconfig.yaml

  rm -rf $SCRIPT_PATH/.tmp
}

# parse & deploy to all AKS clusters
for AKS_CLUSTER in $AKS_CLUSTERS; do
  deploy_to_aks_cluster $AKS_CLUSTER
done
