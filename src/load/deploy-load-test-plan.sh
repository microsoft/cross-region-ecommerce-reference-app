#!/usr/bin/env bash

# Get the directory of the script
SCRIPT_PATH=$( cd "$(dirname "${BASH_SOURCE[0]}")" ; pwd -P )


# Parse command line arguments
for ARG in "$@"; do
  case $ARG in
    -rg=*|--resource-group=*)
      RESOURCE_GROUP_NAME="${ARG#*=}"
      shift
      ;;
    -ltr=*|--load-testing-resource=*)
      LOAD_TESTING_RESOURCE="${ARG#*=}"
      shift
      ;;
    -af=*|--artifacts-folder=*)
      ARTIFACTS_FOLDER="${ARG#*=}"
      shift
      ;;
    -rad=*|--run-after-deploy=*)
      RUN_AFTER_DEPLOY="${ARG#*=}"
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

if [ -z $LOAD_TESTING_RESOURCE ]; then
  echo "No load testing resource added. Please provide a resource. E.g. '$0 -ltr=my-test-name'" >&2
  exit 1
fi

if [ -z $ARTIFACTS_FOLDER ]; then
  echo "No artifacts folder provided. Please provide an artifacts folder. E.g. '$0 -af=my/path/'" >&2
  exit 1
fi

AGENT_JAR_PATH=$(find ${ARTIFACTS_FOLDER}/src/load/jmeterBackendListener/target/agents -name "applicationinsights-agent-*.jar" | head -n 1)
if [ -z "$AGENT_JAR_PATH" ]; then
  echo "Agent jar file not found" >&2
  exit 1
fi
AGENT_FILE_NAME=$(basename "$AGENT_JAR_PATH")

BACKEND_LISTENER_PATH=$(find ${ARTIFACTS_FOLDER}/src/load/jmeterBackendListener/target/ -name "refapp.backendlistener-*-SNAPSHOT.jar" | head -n 1)
if [ -z "$BACKEND_LISTENER_PATH" ]; then
  echo "Backend listener jar file not found" >&2
  exit 1
fi

TEST_PLAN_NAME=azref-load-test

az load test create	\
    --resource-group $RESOURCE_GROUP_NAME \
    --load-test-resource $LOAD_TESTING_RESOURCE  \
    --load-test-config-file ${SCRIPT_PATH}/load-test-config.yaml \
    --test-id $TEST_PLAN_NAME \
    --env JVM_ARGS=-javaagent:/jmeter/lib/ext/$AGENT_FILE_NAME

az load test file upload \
    --resource-group $RESOURCE_GROUP_NAME \
    --load-test-resource $LOAD_TESTING_RESOURCE  \
    --path $AGENT_JAR_PATH \
    --test-id $TEST_PLAN_NAME \
    --file-type ADDITIONAL_ARTIFACTS

az load test file upload \
    --resource-group $RESOURCE_GROUP_NAME \
    --load-test-resource $LOAD_TESTING_RESOURCE  \
    --path $BACKEND_LISTENER_PATH \
    --test-id $TEST_PLAN_NAME \
    --file-type ADDITIONAL_ARTIFACTS

if [ "$RUN_AFTER_DEPLOY" = "True" ]; then
  echo "Starting the load test..."

  az load test-run create \
    --resource-group $RESOURCE_GROUP_NAME \
    --load-test-resource $LOAD_TESTING_RESOURCE  \
    --test-id $TEST_PLAN_NAME \
    --test-run-id pipeline-load-test-run \
    --no-wait
fi
