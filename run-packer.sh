#!/bin/bash
# run-packer: execute the packer action passed as argument
# Requirements:
#  - the variables PKR_VAR_cloud, PKR_VAR_agent and PKR_VAR_architecture are defined
#  - The cloud defined on PKR_VAR_cloud must be configured through its standard environment variables or CLI default setting
# This script could be repalced by a Makefile
# But make is not installed in the Docker image hashicorp/packer:1.7.2

set -eu -o pipefail

: "${PKR_VAR_cloud:?Variable PKR_VAR_cloud not defined.}"
: "${PKR_VAR_agent:?Variable PKR_VAR_agent not defined.}"
: "${PKR_VAR_architecture:?Variable PKR_VAR_architecture not defined.}"
: "${1:?First argument - packer action to execute- not defined.}"

## Always run initialization to ensure plugins are download and workspace is set up
packer init "${PKR_VAR_cloud}/"

case $1 in
  validate)
    packer validate --only="*.${PKR_VAR_agent}" "${PKR_VAR_cloud}/"
    echo "Validation Success."
    ;;
  build)
    packer build --only="*.${PKR_VAR_agent}" --force "${PKR_VAR_cloud}/"
    echo "Build Success."
    ;;
  *)
    echo "Error: Packer action '$1' is unknown."
    ;;
esac
