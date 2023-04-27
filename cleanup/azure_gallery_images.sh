#!/bin/bash

# Check input parameteres
if ! [[ "${1:-1}" =~ ^[0-9]+$ ]]; then
  echo "ERROR: argument $1 is not a number" >&2
  exit 1
fi
timeshift_day="${1}"
build_type="${2:-dev}"

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

gallery_name="${build_type}_packer_images"
resource_group=$(echo "${gallery_name}" | tr '_' '-' | tr '[:lower:]' '[:upper:]')

image_definition_names="$(az sig image-definition list --gallery-name "${gallery_name}" --resource-group "${resource_group}" | jq -r '.[].name' | xargs)"

if [ -n "${image_definition_names}" ]
then
  for imageDefinitionName in ${image_definition_names}
  do
    image_versions="$(az sig image-version list --gallery-image-definition "${imageDefinitionName}" --gallery-name "${gallery_name}" --resource-group "${resource_group}" \
      | jq -r ".[] | select(.publishingProfile.publishedDate < (\"${creation_date_threshold}\")) | .name" \
      | xargs)"
    if [ -n "${image_versions}" ]
    then
      versions_to_delete=()
      for imageVersion in ${image_versions}
      do
        versions_to_delete+=("${imageVersion}")
      done
      if [ -n "${versions_to_delete[*]}" ]
      then
        echo "== Preparing to delete the following versions of ${imageDefinitionName} in ${gallery_name}:"
        echo "${versions_to_delete[*]}"
        echo "======"
        export -f run_az_command
        parallel --halt-on-error never --no-run-if-empty \
          run_az_command sig image-version delete \
            --gallery-image-version {} \
            --gallery-image-definition "${imageDefinitionName}" \
            --gallery-name "${gallery_name}" \
            --resource-group "${resource_group}" \
          ::: "${versions_to_delete[@]}"
      else
        echo "== No dangling images found to delete."
      fi
    else
      echo "No dangling image versions found in ${gallery_name}/${imageDefinitionName}"
    fi
  done
else
  echo "== No image definition found in ${gallery_name}."
fi

echo "== Azure Gallery Images Cleanup finished."
