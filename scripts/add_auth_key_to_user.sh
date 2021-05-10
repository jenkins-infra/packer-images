#!/bin/bash
# This script ensures that the public keys passed as argument $1
# is set up as an SSH authorized key for the user passed as argument $2

set -eux -o pipefail

openssh_public_key="${1}"
target_user="${2}"

# Ensure the SSH directory exists
su - "${target_user}" -c 'mkdir -p ~/.ssh'

# Write down the key
echo "${openssh_public_key}" | su - "${target_user}" -c 'tee -a ~/.ssh/authorized_keys'
su - "${target_user}" -c 'chmod 0700 ~/.ssh'
su - "${target_user}" -c 'chmod 0600 ~/.ssh/*'
