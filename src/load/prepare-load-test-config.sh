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
    --*=*)
      var_name="${ARG%%=*}"
      var_name="${var_name#--}"
      var_value="${ARG#*=}"
      export "$var_name"="$var_value"
      shift
      ;;
    --*)
      echo "Unknown argument '$ARG'" >&2
      exit 1
      ;;
    *)
      ;;
  esac
done

FILE_PATH="${SCRIPT_PATH}/load-test-config.yaml"

replace_var_in_files $FILE_PATH
