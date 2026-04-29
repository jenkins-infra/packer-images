#!/bin/bash

# Fail script on instruction failure
set -e
# Same (fail script on instruction failure) inside pipelines
set -o pipefail
# Helps debugging from updatecli
set -x
# Safety net for unset variables
set -u

nuget_dist_json="$(curl --silent --show-error --location --fail https://dist.nuget.org/index.json)"
nuget_dist_versions="$(echo "${nuget_dist_json}" | jq -r '.artifacts.[] | select(.name == "win-x86-commandline") | .versions[].version')"
found_version="$(echo "${nuget_dist_versions}" | sort -hr | head -n 1)"
test -n "${found_version}"
echo "${found_version}"
