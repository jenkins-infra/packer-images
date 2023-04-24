#!/bin/bash

set -eu -o pipefail

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

## When is yesterday exactly in YYYYMMDDHMMSS
yesterday=""
timeshift_days="1"
if date -v-${timeshift_days}d > /dev/null 2>&1; then
    # BSD systems (Mac OS X)
    yesterday="$(date -v-${timeshift_days}d +%Y%m%d%H%M%S)"
else
    # GNU systems (Linux)
    yesterday="$(date --date="-${timeshift_days} days" +%Y%m%d%H%M%S)"
fi

## Check for Azure API reachability (is it configured?)
az account show >/dev/null || \
  { echo "[ERROR] Unable to request the Azure API: the command 'az account show' failed. Please check your Azure credentials"; exit 1; }

## Remove running instances older than 24 hours
INSTANCE_IDS="$(az group list --query '[?tags.timestamp.to_number(@)<=`'"${yesterday}"'`] | [?starts_with(name, '\''pkr-Resource-'\'')].name'| jq -r '.[]' | xargs)"

if [ -n "${INSTANCE_IDS}" ]
then
  #shellcheck disable=SC2086
  #has to run on each resource group
  cpt="0"
  for rg in ${INSTANCE_IDS}
  do
    run_az_command group delete --name "$rg" --yes --no-wait
    ((cpt=cpt+1))
  done

  if [ "${DRYRUN:-true}" = "false" ] || [ "${DRYRUN:-true}" = "no" ]
  then
    echo "== $cpt resources group have been deleted"
  else
    echo "==DRYRUN $cpt resources group would have been deleted"
  fi
else
  echo "== No dangling instance found to terminate."
fi

## Delete dev and staging shared gallery images versions
for environment in dev staging
do
  GALLERY_NAME="${environment}_packer_images"
  RESOURCE_GROUP=$(echo "${GALLERY_NAME}" | tr '_' '-' | tr '[:lower:]' '[:upper:]')

  IMAGE_DEFINITION_NAMES="$(az sig image-definition list --gallery-name "${GALLERY_NAME}" --resource-group "${RESOURCE_GROUP}" | jq -r '.[].name' | xargs)"

  if [ -n "${IMAGE_DEFINITION_NAMES}" ]
  then
    for imageDefinitionName in ${IMAGE_DEFINITION_NAMES}
    do
      IMAGE_VERSIONS="$(az sig image-version list --gallery-image-definition "${imageDefinitionName}" --gallery-name "${GALLERY_NAME}" --resource-group "${RESOURCE_GROUP}" | jq -r '.[].name' | xargs)"
      if [ -n "${IMAGE_VERSIONS}" ]
      then
        versions_to_delete=()
        for imageVersion in ${IMAGE_VERSIONS}
        do
          versions_to_delete+=("${imageVersion}")
        done
        if [ -n "${versions_to_delete[*]}" ]
        then
          echo "== Preapring to delete the following versions of ${imageDefinitionName} in ${GALLERY_NAME}:"
          echo "${versions_to_delete[*]}"
          echo "======"
          export -f run_az_command
          parallel --halt-on-error never --no-run-if-empty \
            run_az_command sig image-version delete \
              --gallery-image-version {} \
              --gallery-image-definition "${imageDefinitionName}" \
              --gallery-name "${GALLERY_NAME}" \
              --resource-group "${RESOURCE_GROUP}" \
            ::: "${versions_to_delete[@]}"
        else
          echo "== No dangling images found to delete."
        fi
      else
        echo "No dangling image versions found in ${GALLERY_NAME}/${imageDefinitionName}"
      fi
    done
  else
    echo "== No image definition found in ${GALLERY_NAME}."
  fi
done

echo "== Azure Packer Cleanup finished."
