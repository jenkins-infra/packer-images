#!/bin/bash
# This script provision the Linux Ubuntu 18 images for Jenkins agents
# Architecture supported: amd64, arm64

set -eux -o pipefail

## Check for environment variables or fail miserably (due to set -u enabled)
echo "== Provisiong jenkins-infra agent for ubuntu 18"
echo "ARCHITECTURE=${ARCHITECTURE}"
echo "COMPOSE_VERSION=${COMPOSE_VERSION}"
echo "MAVEN_VERSION=${MAVEN_VERSION}"

## Ensure the machine is up-to-date
apt-get update
apt-get upgrade -y

## Ensure Docker is installed as per https://docs.docker.com/engine/install/ubuntu/
apt-get install -y --no-install-recommends \
  apt-transport-https \
  ca-certificates \
  curl \
  gnupg-agent \
  software-properties-common

curl --fail --silent --location --show-error https://download.docker.com/linux/ubuntu/gpg | apt-key add -
add-apt-repository "deb [arch=${ARCHITECTURE}] https://download.docker.com/linux/ubuntu bionic stable"
apt-get update
apt-get install -y --no-install-recommends docker-ce

## Ensure that the Jenkins Agent commons requirements are installed
apt-get install -y --no-install-recommends \
  openjdk-8-jdk \
  openjdk-11-jdk \
  make \
  unzip \
  zip \
  jq \
  git

## Ensure that docker-compose is installed (version from environment)
curl --fail --silent --location --show-error --output /usr/local/bin/docker-compose \
  "https://github.com/docker/compose/releases/download/${COMPOSE_VERSION}/docker-compose-Linux-x86_64"

## Ensure that maven is installed and configured (version from environment)
curl --fail --silent --location --show-error --output "/tmp/apache-maven-${MAVEN_VERSION}-bin.tar.gz" \
  "https://archive.apache.org/dist/maven/maven-3/${MAVEN_VERSION}/binaries/apache-maven-${MAVEN_VERSION}-bin.tar.gz"

tar zxf "/tmp/apache-maven-${MAVEN_VERSION}-bin.tar.gz" -C /usr/share/
ln -s "/usr/share/apache-maven-${MAVEN_VERSION}/bin/mvn" /usr/bin/mvn
rm -f "/tmp/apache-maven-${MAVEN_VERSION}-bin.tar.gz"


## Ensure that there is a user named "jenkins" created and configured
username=jenkins
userid=1001
userhome=/home/jenkins
groupname=jenkins
groupid=1001

groupadd --gid="${groupid}" "${groupname}"

# jenkins should not be able to run sudo commands
useradd --create-home \
  --home-dir "${userhome}" \
  --uid "${userid}" \
  --gid "${groupid}" \
  --groups docker \
  --shell /bin/bash \
  "${username}"

## Ensure that the VM is cleaned up
export HISTSIZE=0
sync
