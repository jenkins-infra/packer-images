#!/bin/bash
# install-packer: install packer for the current architecture,
#  in the directory specified as 1st argument, in the version specified as 2nd argument

packer_install_dir="${1:?First argument missing: directory where to install packer.}"
packer_version="${2:?Second argument missing: version of packer to install.}"

set -eu -o pipefail

packer_cmd="packer"
temp_dir="$(mktemp -d)"
mkdir -p "${packer_install_dir}"

## check if packer exists or install it
echo "===================================="

## Check for presence of requirements or fail fast
for cli in curl unzip
do
  if ! command -v $cli >/dev/null 2>&1
  then
    echo "ERROR: command line ${cli} required but not found. Exiting."
    exit 1
  fi
done

echo "= Installing Packer version ${packer_version} to ${packer_install_dir}"

if ! command -v ${packer_cmd} >/dev/null 2>&1
then
  if test -x "${packer_install_dir}/${packer_cmd}"
  then
    packer_cmd="${packer_install_dir}/packer"
  else
    echo "Detecting CPU architecture..."
    arch=$(uname -m)
    if [[ $arch == x86_64* ]]; then
        echo "X64 Architecture"
        packer_download_url="https://releases.hashicorp.com/packer/${packer_version}/packer_${packer_version}_linux_amd64.zip"
    elif [[ $arch == i*86 ]]; then
        echo "X32 Architecture"
        packer_download_url="https://releases.hashicorp.com/packer/${packer_version}/packer_${packer_version}_linux_386.zip"
    elif [[ $arch == arm* ]]; then
        echo "ARM Architecture 32b"
        packer_download_url="https://releases.hashicorp.com/packer/${packer_version}/packer_${packer_version}_linux_arm.zip"
    elif [[ $arch == aarch64 ]]; then
        echo "ARM Architecture 64b"
        packer_download_url="https://releases.hashicorp.com/packer/${packer_version}/packer_${packer_version}_linux_arm64.zip"
    else
        echo "ERROR: unknwon architecture (${arch}). Exiting."
        exit 2
    fi

    zip_file="${temp_dir}/packer.zip"
    curl -sSL -o "${zip_file}" "${packer_download_url}"
    unzip "${zip_file}" -d "${packer_install_dir}"
    packer_cmd="${packer_install_dir}/packer"
  fi
fi

echo "= Packer installed, running sanity check (command '${packer_cmd} version')..."
"${packer_cmd}" version
echo "===================================="

exit 0
