#!/bin/bash
# This script provision the Linux Ubuntu 20 images for Jenkins agents
# Architecture supported: amd64, arm64

set -eux -o pipefail

## Check for environment variables or fail miserably (due to set -u enabled)
echo "== Provisiong jenkins-infra agent for ubuntu 20"
case "$(uname -m)" in
    x86_64)
      if test "${ARCHITECTURE}" != "amd64"; then
        echo "Architecture mismatch: $(uname -m) != ${ARCHITECTURE}"
        exit 1
      fi
      ;;
    arm64 | aarch64) # macOS M1 arm64 while ubuntu 20 is aarch64
      if test "${ARCHITECTURE}" != "arm64"; then
        echo "Architecture mismatch: $(uname -m) != ${ARCHITECTURE}"
        exit 1
      fi
      ;;
    *)
      echo "Unsupported architecture: $(uname -m)"
      exit 1
      ;;
esac
echo "ARCHITECTURE=${ARCHITECTURE}"
export DEBIAN_FRONTEND=noninteractive

## Setting up the default Jenkins user
username=jenkins
userid=1001
userhome=/home/jenkins
groupname=jenkins
groupid=1001
install_dir=/usr/local/bin
asdf_install_dir="${userhome}/.asdf"
launchable_venv_dir="/usr/local/launchable"

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
  cp /tmp/{add_auth_key_to_user.sh,get-fileshare-signed-url.sh} /usr/local/bin/
  chmod a+x /usr/local/bin/add_auth_key_to_user.sh /usr/local/bin/get-fileshare-signed-url.sh
}

## Set the locale
function set_locale(){
  echo "LC_ALL=${LC_ALL}" >> /etc/environment
  echo "${LANG} ${LANG##*.}" >> /etc/locale.gen
  echo "LANG=${LANG}" > /etc/locale.conf
  locale-gen "${LANG}"
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
  apt-get update --quiet
  apt-get upgrade -y
}

function install_common_requirements() {
  apt-get update --quiet
  apt-get install --yes --no-install-recommends \
    apt-transport-https \
    ca-certificates `# Adds certificate authority for proper use of TLS` \
    curl `# A nice HTTP client` \
    dnsutils `# Provides dig(1)` \
    lsb-release `# Provides CLI for distribution detction` \
    gpg-agent `# Required for GPG management` \
    rsync `# Differential copy is quite useful` \
    software-properties-common `# Provides a LOT of APT utilities`
}

function install_ssh_requirements() {
  apt-get update --quiet
  apt-get install --yes --no-install-recommends openssh-client
}

## Ensure that there is a user named "jenkins" created and configured
function setuser() {
  groupadd --gid="${groupid}" "${groupname}"

  # jenkins should not be able to run sudo commands
  useradd --create-home \
    --home-dir "${userhome}" \
    --uid "${userid}" \
    --gid "${groupid}" \
    --shell /bin/bash \
    "${username}"

  # Add authorized keys to jenkins user
  mkdir -p "${userhome}/.ssh"
  curl --fail --silent --location --show-error "${OPENSSH_AUTHORIZED_KEYS_URL}" --output "${userhome}/.ssh/authorized_keys"
  chmod 0700 "${userhome}/.ssh"
  chmod 0600 "${userhome}/.ssh/authorized_keys"
  chown -R "${username}:${groupname}" "${userhome}/.ssh"

  # Create agent folder
  mkdir -p "${userhome}/agent"
  chown -R "${username}:${groupname}" "${userhome}/agent"
}

