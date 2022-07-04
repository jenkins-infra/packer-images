#!/bin/bash
# This script provision the Linux Ubuntu 20 images for Jenkins agents
# Architecture supported: amd64, arm64

set -eux -o pipefail

## Check for environment variables or fail miserably (due to set -u enabled)
echo "== Provisiong jenkins-infra agent for ubuntu 20"
echo "ARCHITECTURE=${ARCHITECTURE}"
export DEBIAN_FRONTEND=noninteractive

## This function checks a list of commands are working, and exits with code 1 if not
function check_commands() {
  ## Check for presence of requirements or fail fast
  for cli in add-apt-repository apt-get apt-cache awk curl grep groupadd head tar uname useradd
  do
    if ! command -v $cli >/dev/null 2>&1
    then
      echo "ERROR: command line ${cli} required but not found. Exiting."
      exit 1
    fi
  done
}

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

  apt-get install --yes --no-install-recommends "${1}=${package_version}"
}

## Copy custom scripts
function copy_custom_scripts() {
  cp /tmp/add_auth_key_to_user.sh /usr/local/bin/add_auth_key_to_user.sh
  chmod a+x /usr/local/bin/add_auth_key_to_user.sh
}

## All the clean for apt
function clean_apt() {
  ## Disable and remove Unattended APT upgrades
  echo 'APT::Periodic::Enable "0";' > /etc/apt/apt.conf.d/10cloudinit-disable
  apt-get purge -y unattended-upgrades || true # Do not fail if the package does not exist

  ## Remove unused packages
  apt-get purge -y snap lxd || true # Do not fail if the package does not exist
  apt-get autoremove --purge -y

  ## Ensure the machine is up-to-date
  apt-get update
  apt-get upgrade -y
}

## Ensure Docker is installed as per https://docs.docker.com/engine/install/ubuntu/
function install_docker() {
  apt-get update --quiet
  apt-get install --yes --no-install-recommends \
    ca-certificates \
    curl \
    gnupg \
    lsb-release \
    gnupg-agent \
    software-properties-common

  gpg --batch --yes --dearmor -o /usr/share/keyrings/docker-archive-keyring.gpg /tmp/docker.gpg

  echo \
    "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/docker-archive-keyring.gpg] https://download.docker.com/linux/ubuntu \
    $(lsb_release -cs) stable" | tee /etc/apt/sources.list.d/docker.list > /dev/null
  apt-get update --quiet
  apt-get install --yes --no-install-recommends docker-ce
}

## Ensure that the Jenkins Agent commons requirements are installed
function install_JA_requirements(){
  apt-get install --yes --no-install-recommends \
    make \
    unzip \
    zip \
    jq="${JQ_VERSION}*" `# This package exists for both intel and ARM on Ubuntu 20.04. Fix version to ensure constant behavior.` \
    parallel
}

## setup qemu
function install_qemu() {
  apt-get install --yes --no-install-recommends \
    qemu \
    binfmt-support \
    qemu-user-static

  if [ "$(uname -m)" = "x86_64" ]; then
    docker run --rm --privileged multiarch/qemu-user-static --reset -p yes || true # Never fail
  fi
}

## Install Python 3
function install_python() {
  apt-get install --yes --no-install-recommends \
    python3 \
    python3-docker \
    python3-pip \
    python3-venv \
    python3-wheel
  python3 -m pip install --no-cache-dir pip --upgrade
}

## Install git and git-lfs
function install_git_gitlfs() {
  if [ -n "${GIT_LINUX_VERSION}" ]
  then
    ## a specific git version is required: search it on the official git PPA repositories
    add-apt-repository -y ppa:git-core/ppa
    install_package_version git "${GIT_LINUX_VERSION}"
  else
    ## No git version: install the latest git available in the default repos
    apt-get install --yes --no-install-recommends git
  fi

  ## Install git-lfs (after git)
  git_lfs_archive="git-lfs-linux-${ARCHITECTURE}-v${GIT_LFS_VERSION}.tar.gz"
  git_lfs_release_url="https://github.com/git-lfs/git-lfs/releases/download/v${GIT_LFS_VERSION}/${git_lfs_archive}"

  curl --fail --silent --location --show-error --output "/tmp/${git_lfs_archive}" "${git_lfs_release_url}"
  mkdir -p /tmp/git-lfs
  tar --extract --directory=/tmp/git-lfs --gzip --verbose --file="/tmp/${git_lfs_archive}" --strip-components=1 #strip the 1st-level directory of the archive as it has a changing name, since git-lfs 3.2.0.
  bash -x /tmp/git-lfs/install.sh # Execute in debug mode in case something goes wrong
  rm -rf /tmp/git-lfs*
}

function install_jdk() {
  ## Prevent Java null pointer exception due to missing fontconfig
  apt-get install --yes --no-install-recommends fontconfig

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
    "https://github.com/adoptium/temurin17-binaries/releases/download/jdk-${JDK17_VERSION}/OpenJDK17U-jdk_${cpu_arch_short}_linux_hotspot_${jdk17_short_version}.tar.gz"
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
}

## Ensure that docker-compose is installed (version from environment)
function install_docker_compose(){
  curl --fail --silent --location --show-error --output /usr/local/bin/docker-compose \
    "https://github.com/docker/compose/releases/download/v${COMPOSE_VERSION}/docker-compose-Linux-$(uname -m)"
  chmod a+x /usr/local/bin/docker-compose
}

