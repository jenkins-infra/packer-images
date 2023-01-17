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
asdf_install_dir="${userhome}/.asdf"

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
  tar --extract --verbose --gunzip --file="${archive}" --directory="${asdf_install_dir}" --strip-components=1 #strip the 1st-level directory of the archive as it has a changing name (asdf-<version>)

  touch "${profile_script}"
  echo ". ${asdf_install_dir}/asdf.sh" >> "${profile_script}"
  chown -R "${username}:${groupname}" "${userhome}"
  rm -f "${archive}"
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

  # Ensure that version is fixed
  echo "
Package: docker-ce*
Pin: version 5:${DOCKER_VERSION}*
Pin-Priority: 1001
" | tee /etc/apt/preferences.d/docker-ce

  # Install pinned version
  apt-get install --yes --no-install-recommends docker-ce

  # Allow the default user to use Docker. https://docs.docker.com/engine/install/linux-postinstall/
  # Please note that it gives effectively full root permissions to this user so these compute instances must be ephemeral
  usermod -aG docker "${username}"
}

## Ensure that the Jenkins Agent commons requirements are installed
function install_JA_requirements(){
  apt-get update --quiet
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
  apt-get update --quiet
  apt-get install --yes software-properties-common

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

function install_jdk() {
  apt-get update --quiet
  ## Prevent Java null pointer exception due to missing fontconfig
  apt-get install --yes --no-install-recommends fontconfig

  ## OpenJDKs: Adoptium - https://adoptium.net/installation.html
  mkdir -p /opt/jdk-8 /opt/jdk-11 /opt/jdk-17 /opt/jdk-19

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
  tar --extract --verbose --gunzip --file=/tmp/jdk8.tgz --directory=/opt/jdk-8 --strip-components=1

  # JDK11
  jdk11_short_version="${JDK11_VERSION//+/_}"
  curl -sSL -o /tmp/jdk11.tgz \
    "https://github.com/adoptium/temurin11-binaries/releases/download/jdk-${JDK11_VERSION}/OpenJDK11U-jdk_${cpu_arch_short}_linux_hotspot_${jdk11_short_version}.tar.gz"
  tar --extract --verbose --gunzip --file=/tmp/jdk11.tgz --directory=/opt/jdk-11 --strip-components=1

  # JDK17
  jdk17_short_version="${JDK17_VERSION//+/_}"
  curl -sSL -o /tmp/jdk17.tgz \
    "https://github.com/adoptium/temurin17-binaries/releases/download/jdk-${JDK17_VERSION}/OpenJDK17U-jdk_${cpu_arch_short}_linux_hotspot_${jdk17_short_version}.tar.gz"
  tar --extract --verbose --gunzip --file=/tmp/jdk17.tgz --directory=/opt/jdk-17 --strip-components=1

  # JDK19
  jdk19_short_version="${JDK19_VERSION//+/_}"
  curl -sSL -o /tmp/jdk19.tgz \
    "https://github.com/adoptium/temurin19-binaries/releases/download/jdk-${JDK19_VERSION}/OpenJDK19U-jdk_${cpu_arch_short}_linux_hotspot_${jdk19_short_version}.tar.gz"
  tar --extract --verbose --gunzip --file=/tmp/jdk19.tgz --directory=/opt/jdk-19 --strip-components=1

  # Define JDK installations
  # The priority of a JDK is the last argument.
  # Starts by setting priority to the JDK major version: higher version is the expected default
  update-alternatives --install /usr/bin/java java /opt/jdk-8/bin/java 8
  update-alternatives --install /usr/bin/java java /opt/jdk-11/bin/java 11
  update-alternatives --install /usr/bin/java java /opt/jdk-17/bin/java 17
  update-alternatives --install /usr/bin/java java /opt/jdk-19/bin/java 19
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

  tar --extract --verbose --gunzip --file="/tmp/apache-maven-${MAVEN_VERSION}-bin.tar.gz" --directory=/usr/share/
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
  tar --extract --verbose --gunzip --file=/tmp/jx-release-version.tgz --directory=/tmp
  cp /tmp/jx-release-version /usr/local/bin/jx-release-version
  rm -rf /tmp/*
}

## Ensure that azure-cli is installed
function install_azurecli() {
  apt-get update --quiet
  ## From https://github.com/Azure/azure-cli/issues/7368#issuecomment-921578936
  apt-get install --yes --no-install-recommends \
    gcc \
    libffi-dev \
    libsodium-dev \
    python3-dev
  export SODIUM_INSTALL="system"
  # Python dependencies for the azure-cli
  python3 -m pip install --no-cache-dir --upgrade cryptography pynacl pyOpenSSL
  # Using the Python installation to ensure that both Intel and ARM are supported (Microsoft only provides a package for Intel)
  python3 -m pip install --no-cache-dir azure-cli=="${AZURECLI_VERSION}"
}

## Ensure that the GitHub command line (`gh`) is installed
function install_gh() {
  curl --silent --show-error --location --output /tmp/gh.tar.gz \
    "https://github.com/cli/cli/releases/download/v${GH_VERSION}/gh_${GH_VERSION}_linux_${ARCHITECTURE}.tar.gz"
  tar --extract --verbose --gunzip --file=/tmp/gh.tar.gz --directory=/tmp
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

## Install Ruby with asdf
function install_ruby() {
  # Ensure that ASDF is installed
  install_asdf
  # Ensure that require dependencies are present to install Ruby
  apt-get update --quiet
  apt-get install --yes --no-install-recommends autoconf bison build-essential libssl-dev libyaml-dev libreadline6-dev zlib1g-dev libncurses5-dev libffi-dev libgdbm6 libgdbm-dev libdb-dev
  # Install Ruby with ASDF and set it as default installation
  install_asdf_plugin ruby https://github.com/asdf-vm/asdf-ruby.git
  install_asdf_package ruby "${RUBY_VERSION}"
}

## Install Yq with asdf
function install_yq() {
  # Ensure that ASDF is installed
  install_asdf

  # Install Yq with ASDF and set it as default installation
  install_asdf_plugin yq https://github.com/sudermanjr/asdf-yq.git
  install_asdf_package yq "${YQ_VERSION}"
}

## Install Packer with ASDF (because it checks for integrity with the Hashicorp GPG key)
function install_packer() {
  # Ensure that ASDF is installed
  install_asdf

  # Install packer with ASDF and set it as default installation
  install_asdf_plugin packer https://github.com/asdf-community/asdf-hashicorp.git
  install_asdf_package packer "${PACKER_VERSION}"
}

## Install Datadog agent but not starting it and not enabling it (that will be the role of the system spinning up VM through cloud-init usually)
function install_datadog() {
  apt-get update --quiet
  apt-get install --yes --no-install-recommends apt-transport-https ca-certificates curl gnupg # Should already be there but this function should be autonomous

  echo 'deb [signed-by=/usr/share/keyrings/datadog-archive-keyring.gpg] https://apt.datadoghq.com/ stable 7' > /etc/apt/sources.list.d/datadog.list
  touch /usr/share/keyrings/datadog-archive-keyring.gpg
  chmod a+r /usr/share/keyrings/datadog-archive-keyring.gpg

  curl https://keys.datadoghq.com/DATADOG_APT_KEY_CURRENT.public | gpg --no-default-keyring --keyring /usr/share/keyrings/datadog-archive-keyring.gpg --import --batch
  curl https://keys.datadoghq.com/DATADOG_APT_KEY_382E94DE.public | gpg --no-default-keyring --keyring /usr/share/keyrings/datadog-archive-keyring.gpg --import --batch
  curl https://keys.datadoghq.com/DATADOG_APT_KEY_F14F620E.public | gpg --no-default-keyring --keyring /usr/share/keyrings/datadog-archive-keyring.gpg --import --batch

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
  tar --extract --verbose --gunzip --file="${archive_path}" --directory=/tmp
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

function install_tfsec() {
  apt-get update --quiet
  apt-get install --yes --no-install-recommends curl # Should already be there but this function should be autonomous

  curl --silent --location --show-error "https://github.com/aquasecurity/tfsec/releases/download/v${TFSEC_VERSION}/tfsec-linux-${ARCHITECTURE}" --output /usr/local/bin/tfsec
  chmod +rx /usr/local/bin/tfsec
}

function install_playwright_dependencies() {
  apt-get update --quiet
  # Playwright dependencies. https://ci.jenkins.io/job/Websites/job/jenkins-io-components/view/change-requests/job/PR-55/4/console
  apt-get install --yes --no-install-recommends \
    libglib2.0-0\
    libnss3\
    libnspr4\
    libatk1.0-0\
    libatk-bridge2.0-0\
    libcups2\
    libdrm2\
    libdbus-1-3\
    libxcb1\
    libxkbcommon0\
    libx11-6\
    libxcomposite1\
    libxdamage1\
    libxext6\
    libxfixes3\
    libxrandr2\
    libgbm1\
    libpango-1.0-0\
    libcairo2\
    libasound2\
    libatspi2.0-0\
    libwayland-client0
}



## Ensure that the VM is cleaned up
function cleanup() {
  export HISTSIZE=0
  rm -rf /tmp/* /var/log/*
  sync
}

function sanity_check() {
  echo "== Sanity Check of installed tools, running as user ${username}"
  su - "${username}" -c "source ${asdf_install_dir}/asdf.sh \
  && asdf version \
  && aws --version \
  && az --version \
  && bundle -v \
  && chromium-browser --version \
  && container-structure-test version \
  && datadog-agent version \
  && docker -v  \
  && docker-compose -v \
  && gh --version \
  && git --version \
  && git-lfs --version \
  && goss --version \
  && hadolint -v \
  && java -version \
  && jq --version \
  && jx-release-version -version \
  && kubectl version --client \
  && make --version \
  && mvn -v \
  && netlify-deploy --help \
  && command -v ssh-agent \
  && packer -v \
  && parallel --version \
  && python3 --version \
  && ruby -v \
  && terraform -v \
  && tfsec --version \
  && unzip -v \
  && updatecli version \
  && vagrant -v \
  && yq --version \
  && zip -v \
  "
  echo "== End of sanity check"
  echo "== Installed packages:"
  dpkg -l
}

function main() {
  check_commands
  copy_custom_scripts
  set_locale # Define the locale
  clean_apt
  install_ssh_requirements # Ensure that OpenSSH CLI and SSH agent are installed
  setuser # Define user Jenkins before all (to allow installing stuff in its home dir)
  install_asdf # Before all the others but after the jenkins home is created
  install_chromium
  install_docker
  install_datadog
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
  install_ruby
  install_yq
  install_packer
  install_updatecli
  install_awscli
  install_netlifydeploy
  install_terraform
  install_kubectl
  install_tfsec
  install_goss
  install_playwright_dependencies
  cleanup
}

main
sanity_check