## Install asdf on the default user's home
function install_asdf() {
  local archive profile_script
  archive=/tmp/asdf.tgz
  profile_script="${userhome}/.bashrc"

  if test -f "${userhome}/.asdf/asdf.sh"
  then
    return 0
  fi
  test -d "${userhome}"

  curl --fail --silent --show-error --location "https://github.com/asdf-vm/asdf/archive/refs/tags/v${ASDF_VERSION}.tar.gz" --output "${archive}"
  mkdir -p "${asdf_install_dir}"
  tar --extract --gunzip --file="${archive}" --directory="${asdf_install_dir}" --strip-components=1 #strip the 1st-level directory of the archive as it has a changing name (asdf-<version>)

  touch "${profile_script}"
  echo ". ${asdf_install_dir}/asdf.sh" >> "${profile_script}"
  chown -R "${username}:${groupname}" "${userhome}"
  rm -f "${archive}"

  ## append to the system wide path variable, need to be seconded for docker in packer sources.pkr.hcl
  ## https://backreference.org/2010/02/20/using-different-delimiters-in-sed/index.html
  sed --in-place --regexp-extended "s|^PATH=\"(.*)\"$|PATH=\"${asdf_install_dir}/shims:${asdf_install_dir}/bin:\1\"|" /etc/environment
}

## Install the ASDF Plugin passed as argument ($1 is the name and $2 the URL)
function install_asdf_plugin() {
  local plugin_name="${1}"
  local plugin_url="${2}"

  # Git is required to install asdf plugins
  command -v git >/dev/null 2>&1

  su - "${username}" -c "source ${asdf_install_dir}/asdf.sh && asdf plugin add ${plugin_name} ${plugin_url}"
}

## Install an ASDF Package in the default user's ASDF installation and mark it as the default global installation
function install_asdf_package() {
  local package_name="${1}"
  local package_version="${2}"

  # Git is required to install asdf packages
  command -v git >/dev/null 2>&1

  su - "${username}" -c "source ${asdf_install_dir}/asdf.sh && asdf install ${package_name} ${package_version}"
  su - "${username}" -c "source ${asdf_install_dir}/asdf.sh && asdf global ${package_name} ${package_version}"
}

## Ensure Docker is installed as per https://docs.docker.com/engine/install/ubuntu/
function install_docker() {
  keyring_file=/usr/share/keyrings/docker-archive-keyring.gpg
  gpg --batch --yes --dearmor -o "${keyring_file}" /tmp/gpg-keys/docker.gpg
  chmod a+r "${keyring_file}"

  echo "deb [arch=$(dpkg --print-architecture) signed-by=${keyring_file}] https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable" > /etc/apt/sources.list.d/docker.list
  apt-get update --quiet

  # Install pinned version
  apt-get install --yes --no-install-recommends \
    docker-ce="5:${DOCKER_VERSION}*" \
    docker-ce-cli="5:${DOCKER_VERSION}*" \
    docker-buildx-plugin

  # Allow the default user to use Docker. https://docs.docker.com/engine/install/linux-postinstall/
  # Please note that it gives effectively full root permissions to this user so these compute instances must be ephemeral
  usermod -aG docker "${username}"
}

## Ensure Golang is installed
function install_golang(){
  ## will be installed in /usr/local/bin
  golang_download_url="https://go.dev/dl/go${GOLANG_VERSION}.linux-${ARCHITECTURE}.tar.gz"
  curl --fail --silent --show-error --location "${golang_download_url}" | \
    tar --extract --gunzip --directory="/usr/local/"
  ## append to the system wide path variable, need to be seconded for docker in packer sources.pkr.hcl
  sed -e '/^PATH/s/"$/:\/usr\/local\/go\/bin"/g' -i /etc/environment
  ## Default GOPATH need to be created
  mkdir -p "${userhome}/go"
  chown jenkins:jenkins "${userhome}/go"
}

## Ensure GolangCIlint is installed
function install_golangcilint(){
  ## will be installed in /usr/local/bin
  golangcilint_download_url="https://www.github.com/golangci/golangci-lint/releases/download/v${GOLANGCILINT_VERSION}/golangci-lint-${GOLANGCILINT_VERSION}-linux-${ARCHITECTURE}.tar.gz"
  curl --fail --silent --show-error --location "${golangcilint_download_url}" | \
    tar --extract --gunzip --strip-components=1 --directory="/usr/local/bin/" "golangci-lint-${GOLANGCILINT_VERSION}-linux-${ARCHITECTURE}/golangci-lint"
}

