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
## Remove snapshots older than 1 month from dev
snapshot_ids="$(aws ec2 describe-snapshots \
  --owner-ids self \
  --query "Snapshots[?StartTime<='${lastmonthdate}'].[SnapshotId]" \
  --no-paginate \
  --region=us-east-2 \
  | jq -r '.[][]' | xargs)"

if [ -n "${snapshot_ids}" ]
then
  #shellcheck disable=SC2086
  #has to run on each instance
  cpt="0"
  for thesnapshot_id in ${snapshot_ids}
  do
    run_aws_ec2_command delete-snapshot --snapshot-id "${thesnapshot_id}"
    ((cpt=cpt+1))
  done

  if [ "${DRYRUN:-true}" = "false" ] || [ "${DRYRUN:-true}" = "no" ]
  then
    echo "== $cpt snapshots have been deleted"
  else
    echo "==DRYRUN $cpt snapshots would have been deleted"
  fi
else
  echo "== No dangling snapshots found to delete."
fi

echo "== AWS Packer Cleanup SNAPSHOTS finished."
