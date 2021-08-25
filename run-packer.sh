#!/bin/bash
# run-packer: execute the packer action passed as argument
# Requirements:
#  - the variables PKR_VAR_image_type, PKR_VAR_agent and PKR_VAR_architecture are defined
#  - The cloud defined on PKR_VAR_image_type must be configured through its standard environment variables or CLI default setting
# This script could be replaced by a Makefile
# But make is not installed in the Docker image hashicorp/packer

set -eu -o pipefail

: "${PKR_VAR_image_type:?Variable PKR_VAR_image_type not defined.}"
: "${PKR_VAR_agent:?Variable PKR_VAR_agent not defined.}"
: "${PKR_VAR_architecture:?Variable PKR_VAR_architecture not defined.}"
: "${1:?First argument - packer action to execute- not defined.}"

packer_template_dir="./"

PKR_VAR_image_version="$(jx-release-version -next-version semantic)"
export PKR_VAR_image_version

## Always run initialization to ensure plugins are download and workspace is set up
packer init "${packer_template_dir}"

case $1 in
  validate)
    packer validate --only="${PKR_VAR_image_type}.${PKR_VAR_agent}" "${packer_template_dir}"
    echo "Validation Success."
    ;;
  build)
    packer build --only="${PKR_VAR_image_type}.${PKR_VAR_agent}" -timestamp-ui --force "${packer_template_dir}"
    echo "Build Success."
    ;;
  *)
    echo "Error: Packer action '$1' is unknown."
    ;;
esac