## Ensure that the Jenkins Agent commons requirements are installed
function install_JA_requirements(){
  apt-get update --quiet
  # JQ_VERSION is an env var provided outside of the script
  # shellcheck disable=SC2153
  apt-get install --yes --no-install-recommends \
    make \
    unzip \
    zip \
    jq="${JQ_VERSION}*" `# This package exists for both intel and ARM on Ubuntu 20.04. Fix version to ensure constant behavior.` \
    parallel
}

## setup qemu
function install_qemu() {
  apt-get update --quiet
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
  apt-get update --quiet
  apt-get install --yes --no-install-recommends \
    python3 \
    python3-docker \
    python3-pip \
    python3-venv \
    python3-wheel
  python3 -m pip install --no-cache-dir pip --upgrade
}

## Install chromium
### Using chromium because chrome is not available on arm64
### see https://bugs.chromium.org/p/chromium/issues/detail?id=677140
function install_chromium() {
  apt-get remove --yes chromium-browser chromium-browser-l10n chromium-codecs-ffmpeg-extra

  # Using this PPA as the chromium default repositories require snap which doesn't work in docker.
  # see https://askubuntu.com/questions/1255692/is-it-still-possible-to-install-chromium-as-a-deb-package-on-20-04-lts-using-som
  add-apt-repository --yes ppa:phd/chromium-browser
  apt-get update --quiet

  # Pin 'chromium' package to this PPA repository (to avoid chromium installed from another source)
  # Then the candidate will always be the 18.04 package version (20.04 packages require snap but snap does not run inside Docker)
  # Check with apt-cache policy chromium-browser
  echo '
Package: *
Pin: release o=LP-PPA-phd-chromium-browser
Pin-Priority: 1001
' | tee /etc/apt/preferences.d/phd-chromium-browser

  apt-get install --yes chromium-browser
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

## install the jdks major versions for the current os and platform
function install_jdks(){
  for major_jdk_version in ${JDKS}; do
    echo "jdk to install : ${major_jdk_version}"
    installer_url_var="JDK${major_jdk_version}_INSTALLER_URL"
    temp_archive="$(mktemp)"
    installation_dir="/opt/jdk-${major_jdk_version}"
    curl --fail --silent --show-error --location --output "${temp_archive}" "${!installer_url_var}"
    checksum_value_var="JDK${major_jdk_version}_CHECKSUM_VALUE"
    real_checksum=$(sha256sum "${temp_archive}" | awk '{print $1}')
    if [ "${real_checksum}" = "${!checksum_value_var}" ]; then
      mkdir -p "${installation_dir}"
      tar --extract --gunzip --file="${temp_archive}" --directory="${installation_dir}" --strip-components=1
    else
      echo "wrong checksum for ${major_jdk_version} install"
      exit 1
    fi
  done
}

## Ensure that docker-compose is installed (version from environment)
function install_docker_compose(){
  curl --fail --silent --location --show-error --output /usr/local/bin/docker-compose \
    "https://github.com/docker/compose/releases/download/v${COMPOSE_VERSION}/docker-compose-Linux-$(uname -m)"
  chmod a+x /usr/local/bin/docker-compose
}

## Ensure that DOCTL is installed
function install_doctl(){
  curl --fail --silent --location --show-error \
    "https://github.com/digitalocean/doctl/releases/download/v${DOCTL_VERSION}/doctl-${DOCTL_VERSION}-linux-${ARCHITECTURE}.tar.gz" | tar --extract --gunzip --directory="${install_dir}"/ doctl
}

## Ensure that`helm` and its plugins are installed
function install_helm(){
  curl --fail --silent --location --show-error \
    "https://get.helm.sh/helm-v${HELM_VERSION}-linux-${ARCHITECTURE}.tar.gz" | \
    tar --extract --gunzip --strip-components 1 --directory="${install_dir}"/ "linux-${ARCHITECTURE}/helm"

  su - "${username}" -c "helm plugin install https://github.com/databus23/helm-diff --version v${HELM_DIFF_VERSION}"
  su - "${username}" -c "helm plugin install https://github.com/jkroepke/helm-secrets --version v${HELM_SECRETS_VERSION}"
  su - "${username}" -c "helm plugin install https://github.com/aslafy-z/helm-git.git --version v${HELM_GIT_VERSION}"
}

## Ensure that`helmfile` is installed
function install_helmfile(){
  curl --fail --silent --location --show-error \
    "https://github.com/helmfile/helmfile/releases/download/v${HELMFILE_VERSION}/helmfile_${HELMFILE_VERSION}_linux_${ARCHITECTURE}.tar.gz" | \
    tar --extract --gunzip --directory="${install_dir}"/  helmfile
}

## Ensure that`sops` is installed
function install_sops(){
  curl --fail --silent --location --show-error --output "${install_dir}"/sops \
    "https://github.com/mozilla/sops/releases/download/v${SOPS_VERSION}/sops-v${SOPS_VERSION}.linux.${ARCHITECTURE}"
  chmod +x "${install_dir}"/sops
}

## Ensure that maven is installed and configured (version from environment)
function install_maven() {
  # If the Apache mirrors responds an error, we usually fallback to their "archives" system as it hosts older Maven versions
  curl --fail --silent --location --show-error --output "/tmp/apache-maven-${MAVEN_VERSION}-bin.tar.gz" \
    "https://dlcdn.apache.org/maven/maven-3/${MAVEN_VERSION}/binaries/apache-maven-${MAVEN_VERSION}-bin.tar.gz" \
  || curl --fail --silent --location --show-error --output "/tmp/apache-maven-${MAVEN_VERSION}-bin.tar.gz" \
    "https://archive.apache.org/dist/maven/maven-3/${MAVEN_VERSION}/binaries/apache-maven-${MAVEN_VERSION}-bin.tar.gz"

  tar --extract --gunzip --file="/tmp/apache-maven-${MAVEN_VERSION}-bin.tar.gz" --directory=/usr/share/
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
  tar --extract --gunzip --file=/tmp/jx-release-version.tgz --directory=/tmp
  cp /tmp/jx-release-version /usr/local/bin/jx-release-version
  rm -rf /tmp/jx*
}

## Ensure that azure-cli is installed
function install_azurecli() {
  apt-get update --quiet
  apt-get install --yes --no-install-recommends \
    gpg \
    lsb-release
  # Download and install the Microsoft signing key
  mkdir -p /etc/apt/keyrings
  curl -sLS https://packages.microsoft.com/keys/microsoft.asc | gpg --dearmor | tee /etc/apt/keyrings/microsoft.gpg > /dev/null
  chmod go+r /etc/apt/keyrings/microsoft.gpg
  # Add the Azure CLI software repository
  echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/microsoft.gpg] https://packages.microsoft.com/repos/azure-cli/ $(lsb_release -cs) main" | tee /etc/apt/sources.list.d/azure-cli.list
  # Update repository information and install the azure-cli package
  apt-get update --quiet
  apt-get install --yes --no-install-recommends azure-cli="${AZURECLI_VERSION}*"
}

