#!/bin/bash

set -eu -o pipefail

run_aws_ec2_deletion_command() {
  # Check the DRYRUN environment variable
  if [ "${DRYRUN:-true}" = "false" ] || [ "${DRYRUN:-true}" = "no" ]
  then
    # Execute command "as it"
    aws ec2 "$@"
  else
    # Execute command with the "--dry-run"
    ec2_subcommand="$1"
    shift
    echo "== DRY RUN:"
    echo "aws ec2 ${ec2_subcommand} --dry-run" "$@"
    aws ec2 "${ec2_subcommand}" --dry-run "$@" 2>&1 | grep -v 'Request would have succeeded' || true
  fi
}

## Check for presence of required CLIs
for cli in aws jq date xargs
do
  command -v "${cli}" >/dev/null || { echo "[ERROR] no '${cli}' command found."; exit 1; }
done

## When is last month exactly?
lastmonthdate=""
timeshift_month="1"
if date -v-${timeshift_month}m > /dev/null 2>&1; then
    # BSD systems (Mac OS X)
    lastmonthdate="$(date -v-${timeshift_month}m +%Y-%m-%d)"
else
    # GNU systems (Linux)
    lastmonthdate="$(date --date="-${timeshift_month} months" +%Y-%m-%d)"
fi

## Check for aws API reachibility (is it configured?)
aws sts get-caller-identity >/dev/null || \
  { echo "[ERROR] Unable to request the AWS API: the command 'sts get-caller-identity' failed. Please check your AWS credentials"; exit 1; }

## STEP 1
## Remove images older than <timeshift_month> month(s) from dev
INSTANCE_IDS="$(aws ec2 describe-images --owners self --filters 'Name=tag:build_type,Values=dev' \
  --query 'Images[?CreationDate<=`'"${lastmonthdate}"'`][].ImageId' | jq -r '.[]' | xargs)"

if [ -n "${INSTANCE_IDS}" ]
then
  #shellcheck disable=SC2086
  #has to run on each instance
  cpt="0"
  for theimageid in ${INSTANCE_IDS}
  do
    run_aws_ec2_deletion_command deregister-image --image-id ${theimageid}
    ((cpt=cpt+1))
  done

  if [ "${DRYRUN:-true}" = "false" ] || [ "${DRYRUN:-true}" = "no" ]
  then
    echo "== $cpt images have been deregistered"
  else
    echo "==DRYRUN $cpt images would have been deregistered"
  fi
else
  echo "== No dangling images found to delete."
fi

echo "== AWS Packer Cleanup IMAGES finished."
