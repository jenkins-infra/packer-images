#!/bin/bash
# This script provision the Linux Ubuntu 18 images for Jenkins agents
# Architecture supported: amd64, arm64

set -eux -o pipefail

## Check for environment variables or fail miserably (due to set -u enabled)
echo "== Provisiong jenkins-infra agent for ubuntu 18"
echo "ARCHITECTURE=${ARCHITECTURE}"
echo "COMPOSE_VERSION=${COMPOSE_VERSION}"
echo "MAVEN_VERSION=${MAVEN_VERSION}"
export DEBIAN_FRONTEND=noninteractive

## Copy custom scripts
cp /tmp/add_auth_key_to_user.sh /usr/local/bin/add_auth_key_to_user.sh
chmod a+x /usr/local/bin/add_auth_key_to_user.sh

## Disable and Remove Unattended APT Upgrades
echo 'APT::Periodic::Enable "0";' > /etc/apt/apt.conf.d/10cloudinit-disable
apt purge -y unattended-upgrades

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
  jq

## Install git
if [ -n "${GIT_VERSION}" ]
then
  ## a specific git version is required: search it on the official git PPA repositories
  add-apt-repository -y ppa:git-core/ppa
  GIT_PACKAGE_VERSION="$(apt-cache madison git \
    | grep "${GIT_VERSION}" `# Extract all candidate packages with this version` \
    | head -n1 `# Only keep the most recent package which should be the first line` \
    | awk '{print $3}' `# Package version is the 3rd column`)"
  apt-get install -y --no-install-recommends git="${GIT_PACKAGE_VERSION}"
else
  ## No git version: install the latest git available in the default repos
  apt-get install -y --no-install-recommends git
fi

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

# Add authorized keys to jenkins user
mkdir -p "${userhome}/.ssh"
curl --fail --silent --location --show-error "${OPENSSH_AUTHORIZED_KEYS_URL}" --output "${userhome}/.ssh/authorized_keys"
chmod 0700 "${userhome}/.ssh"
chmod 0600 "${userhome}/.ssh/authorized_keys"
chown -R jenkins:jenkins "${userhome}/.ssh"

## Ensure that the VM is cleaned up
export HISTSIZE=0
sync
