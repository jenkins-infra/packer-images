#!/bin/bash
# This script returns if a pull request (retrieved from CHANGE_ID env var)
# has labels implying ubuntu, windows, or a specific windows version only
# If there are both or none, it returns "mixed-or-none"

set -eu -o pipefail

: "${CHANGE_ID:?Required}"
: "${GITHUB_TOKEN:?Required}"
: "${GITHUB_REPOSITORY:=jenkins-infra/packer-images}"

labels=$(curl -sSf \
	-H "Authorization: Bearer ${GITHUB_TOKEN}" \
	-H "Accept: application/vnd.github+json" \
	"https://api.github.com/repos/${GITHUB_REPOSITORY}/issues/${CHANGE_ID}/labels" |
	jq -r '.[].name')

set -x

has_ubuntu=false
has_windows=false
has_windows_2019=false
has_windows_2022=false
has_windows_2025=false

for label in ${labels}; do
	case "$label" in
	ubuntu)
		has_ubuntu=true
		;;
	windows-2019)
		has_windows=true
		has_windows_2019=true
		;;
	windows-2022)
		has_windows=true
		has_windows_2022=true
		;;
	windows-2025)
		has_windows=true
		has_windows_2025=true
		;;
	*)
		has_ubuntu=false
		has_windows=false
		;;
	esac
done

result="mixed-or-none"
if [[ "${has_ubuntu}" == true && "${has_windows}" == false ]]; then
	result="ubuntu-only"
fi
if [[ "${has_ubuntu}" == false && "${has_windows}" == true ]]; then
	result="windows-only"
	if [[ "${has_windows_2019}" == true && "${has_windows_2022}" == false && "${has_windows_2025}" == false ]]; then
		result="windows-2019-only"
	fi
	if [[ "${has_windows_2019}" == false && "${has_windows_2022}" == true && "${has_windows_2025}" == false ]]; then
		result="windows-2022-only"
	fi
	if [[ "${has_windows_2019}" == false && "${has_windows_2022}" == false && "${has_windows_2025}" == true ]]; then
		result="windows-2025-only"
	fi
fi
echo "${result}"