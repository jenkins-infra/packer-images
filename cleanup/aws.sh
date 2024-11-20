#!/bin/bash

set -Eeux -o pipefail

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

# Capture the list of security group IDs into a variable
security_groups=$(aws ec2 describe-security-groups --filters 'Name=group-name,Values=*packer*' \
    | jq -r '.SecurityGroups[].GroupId') || {
      echo "[ERROR] Failed to describe security groups.";
      exit 1; # Ensure the script exits if the command fails
  }

# Iterate over the captured list of security group IDs
for secgroup_id in ${security_groups}; do
  # Get the number of associated network interfaces for the current security group
  network_interfaces=$(aws ec2 describe-network-interfaces --filters "Name=group-id,Values=${secgroup_id}" \
      | jq -r '.NetworkInterfaces | length') || {
        echo "[ERROR] Failed to describe network interfaces for security group: ${secgroup_id}";
        exit 1; # Exit on failure
    }

  # Check if the security group is orphaned
  if [ "${network_interfaces}" -eq 0 ]; then
    echo "== Deleting orphaned security group: ${secgroup_id}"
    # Attempt to delete the security group
    run_aws_ec2_deletion_command delete-security-group --group-id "${secgroup_id}" || {
        echo "[ERROR] Failed to delete security group: ${secgroup_id}";
        exit 1; # Exit on failure
    }
  else
    echo "== Security group ${secgroup_id} is still in use. Skipping."
  fi
done

echo "== AWS Packer Cleanup finished."
