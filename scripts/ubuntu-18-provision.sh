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

## This function installs the package provided as arg. $1
# with the latest version specified as arg. $2.
# When there are different packages builds available for the provided version
# then the most recent one ise installed
function install_package_version() {
  local package_version
  package_version="$(apt-cache madison "${1}" \
    | grep "${2}" `# Extract all candidate packages with this version` \
    | head -n1 `# Only keep the most recent package which should be the first line` \
    | awk '{print $3}' `# Package version is the 3rd column`)"
  apt-get install -y --no-install-recommends "${1}=${package_version}"
}

## Copy custom scripts
cp /tmp/add_auth_key_to_user.sh /usr/local/bin/add_auth_key_to_user.sh
chmod a+x /usr/local/bin/add_auth_key_to_user.sh

## Disable and Remove Unattended APT Upgrades
echo 'APT::Periodic::Enable "0";' > /etc/apt/apt.conf.d/10cloudinit-disable
apt purge -y unattended-upgrades

## Remove unused packages
apt purge -y snap lxcfs lxd lxd-client
apt autoremove --purge -y

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
  make \
  unzip \
  zip \
  jq

## Install git
if [ -n "${GIT_VERSION}" ]
then
  ## a specific git version is required: search it on the official git PPA repositories
  add-apt-repository -y ppa:git-core/ppa
  install_package_version git "${GIT_VERSION}"
else
  ## No git version: install the latest git available in the default repos
  apt-get install -y --no-install-recommends git
fi

## Install git-lfs (after git)
git_lfs_deb="/tmp/git-lfs_${GIT_LFS_VERSION}_amd64.deb"
curl --fail --silent --location --show-error --output "${git_lfs_deb}" \
  "https://packagecloud.io/github/git-lfs/packages/debian/stretch/git-lfs_${GIT_LFS_VERSION}_amd64.deb/download"
dpkg -i "${git_lfs_deb}"
rm -f "${git_lfs_deb}"

## OpenJDKs
install_package_version openjdk-11-jdk "${JDK11_VERSION}"
install_package_version openjdk-8-jdk "${JDK8_VERSION}"

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
rm -rf /tmp/* /var/log/*
sync