## Ensure that azcopy is installed
function install_azcopy() {
  azcopy_arch="$(uname -m)"
  if [ "${azcopy_arch}" == "aarch64" ]
  then
    azcopy_arch="arm64"
  fi
  azcopy_pkg="$(mktemp)"
  curl --silent --show-error --location --output "${azcopy_pkg}" "https://github.com/Azure/azure-storage-azcopy/releases/download/v${AZCOPY_VERSION}/azcopy-${AZCOPY_VERSION}.${azcopy_arch}.deb"
  dpkg --install "${azcopy_pkg}"
  rm -f "${azcopy_pkg}"
}

## Ensure that the GitHub command line (`gh`) is installed
function install_gh() {
  curl --silent --show-error --location --output /tmp/gh.tar.gz \
    "https://github.com/cli/cli/releases/download/v${GH_VERSION}/gh_${GH_VERSION}_linux_${ARCHITECTURE}.tar.gz"
  tar --extract --gunzip --file=/tmp/gh.tar.gz --directory=/tmp
  cp "/tmp/gh_${GH_VERSION}_linux_${ARCHITECTURE}/bin/gh" /usr/local/bin/gh
  rm -rf /tmp/gh*
}

## Install Vagrant as per https://www.vagrantup.com/downloads
function install_vagrant() {
  local keyring_file=/usr/share/keyrings/hashicorp-archive-keyring.gpg
  gpg --batch --yes --dearmor -o "${keyring_file}" /tmp/gpg-keys/hashicorp.gpg
  chmod a+r "${keyring_file}"
  echo "deb [signed-by=${keyring_file}] https://apt.releases.hashicorp.com $(lsb_release -cs) main" > /etc/apt/sources.list.d/hashicorp.list
  apt update --quiet

  if test "${ARCHITECTURE}" == "amd64"
  then
    install_package_version vagrant "${VAGRANT_VERSION}"
  else
    # Support of vagrant on other CPUs than AMD64 is partial: version are not always the same.
    # As it is an edge case
    apt-get install --yes --no-install-recommends vagrant
  fi
}

