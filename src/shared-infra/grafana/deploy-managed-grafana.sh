az deployment sub create \
  --name refapp-grafana-deploy \
  --template-file main.bicep \
  --location $(cat ../sharedInfraParams.json | jq .parameters.grafanaParams.value.location | tr -d '"') \
  --parameters ../sharedInfraParams.json