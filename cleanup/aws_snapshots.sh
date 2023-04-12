#!/bin/bash

set -eu -o pipefail

run_aws_ec2_command() {
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

start_time_threshold=""
timeshift_days="1"
if date -v-${timeshift_days}d > /dev/null 2>&1; then
    # BSD systems (Mac OS X)
    start_time_threshold="$(date -v-${timeshift_days}d +%Y-%m-%d)"
else
    # GNU systems (Linux)
    start_time_threshold="$(date --date="-${timeshift_days} days" +%Y-%m-%d)"
fi

## Check for aws API reachibility (is it configured?)
aws sts get-caller-identity >/dev/null || \
  { echo "[ERROR] Unable to request the AWS API: the command 'sts get-caller-identity' failed. Please check your AWS credentials"; exit 1; }

## STEP 1
## Remove snapshots older than <timeshift_days> day(s)
snapshot_ids="$(aws ec2 describe-snapshots \
  --owner-ids self \
  --query "Snapshots[?StartTime<='${start_time_threshold}'].[SnapshotId]" \
  --no-paginate \
  --region=us-east-2 \
  | jq -r '.[][]')"

if [ -n "${snapshot_ids}" ]
then
  export -f run_aws_ec2_command
  echo "${snapshot_ids}" | parallel --halt-on-error never --no-run-if-empty run_aws_ec2_command delete-snapshot --snapshot-id {} :::
else
  echo "== No dangling snapshots found to delete."
fi

echo "== AWS Packer Cleanup SNAPSHOTS finished."
