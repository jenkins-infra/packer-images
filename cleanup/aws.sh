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

## When is yesterday exactly?
yesterday=""
timeshift_days="1"
if date -v-${timeshift_days}m > /dev/null 2>&1; then
    # BSD systems (Mac OS X)
    yesterday="$(date -v-${timeshift_days}d +%Y-%m-%d)"
else
    # GNU systems (Linux)
    yesterday="$(date --date="-${timeshift_days} days" +%Y-%m-%d)"
fi

## Check for aws API reachibility (is it configured?)
aws sts get-caller-identity >/dev/null || \
  { echo "[ERROR] Unable to request the AWS API: the command 'sts get-caller-identity' failed. Please check your AWS credentials"; exit 1; }

## Remove running instances older than 24 hours

INSTANCE_IDS="$(aws ec2 describe-instances --filters 'Name=tag:Name,Values=*Packer*' \
  --query 'Reservations[].Instances[?LaunchTime<=`'"${yesterday}"'`][].InstanceId' | jq -r '.[]' | xargs)"

if [ -n "${INSTANCE_IDS}" ]
then
  #shellcheck disable=SC2086
  run_aws_ec2_deletion_command terminate-instances --instance-ids ${INSTANCE_IDS}
else
  echo "== No dangling instance found to terminate."
fi

## Remove security groups older than 24 hours
for secgroup_id in $(aws ec2 describe-security-groups --filters 'Name=group-name,Values=*packer*' \
  | jq -r '.SecurityGroups[].GroupId')
do
  # Each security group which name matches the pattern '*packer*' is deleted if it is orphaned (not use by any network interface)
  if [ "0" = "$(aws ec2 describe-network-interfaces --filters "Name=group-id,Values=${secgroup_id}" | jq -r '.NetworkInterfaces | length')" ]
  then
    #shellcheck disable=SC2086
    run_aws_ec2_deletion_command delete-security-group --group-id ${secgroup_id}
  fi
done

echo "== AWS Packer Cleanup finished."
