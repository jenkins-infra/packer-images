#!/bin/bash

# Check input parameteres
if ! [[ "${1:-1}" =~ ^[0-9]+$ ]]; then
  echo "ERROR: argument $1 is not a number" >&2
  exit 1
fi
timeshift_day="${1}"
build_type="${2:-dev}"

set -eu -o pipefail

run_aws_ec2_command() {
  # Check the DRYRUN environment variable
  if [ "${DRYRUN:-true}" = "false" ] || [ "${DRYRUN:-true}" = "no" ]
  then
    echo "== INFO: Running command AMI aws ec2 ${*}"
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

creation_date_threshold=""
if date -v-"${timeshift_day}d" > /dev/null 2>&1; then
    # BSD systems (Mac OS X)
    creation_date_threshold="$(date -v-"${timeshift_day}"d +%Y-%m-%d)"
else
    # GNU systems (Linux)
    creation_date_threshold="$(date --date="-${timeshift_day} days" +%Y-%m-%d)"
fi

## Check for aws API reachibility (is it configured?)
aws sts get-caller-identity >/dev/null || \
  { echo "[ERROR] Unable to request the AWS API: the command 'sts get-caller-identity' failed. Please check your AWS credentials"; exit 1; }

## STEP 1
## Remove images older than $1 day(s) of build_type $2
found_ami_ids="$(aws ec2 describe-images --owners self --filters "Name=tag:build_type,Values=${build_type}" \
  --query 'Images[?CreationDate<=`'"${creation_date_threshold}"'`][].ImageId' | jq -r '.[]' | sort -u)"

echo "== Checking the following AMIs (before creation_date_threshold=${creation_date_threshold}, with tag build_type=${build_type}) for deletion:"
echo "${found_ami_ids}"
echo "======"

# Exclude AMI defined in production for Puppet VMs (non puppet managed controllers should have the same, if not then it's sad)
production_amis="$(curl --silent --show-error --location https://raw.githubusercontent.com/jenkins-infra/jenkins-infra/production/hieradata/common.yaml | grep ami- | cut -d'"' -f2)"
ami_ids=()
for ami_id in ${found_ami_ids}
do
  # Add this AMI to the list if not present in the "production_amis"
  if echo "${production_amis}" | grep -v "${ami_id}"
  then
    ami_ids+=("${ami_id}")
  fi
done

if [ -n "${ami_ids[*]}" ]
then
  echo "== Deleting the following AMIs:"
  echo "${ami_ids[*]}"
  echo "======"
  export -f run_aws_ec2_command
  parallel --halt-on-error never --no-run-if-empty run_aws_ec2_command deregister-image --image-id {} ::: "${ami_ids[@]}"
else
  echo "== No dangling images found to delete."
fi

echo "== AWS Packer Cleanup IMAGES finished."