## Ensure that maven is installed and configured (version from environment)
function install_maven() {
  curl --fail --silent --location --show-error --output "/tmp/apache-maven-${MAVEN_VERSION}-bin.tar.gz" \
    "https://archive.apache.org/dist/maven/maven-3/${MAVEN_VERSION}/binaries/apache-maven-${MAVEN_VERSION}-bin.tar.gz"

  tar zxf "/tmp/apache-maven-${MAVEN_VERSION}-bin.tar.gz" -C /usr/share/
  ln -s "/usr/share/apache-maven-${MAVEN_VERSION}/bin/mvn" /usr/bin/mvn
  rm -f "/tmp/apache-maven-${MAVEN_VERSION}-bin.tar.gz"
}

## Ensure that hadolint is installed
function install_hadolint() {
  hadolint_arch_suffix="${ARCHITECTURE}"
  if [ "${hadolint_arch_suffix}" == "amd64" ]; then
    hadolint_arch_suffix="x86_64"
  fi
  curl --fail --silent --location --show-error --output /usr/local/bin/hadolint \
    "https://github.com/hadolint/hadolint/releases/download/v${HADOLINT_VERSION}/hadolint-Linux-${hadolint_arch_suffix}"
  chmod a+x /usr/local/bin/hadolint
}

## Ensure that google container-structure-test is installed
function install_cst() {
  curl --fail --silent --location --show-error --output /usr/local/bin/container-structure-test \
    "https://github.com/GoogleContainerTools/container-structure-test/releases/download/v${CST_VERSION}/container-structure-test-linux-${ARCHITECTURE}"
  chmod a+x /usr/local/bin/container-structure-test
}

## Ensure that jx-release-version is installed
function install_jxreleaseversion() {
  curl --fail --silent --location --show-error --output /tmp/jx-release-version.tgz \
    "https://github.com/jenkins-x-plugins/jx-release-version/releases/download/v${JXRELEASEVERSION_VERSION}/jx-release-version-linux-${ARCHITECTURE}.tar.gz"
  tar -xzf /tmp/jx-release-version.tgz -C /tmp
  cp /tmp/jx-release-version /usr/local/bin/jx-release-version
  rm -rf /tmp/*
}

## Ensure that azure-cli is installed
function install_azurecli() {
  ## From https://github.com/Azure/azure-cli/issues/7368#issuecomment-921578936
  apt-get install --yes --no-install-recommends \
    gcc \
    libffi-dev \
    libsodium-dev \
    python3-dev
  export SODIUM_INSTALL="system"
  python3 -m pip install --no-cache-dir pynacl
  # Using the Python installation to ensure that both Intel and ARM are supported (Microsoft only provides a package for Intel)
  python3 -m pip install --no-cache-dir azure-cli=="${AZURECLI_VERSION}"
}

## Ensure that the GitHub command line (`gh`) is installed
function install_gh() {
  curl --silent --show-error --location --output /tmp/gh.tar.gz \
    "https://github.com/cli/cli/releases/download/v${GH_VERSION}/gh_${GH_VERSION}_linux_${ARCHITECTURE}.tar.gz"
  tar xvfz /tmp/gh.tar.gz -C /tmp
  cp "/tmp/gh_${GH_VERSION}_linux_${ARCHITECTURE}/bin/gh" /usr/local/bin/gh
  rm -rf /tmp/*
}

## Install Vagrant as per https://www.vagrantup.com/downloads
function install_vagrant() {
  curl --fail --silent --show-error --location https://apt.releases.hashicorp.com/gpg | apt-key add -
  apt-add-repository "deb [arch=${ARCHITECTURE}] https://apt.releases.hashicorp.com $(lsb_release -cs) main"
  if test "${ARCHITECTURE}" == "amd64"
  then
    install_package_version vagrant "${VAGRANT_VERSION}"
  else
    # Support of vagrant on other CPUs than AMD64 is partial: version are not always the same.
    # As it is an edge case
    apt-get install --yes --no-install-recommends vagrant
  fi
}

## Ensure that there is a user named "jenkins" created and configured
function setuser() {
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
}

## Ensure that the VM is cleaned up
function cleanup() {
  export HISTSIZE=0
  rm -rf /tmp/* /var/log/*
  sync
}

function sanity_check() {
  echo "== Sanity Check of installed tools"
  az --version
  container-structure-test version
  docker -v ## Client only
  docker-compose -v
  gh --version
  git --version
  git-lfs --version
  hadolint -v
  java -version
  jq --version
  jx-release-version -version
  make --version
  mvn -v
  parallel --version
  python3 --version
  unzip -v
  vagrant -v
  zip -v
  echo "== End of sanity check"
  echo "== Installed packages:"
  dpkg -l
}

function main() {
  check_commands
  copy_custom_scripts
  clean_apt
  install_docker
  install_JA_requirements
  install_qemu
  install_python
  install_git_gitlfs
  install_jdk
  install_docker_compose
  install_maven
  install_hadolint
  install_cst
  install_jxreleaseversion
  install_azurecli
  install_gh
  install_vagrant
  setuser
  cleanup
}

main
sanity_check
