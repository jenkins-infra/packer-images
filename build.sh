#!/bin/bash

set -e -o pipefail

: "${CLOUD:?Cloud not defined [aws,azure]}"
: "${AGENT:?Agent not defined}"
: "${ARCHITECTURE:?Architecture not defined[amd64,arm64]}"
: "${LOCATION:?Location not defined}"

# defining versions here so they can be passed to all builds
export PKR_VAR_location="${LOCATION}"
export PKR_VAR_maven_version="3.6.3"
export PKR_VAR_git_version="2.29.2"
export PKR_VAR_jdk11_version="11.0.9+11"
export PKR_VAR_jdk8_version="8u272-b10"
export PKR_VAR_git_lfs_version="2.12.1"
export PKR_VAR_compose_version="1.25.4"

templatefile="${CLOUD}/${AGENT}-agent.${ARCHITECTURE}.pkr.hcl"
mainArgument="${1:-validateAndBuild}"

function packerInit() {
  packer init "./${templatefile}"
}

function packerValidate() {
  packer validate "./${templatefile}"
}

function packerBuild() {
  packer build --force "./${templatefile}"
}

function fullPackerBuild() {
  packerInit
  packerValidate
  if [ "${mainArgument}" != "validateOnly" ]
  then
    packerBuild
  fi
}

function isTemplateExist() {
  if [ ! -f "${templatefile}" ]; then
    echo "Error file not found: ${templatefile}"
    exit 1
  fi
}

function buildAzure(){
  : "${RESOURCE_GROUP_NAME:?RESOURCE_GROUP_NAME not defined}"
  : "${AZURE_SUBSCRIPTION_ID:?AZURE_SUBSCRIPTION_ID not defined}"
  export PKR_VAR_resource_group_name="${RESOURCE_GROUP_NAME}"
  export PKR_VAR_subscription_id="${AZURE_SUBSCRIPTION_ID}"
  export PKR_VAR_client_id="${AZURE_CLIENT_ID}"
  export PKR_VAR_client_secret="${AZURE_CLIENT_SECRET}"

  fullPackerBuild
}

function buildAWS(){
  fullPackerBuild
}

function build() {
  isTemplateExist
  case $CLOUD in
    aws)
      buildAWS
      ;;
    azure)
      buildAzure
      ;;
  esac
}


build
