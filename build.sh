#!/bin/bash

: "${CLOUD:?Cloud not defined [aws,azure]}"
: "${AGENT:?Agent not defined}"
: "${ARCHITECTURE:?Architecture not defined[amd64,arm64]}"
: "${LOCATION:?Location not defined}"

# defining versions here so they can be passed to all builds
MAVEN_VERSION="3.6.3"
GIT_VERSION="2.29.2"
JDK11_VERSION="11.0.9+11"
JDK8_VERSION="8u272-b10"
GIT_LFS_VERSION="2.12.1"
COMPOSE_VERSION="1.25.4"

function isTemplateExist() {
  if [ ! -f "${CLOUD}/${AGENT}-agent.${ARCHITECTURE}.json" ]; then
    echo "Error file not found: ${CLOUD}/${AGENT}-agent.${ARCHITECTURE}.json"
    exit 1
  fi
}

function buildAzure(){
  : "${RESOURCE_GROUP_NAME:?RESOURCE_GROUP_NAME not defined}"
  : "${AZURE_SUBSCRIPTION_ID:?AZURE_SUBSCRIPTION_ID not defined}"
  packer build \
      --force \
      --var location="$LOCATION" \
      --var resource_group_name="$RESOURCE_GROUP_NAME" \
      --var subscription_id="$AZURE_SUBSCRIPTION_ID" \
      --var client_id="$AZURE_CLIENT_ID" \
      --var client_secret="$AZURE_CLIENT_SECRET" \
      --var maven_version="$MAVEN_VERSION" \
      --var git_version="$GIT_VERSION" \
      --var jdk11_version="$JDK11_VERSION" \
      --var jdk8_version="$JDK8_VERSION" \
      --var git_lfs_version="$GIT_LFS_VERSION" \
      --var compose_version="$COMPOSE_VERSION" \
      "./${CLOUD}/${AGENT}-agent.${ARCHITECTURE}.json"
}

function buildAWS(){
  packer build \
      --force \
      --var location="$LOCATION" \
      --var aws_access_key="$AWS_ACCESS_KEY_ID" \
      --var aws_secret_key="$AWS_SECRET_ACCESS_KEY" \
      --var openssh_public_key="$OPENSSH_PUBLIC_KEY" \
      --var maven_version="$MAVEN_VERSION" \
      --var git_version="$GIT_VERSION" \
      --var jdk11_version="$JDK11_VERSION" \
      --var jdk8_version="$JDK8_VERSION" \
      --var git_lfs_version="$GIT_LFS_VERSION" \
      --var compose_version="$COMPOSE_VERSION" \
      "./${CLOUD}/${AGENT}-agent.${ARCHITECTURE}.json"
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
