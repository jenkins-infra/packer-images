#!/bin/bash
# This script uses apt to find the latest version of docker-ce available.
set -eux -o pipefail

for cli in apt-get apt-cache grep cut xargs
do
  if ! command -v $cli >/dev/null 2>&1
  then
    echo "ERROR: command line ${cli} required but not found. Exiting."
    exit 1
  fi
done

{
  apt-get update --quiet
  apt-get install --yes --no-install-recommends software-properties-common
  add-apt-repository --yes ppa:phd/chromium-browser
  apt-get update --quiet
} 1>&2 # Only write logs to stderr to avoid polluting updatecli's source (retrieved from the stdout)

# Retrieve from apt-cache the latest version of chromium-browser available
apt-cache policy chromium-browser | grep 'ubuntu0.18.04' | cut -d'-' -f1 \
  | xargs `# Trimming the result (removing spaces before and after)` \
  | { read -r x ; if [ "$x" == '(none)' ]; then exit 1; else echo "${x}"; fi }  # 5 Failing if the result is empty