## Install Ruby with asdf
function install_ruby() {
  versionToInstall="${1:-$RUBY_VERSION}"
  # Ensure that ASDF is installed
  test -f "${asdf_install_dir}/asdf.sh"
  # Ensure that require dependencies are present to install Ruby
  apt-get update --quiet
  apt-get install --yes --no-install-recommends autoconf bison build-essential libssl-dev libyaml-dev libreadline6-dev zlib1g-dev libncurses5-dev libffi-dev libgdbm6 libgdbm-dev libdb-dev
  # Install Ruby with ASDF and set it as default installation
  install_asdf_plugin ruby https://github.com/asdf-vm/asdf-ruby.git
  install_asdf_package ruby "${versionToInstall}"
}

## Install Xq
function install_xq() {
  curl --fail --silent --location --show-error \
    "https://github.com/sibprogrammer/xq/releases/download/v${XQ_VERSION}/xq_${XQ_VERSION}_linux_${ARCHITECTURE}.tar.gz" | tar --extract --gunzip --directory="${install_dir}"/ xq
}

## Install Yq with asdf
function install_yq() {
  curl --fail --silent --show-error --output "${install_dir}/yq" --location \
    "https://github.com/mikefarah/yq/releases/download/v${YQ_VERSION}/yq_linux_${ARCHITECTURE}"
  chmod a+x "${install_dir}/yq"
}

## Install Packer with ASDF (because it checks for integrity with the Hashicorp GPG key)
function install_packer() {
  # Ensure that ASDF is installed
  test -f "${asdf_install_dir}/asdf.sh"

  # Install packer with ASDF and set it as default installation
  install_asdf_plugin packer https://github.com/asdf-community/asdf-hashicorp.git
  install_asdf_package packer "${PACKER_VERSION}"
}

## Install Datadog agent but not starting it and not enabling it (that will be the role of the system spinning up VM through cloud-init usually)
function install_datadog() {
  keyring_file=/usr/share/keyrings/datadog-keyring.gpg
  gpg --batch --yes --dearmor -o "${keyring_file}" /tmp/gpg-keys/datadog.gpg
  chmod a+r "${keyring_file}"
  echo "deb [signed-by=${keyring_file}] https://apt.datadoghq.com/ stable 7" > /etc/apt/sources.list.d/datadog.list

  apt-get update --quiet
  apt-get install --yes --no-install-recommends datadog-agent datadog-signing-keys
  # Disabling service at startup to avoid error log before cloud-init providing the datadog parameters
  systemctl disable datadog-agent
}

function install_updatecli() {
  local archive_path=/var/cache/apt/archives/updatecli.deb
  curl --silent --location --show-error "https://github.com/updatecli/updatecli/releases/download/v${UPDATECLI_VERSION}/updatecli_${ARCHITECTURE}.deb" --output "${archive_path}"
  dpkg -i "${archive_path}"
  rm -f "${archive_path}"
}

