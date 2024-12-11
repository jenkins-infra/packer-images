#!/bin/bash

# Check input parameteres
if ! [[ "${1:-1}" =~ ^[0-9]+$ ]]; then
  echo "ERROR: argument $1 is not a number" >&2
  exit 1
fi
timeshift_day="${1}"
build_type="${2:-dev}"

#set -eu -o pipefail
set -eu -o xtrace

run_az_command() {
  # Check the DRYRUN environment variable
  if [ "${DRYRUN:-true}" = "false" ] || [ "${DRYRUN:-true}" = "no" ]
  then
    # Execute command "as it"
    echo "command executed: "
    echo "az" "$@"
    az "$@"
  else
    # Show command with "as it should run"
    echo "== DRY RUN "
    echo "= Command that would be executed without dry-run:"
    echo "az" "$@"
  fi
}

## Check for presence of required CLIs
for cli in az jq date xargs
do
  command -v "${cli}" >/dev/null || { echo "[ERROR] no '${cli}' command found."; exit 1; }
done

## Determine the time threshold
creation_date_threshold=""
if date -v-"${timeshift_day}d" > /dev/null 2>&1; then
    # BSD systems (Mac OS X)
    creation_date_threshold="$(date -v-"${timeshift_day}"d +%Y-%m-%d)"
else
    # GNU systems (Linux)
    creation_date_threshold="$(date --date="-${timeshift_day} days" +%Y-%m-%d)"
fi

## Check for Azure API reachability (is it configured?)
az account show >/dev/null || \
  { echo "[ERROR] Unable to request the Azure API: the command 'az account show' failed. Please check your Azure credentials"; exit 1; }

resource_group_name="${build_type}-packer-builds"

## Remove resources in the "Resource Group" older than the threshold
found_resource_ids="$(az resource list --resource-group="${resource_group_name}" | jq -r ".[] | select(.timeCreated < (\"${creation_date_threshold}\")) | .id")"

if [ -n "${found_resource_ids}" ]
then
  resources_to_delete=()
  for resource_id in ${found_resource_ids}
  do
    resources_to_delete+=("${resource_id}")
  done

  echo "== Preparing to delete the following resources:"
  echo "${resources_to_delete[*]}"
  echo "======"
  export -f run_az_command
  parallel --halt-on-error never --no-run-if-empty \
    run_az_command resource delete \
      --ids {} \
      --resource-group "${resource_group_name}" \
    ::: "${resources_to_delete[@]}"
else
  echo "== No dangling resources found to terminate in ${resource_group_name}"
fi

echo "== Azure Packer Build Resources cleanup finished."
