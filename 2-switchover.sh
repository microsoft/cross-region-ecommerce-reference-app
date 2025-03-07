#!/usr/bin/env bash

# Exit on errors
set -o errexit -o pipefail -o noclobber

bash ./switchover/switchover.sh "$@"