# https://docs.aws.amazon.com/cli/latest/userguide/getting-started-version.html
function install_awscli() {
  local archive_path download_url
  archive_path=/tmp/awscli.zip
  download_url="https://awscli.amazonaws.com/awscli-exe-linux-x86_64-${AWSCLI_VERSION}.zip"
  if test "${ARCHITECTURE}" == "arm64"
  then
    download_url="https://awscli.amazonaws.com/awscli-exe-linux-aarch64-${AWSCLI_VERSION}.zip"
  fi
  curl --silent --location --show-error "${download_url}" --output "${archive_path}"
  unzip "${archive_path}" -d /tmp
  bash /tmp/aws/install
  rm -rf /tmp/aws*
}

function install_netlifydeploy() {
  local archive_path download_url
  archive_path=/tmp/netlifydeploy.tgz
  download_url="https://github.com/halkeye/netlify-golang-deploy/releases/download/v${NETLIFYDEPLOY_VERSION}/netlify-golang-deploy_${NETLIFYDEPLOY_VERSION}_Linux_x86_64.tar.gz"
  if test "${ARCHITECTURE}" == "arm64"
  then
    download_url="https://github.com/halkeye/netlify-golang-deploy/releases/download/v${NETLIFYDEPLOY_VERSION}/netlify-golang-deploy_${NETLIFYDEPLOY_VERSION}_Linux_arm64.tar.gz"
  fi
  curl --silent --location --show-error "${download_url}" --output "${archive_path}"
  tar --extract --gunzip --file="${archive_path}" --directory=/tmp
  mv /tmp/netlify-golang-deploy /usr/local/bin/netlify-deploy
  rm -rf /tmp/netlify*
}

function install_terraform(){
  apt-get update --quiet
  apt-get install --yes --no-install-recommends curl unzip # Should already be there but this function should be autonomous

  local archive_path download_url
  archive_path=/tmp/terraform.zip
  download_url="https://releases.hashicorp.com/terraform/${TERRAFORM_VERSION}/terraform_${TERRAFORM_VERSION}_linux_${ARCHITECTURE}.zip"
  curl --silent --show-error --location --output "${archive_path}" "${download_url}"
  unzip "${archive_path}" -d /usr/local/bin
  rm -f "${archive_path}"
}

function install_kubectl() {
  apt-get update --quiet
  apt-get install --yes --no-install-recommends curl # Should already be there but this function should be autonomous

  curl --silent --location --show-error "https://dl.k8s.io/release/v${KUBECTL_VERSION}/bin/linux/${ARCHITECTURE}/kubectl" --output /usr/local/bin/kubectl
  chmod a+x /usr/local/bin/kubectl
}

## Ensure Goss is installed
function install_goss() {
  apt-get update --quiet
  apt-get install --yes --no-install-recommends curl # Should already be there but this function should be autonomous

  curl --silent --location --show-error "https://github.com/goss-org/goss/releases/download/v${GOSS_VERSION}/goss-linux-${ARCHITECTURE}" --output /usr/local/bin/goss
  chmod +rx /usr/local/bin/goss
}

function install_trivy() {
  apt-get update --quiet
  apt-get install --yes --no-install-recommends curl # Should already be there but this function should be autonomous

  trivy_arch="64bit"
  if test "${ARCHITECTURE}" == "arm64"
  then
    trivy_arch="ARM64"
  fi

  downloaded_archive=/tmp/trivy.tgz

  curl --silent --location --show-error --output "${downloaded_archive}" \
    "https://github.com/aquasecurity/trivy/releases/download/v${TRIVY_VERSION}/trivy_${TRIVY_VERSION}_Linux-${trivy_arch}.tar.gz"

  # Only extract the binary
  tar --extract --gunzip --file="${downloaded_archive}" --directory=/usr/local/bin trivy

  rm -rf /tmp/trivy*
}

## Install Nodejs with asdf
function install_nodejs() {
  # Ensure that ASDF is installed
  test -f "${asdf_install_dir}/asdf.sh"
  # Install Node.js with ASDF and set it as default installation
  install_asdf_plugin nodejs https://github.com/asdf-vm/asdf-nodejs.git
  install_asdf_package nodejs "${NODEJS_LINUX_VERSION}"

  # Bump NPM to its latest available version
  su - "${username}" -c "source ${asdf_install_dir}/asdf.sh && npm install -g npm"
}

