#!/bin/bash
# This script provision the Linux Ubuntu 20 images for Jenkins agents
# Architecture supported: amd64, arm64

set -eux -o pipefail

## Check for environment variables or fail miserably (due to set -u enabled)
echo "== Provisiong jenkins-infra agent for ubuntu 20"
echo "ARCHITECTURE=${ARCHITECTURE}"
echo "COMPOSE_VERSION=${COMPOSE_VERSION}"
echo "MAVEN_VERSION=${MAVEN_VERSION}"
export DEBIAN_FRONTEND=noninteractive
ubuntu_codename="$(grep UBUNTU_CODENAME /etc/os-release | cut -d = -f 2)"

## Check for presence of requirements or fail fast
for cli in add-apt-repository apt-get apt-cache awk curl grep groupadd head tar uname useradd
do
  if ! command -v $cli >/dev/null 2>&1
  then
    echo "ERROR: command line ${cli} required but not found. Exiting."
    exit 1
  fi
done

## This function installs the package provided as arg. $1
# with the latest version specified as arg. $2.
# When there are different packages builds available for the provided version
# then the most recent one ise installed
function install_package_version() {
  local package_version

  package_version="$(apt-cache madison "${1}" \
    | grep "${2}" `# Extract all candidate packages with this version` \
    | head -n1 `# Only keep the most recent package which should be the first line` \
    | awk '{print $3}' `# Package version is the 3rd column` || { echo "ERROR: could not find version $2 for $1. Output of apt-cache madison is: $(apt-cache madison "${1}")"; exit 1; } )"

  apt-get install -y --no-install-recommends "${1}=${package_version}"
}

## Copy custom scripts
cp /tmp/add_auth_key_to_user.sh /usr/local/bin/add_auth_key_to_user.sh
chmod a+x /usr/local/bin/add_auth_key_to_user.sh

## Disable and Remove Unattended APT Upgrades
echo 'APT::Periodic::Enable "0";' > /etc/apt/apt.conf.d/10cloudinit-disable
apt-get purge -y unattended-upgrades || true # Do not fail if the package does not exist

## Remove unused packages
apt-get purge -y snap lxd || true # Do not fail if the package does not exist
apt-get autoremove --purge -y

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
add-apt-repository "deb [arch=${ARCHITECTURE}] https://download.docker.com/linux/ubuntu ${ubuntu_codename} stable"
apt-get update
apt-get install -y --no-install-recommends docker-ce

## Ensure that the Jenkins Agent commons requirements are installed
apt-get install -y --no-install-recommends \
  make \
  unzip \
  zip \
  jq \
  parallel

# setup qemu
apt-get install -y --no-install-recommends \
  qemu \
  binfmt-support \
  qemu-user-static

if [ "$(uname -m)" = "x86_64" ]; then
  docker run --rm --privileged multiarch/qemu-user-static --reset -p yes || true # Never fail
fi

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
git_lfs_archive="git-lfs-linux-${ARCHITECTURE}-v${GIT_LFS_VERSION}.tar.gz"
git_lfs_release_url="https://github.com/git-lfs/git-lfs/releases/download/v${GIT_LFS_VERSION}/${git_lfs_archive}"

curl --fail --silent --location --show-error --output "/tmp/${git_lfs_archive}" "${git_lfs_release_url}"
mkdir -p /tmp/git-lfs
tar xzvf "/tmp/${git_lfs_archive}" -C /tmp/git-lfs
bash -x /tmp/git-lfs/install.sh # Execute in debug mode in case something goes wrong
rm -rf /tmp/git-lfs*

## Install JDK needed component
## Prevent Java null pointer exception due to missing fontconfig
apt-get install -y --no-install-recommends fontconfig

## OpenJDKs: Adoptium - https://adoptium.net/installation.html
mkdir -p /opt/jdk-8 /opt/jdk-11 /opt/jdk-17

# JDK8
jdk8_short_version="${JDK8_VERSION//-/}"
cpu_arch_short="$(uname -m)"
if test "${cpu_arch_short}" == "x86_64"
then
  # Damn :'(
  cpu_arch_short="x64"
fi
curl -sSL -o /tmp/jdk8.tgz \
  "https://github.com/adoptium/temurin8-binaries/releases/download/jdk${JDK8_VERSION}/OpenJDK8U-jdk_${cpu_arch_short}_linux_hotspot_${jdk8_short_version}.tar.gz"
tar xzf /tmp/jdk8.tgz --strip-components=1 -C /opt/jdk-8

# JDK11
jdk11_short_version="${JDK11_VERSION//+/_}"
curl -sSL -o /tmp/jdk11.tgz \
  "https://github.com/adoptium/temurin11-binaries/releases/download/jdk-${JDK11_VERSION}/OpenJDK11U-jdk_${cpu_arch_short}_linux_hotspot_${jdk11_short_version}.tar.gz"
tar xzf /tmp/jdk11.tgz --strip-components=1 -C /opt/jdk-11

# JDK17
jdk17_short_version="${JDK17_VERSION//+/_}"
curl -sSL -o /tmp/jdk17.tgz \
  "https://github.com/adoptium/temurin17-binaries/releases/download/jdk-${JDK17_VERSION}/OpenJDK17-jdk_${cpu_arch_short}_linux_hotspot_${jdk17_short_version}.tar.gz"
tar xzf /tmp/jdk17.tgz --strip-components=1 -C /opt/jdk-17

# Define JDK installations
# The priority of a JDK is the last argument.
# Starts by setting priority to the JDK major version: higher version is the expected default
update-alternatives --install /usr/bin/java java /opt/jdk-8/bin/java 8
update-alternatives --install /usr/bin/java java /opt/jdk-11/bin/java 11
update-alternatives --install /usr/bin/java java /opt/jdk-17/bin/java 17
# Then, use the DEFAULT_JDK env var to set the priority of the specified default JDK to 1000 to ensure its the one used by update-alternatives
update-alternatives --install /usr/bin/java java "/opt/jdk-${DEFAULT_JDK}/bin/java" 1000
echo "JAVA_HOME=/opt/jdk-${DEFAULT_JDK}" >> /etc/environment

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
