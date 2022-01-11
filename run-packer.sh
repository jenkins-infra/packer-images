#!/bin/bash
# run-packer: execute the packer action passed as argument
# This script could be replaced by a Makefile
# But make is not installed in the Docker image hashicorp/packer

set -eu -o pipefail

: "${1:?First argument - packer action to execute- not defined.}"

packer_template_dir="./"

export PKR_VAR_scm_ref PKR_VAR_image_type PKR_VAR_agent


## Always run initialization to ensure plugins are download and workspace is set up
packer init "${packer_template_dir}"

## Define Packer flags based on the current environment (look at the `Jenkinsfile` to diagnose the pipeline)
PACKER_COMMON_FLAGS=("${packer_template_dir}")
set +u
if test -n "${PKR_VAR_image_type}" && test -n "${PKR_VAR_agent}"
then
  PACKER_COMMON_FLAGS=("--only=${PKR_VAR_image_type}.${PKR_VAR_agent}" "${PACKER_COMMON_FLAGS[@]}")
fi
set -u

echo "== Running action $1 with packer: =="
case $1 in
  validate)
    packer fmt -recursive .
    packer validate "${PACKER_COMMON_FLAGS[@]}"
    echo "Validation Success."
    ;;
  build)
    packer build -timestamp-ui --force "${PACKER_COMMON_FLAGS[@]}"
    echo "Build Success."
    ;;
  report)
    echo "= Current Packer environment:"
    env | grep -i PKR_VAR
    env | grep -i PACKER
    PACKER_VARS_FILE=.auto.pkrvars.hcl
    echo "= Current Packer var file ${PACKER_VARS_FILE} =="
    cat "${PACKER_VARS_FILE}"
    ;;
  *)
    echo "Error: Packer action '$1' is unknown."
    ;;
esac
echo "===================================="

exit 0