function install_playwright() {
  ### Install playwright's dependencies before the module itself
  ## The command 'npx playwright install-deps --dry-run' prints the expectd command for installing dependencies.
  # But this command requires `sudo` access (which the ${username} user does not have).
  # Also, the `root` user does not have access to the ASDF setup.
  # Don't forget to change dir and to remove any `stderr` to avoid polluting the evakuated command
  playwright_deps_install_command="$(su - "${username}" -c "\
    source ${asdf_install_dir}/asdf.sh \
    && npx playwright install-deps --dry-run" \
  2>/dev/null)"
  eval "${playwright_deps_install_command}"

  # Install pinned playwright globally
  su - "${username}" -c "source ${asdf_install_dir}/asdf.sh && npm install -g playwright@${PLAYWRIGHT_VERSION}"
}

## Install Launchable with python3 in its own virtual environment
function install_launchable() {
  python3 -m venv "${launchable_venv_dir}"
  "${launchable_venv_dir}"/bin/pip --require-virtualenv --no-cache-dir install setuptools wheel
  "${launchable_venv_dir}"/bin/pip --require-virtualenv --no-cache-dir install launchable=="${LAUNCHABLE_VERSION}"
  # Symlink to a folder in the PATH
  ln -s "${launchable_venv_dir}/bin/launchable" /usr/local/bin/launchable
}

## ensure yamllint is installed
function install_yamllint() {
  apt-get update --quiet
  apt-get install --yes --no-install-recommends \
    yamllint
}

## Ensure that the VM is cleaned up of provision artifacts
function cleanup() {
  export HISTSIZE=0
  rm -rf /tmp/* /var/log/* "${HOME}/.npm"
  sync
}

## Install rngd to increase VM entropy
function install_rngd() {
  apt-get update --quiet
  apt-get install --yes --no-install-recommends rng-tools5
  systemctl enable rng-tools5 || true # Uses logical operator '|| true' to prevent script from failing due to non-zero exit status in the case of docker containers
  systemctl start rngd || true
}

## Install Typos
function install_typos() {
  apt-get update --quiet
  apt-get install --yes --no-install-recommends curl # Should already be there but this function should be autonomous

  curl --silent --show-error --location --output /tmp/typos.tar.gz "https://github.com/crate-ci/typos/releases/download/v${TYPOS_VERSION}/typos-v${TYPOS_VERSION}-$(uname -m)-unknown-linux-musl.tar.gz"
  tar xvfz /tmp/typos.tar.gz -C /usr/local/bin ./typos
  chmod a+x /usr/local/bin/typos
  rm -rf /tmp/typos.tar.gz
}

function main() {
  check_commands
  copy_custom_scripts
  set_locale # Define the locale
  clean_apt
  install_common_requirements
  setuser # Define user Jenkins before all (to allow installing stuff in its home dir)
  install_git_gitlfs
  install_ssh_requirements # Ensure that OpenSSH CLI and SSH agent are installed
  install_asdf # Before all the others but after the jenkins home is created
  install_goss # needed by the pipeline
  install_docker # needed by the pipeline
  install_jdks # needed by the pipeline
  install_chromium
  install_datadog
  install_JA_requirements
  install_qemu
  install_azcopy
  install_doctl
  install_python
  install_docker_compose
  install_maven
  install_hadolint
  install_cst
  install_jxreleaseversion
  install_azurecli
  install_gh
  install_golang
  install_golangcilint # must come after golang
  install_ruby "${RUBY_PUPPET_VERSION}"
  install_ruby "${RUBY_VERSION}"
  install_vagrant
  install_xq
  install_yq
  install_packer
  install_updatecli
  install_awscli
  install_netlifydeploy
  install_terraform
  install_kubectl
  install_trivy
  install_nodejs
  install_playwright
  install_launchable
  install_helm
  install_helmfile
  install_sops
  install_yamllint
  install_rngd
  install_typos

  echo "== Installed packages:"
  dpkg -l
}

main
cleanup
