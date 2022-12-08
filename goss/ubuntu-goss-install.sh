#!/bin/bash
# This script provision the Linux Ubuntu 20 images for Jenkins agents
# Architecture supported: amd64, arm64

set -eux -o pipefail

## Check for environment variables or fail miserably (due to set -u enabled)
echo "== Provisiong Goss for ubuntu 20"
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


## Ensure Goss is installed
function install_goss() {
    goss_version="${GOSS_VERSION:-v0.3.20}"
    goss_url="https://github.com/goss-org/goss/releases/download/v${goss_version}/goss-linux-amd64"
    curl -L "${goss_url}" -o /usr/local/bin/goss
    chmod +rx /usr/local/bin/goss
}

function sanity_check() {
    echo "== Sanity Check of installed tools, running as user ${username}"
    su - "${username}" -c "goss --version"
    echo "== End of sanity check"
}

function main() {
    install_goss
}

main
sanity_check
