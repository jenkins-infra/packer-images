#!/bin/bash
# run-packer: execute the packer action passed as argument
# This script could be replaced by a Makefile
# But make is not installed in the Docker image hashicorp/packer

set -eux -o pipefail

: "${1:?First argument - packer action to execute- not defined.}"

packer_cmd="packer"
packer_template_dir="./"
packer_install_dir="/$HOME"
packer_version="1.7.8"

export PKR_VAR_scm_ref PKR_VAR_image_type PKR_VAR_agent


## check if packer exists or install it
if ! command -v ${packer_cmd} >/dev/null 2>&1
then
  if test -x "${packer_install_dir}/${packer_cmd}"
  then
    packer_cmd="${packer_install_dir}/packer"
  else
    echo "Packer not installed, installing it"
    arch=$(uname -i)
    if [[ $arch == x86_64* ]]; then
        echo "X64 Architecture"
        packer_download_path="https://releases.hashicorp.com/packer/${packer_version}/packer_${packer_version}_linux_amd64.zip"
    elif [[ $arch == i*86 ]]; then
        echo "X32 Architecture"
        packer_download_path="https://releases.hashicorp.com/packer/${packer_version}/packer_${packer_version}_linux_386.zip"
    elif [[ $arch == arm* ]]; then
        echo "ARM Architecture 32b"
        packer_download_path="https://releases.hashicorp.com/packer/${packer_version}/packer_${packer_version}_linux_arm.zip"
    elif [[ $arch == aarch64 ]]; then
        echo "ARM Architecture 64b"
        packer_download_path="https://releases.hashicorp.com/packer/${packer_version}/packer_${packer_version}_linux_arm64.zip"
    else 
        echo "Architecture not found"
        exit 2
    fi
    curl -sSL -o /tmp/packer.zip $packer_download_path
    unzip /tmp/packer.zip -d "${packer_install_dir}"
    packer_cmd="${packer_install_dir}/packer"
  fi
fi

## Always run initialization to ensure plugins are download and workspace is set up
$packer_cmd init "${packer_template_dir}"

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
    $packer_cmd fmt -recursive .
    $packer_cmd validate "${PACKER_COMMON_FLAGS[@]}"
    echo "Validation Success."
    ;;
  build)
    $packer_cmd build -timestamp-ui --force "${PACKER_COMMON_FLAGS[@]}"
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
