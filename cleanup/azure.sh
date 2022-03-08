#!/bin/bash

set -eu -o pipefail

run_az_deletion_command() {
  # Check the DRYRUN environment variable
  if [ "${DRYRUN:-true}" = "false" ] || [ "${DRYRUN:-true}" = "no" ]
  then
    # Execute command "as it"
    echo "command that would be executed : "
    echo "az group" "$@"
    az group "$@"
  else
    # Execute command with the "--dry-run"
    subcommand="$1"
    shift
    echo "== DRY RUN (show instead of ${subcommand}):"
    echo "az group show $@"
    az group show "$@" 2>&1 | grep -v 'Request would have succeeded' || true
  fi
}

## Check for presence of required CLIs
for cli in az jq date xargs
do
  command -v "${cli}" >/dev/null || { echo "[ERROR] no '${cli}' command found."; exit 1; }
done

## When is yesterday exactly in YYYYMMDDHMMSS
yesterday=""
timeshift_days="1"
if date -v-${timeshift_days}m > /dev/null 2>&1; then
    # BSD systems (Mac OS X)
    yesterday="$(date -v-${timeshift_days}d +%Y%m%d%H%M%S)"
else
    # GNU systems (Linux)
    yesterday="$(date --date="-${timeshift_days} days" +%Y%m%d%H%M%S)"
fi

## Check for aws API reachability (is it configured?)
az account show >/dev/null || \
  { echo "[ERROR] Unable to request the Azure API: the command 'az account show' failed. Please check your Azure credentials"; exit 1; }

## Remove running instances older than 24 hours
#az group list --query '[?tags.timestamp<'\''20220222222222'\''] | [?starts_with(name, '\''pkr-Resource-'\'')].name'
INSTANCE_IDS="$(az group list --query '[?tags.timestamp<='\''`'"${yesterday}"'`'\''] | [?starts_with(name, '\''pkr-Resource-'\'')].name'| jq -r '.[]' | xargs)" 

if [ -n "${INSTANCE_IDS}" ]
then
  #shellcheck disable=SC2086
  #has to run on each resource group
  cpt="0"
  for rg in ${INSTANCE_IDS}
  do
    run_az_deletion_command delete --name $rg
    ((cpt=cpt+1))
  done
  echo "== $cpt resources group have been deleted"
else
  echo "== No dangling instance found to terminate."
fi

echo "== Azure Packer Cleanup finished."
