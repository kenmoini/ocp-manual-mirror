#!/bin/bash

# join-auths.sh

# This script will simply take two pull secrets and combine them
# Useful for taking a Red Hat Pull Secret JSON file and combining it with your private one for mirroring
# eg

# podman login --authfile private-ps.json private.registry.example.com
# ./join-auths.sh private-ps.json red-hat-ps.json > combined-ps.json

# Check to make sure we have to parameters passed to the script
if [ $# -ne 2 ]; then
  echo "Usage: $0 pull-secret-1.json pull-secret-2.json [> output.json]"
  exit 1
fi

# Load the two pull secrets into variables

jq -Mrcs '.[0] * .[1]' ${1} ${2}
