#!/bin/bash

set -eux -o pipefail

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

if [ -n "${snapshot_ids}" ]; then
  echo "== Found the following snapshots for potential deletion:"
  echo "${snapshot_ids}"
  echo "======"

  for snapshot_id in ${snapshot_ids}; do
    echo "== Checking if snapshot ${snapshot_id} is in use..."
    # Check if the snapshot is in use by querying associated AMIs
    if aws ec2 describe-images --filters "Name=block-device-mapping.snapshot-id,Values=${snapshot_id}" --query 'Images[*].ImageId' --output text | grep -q .; then
      echo "[INFO] Snapshot ${snapshot_id} is in use by an AMI. Skipping."
    else
      # Only attempt to delete if the snapshot is not in use
      echo "== Snapshot ${snapshot_id} is not in use. Proceeding with deletion."
      if run_aws_ec2_command delete-snapshot --snapshot-id "${snapshot_id}"; then
        echo "== Snapshot ${snapshot_id} successfully deleted."
      else
        echo "[ERROR] Failed to delete snapshot ${snapshot_id}."
      fi
    fi
  done
else
  echo "== No dangling snapshots found to delete."
fi

echo "== AWS Packer Cleanup SNAPSHOTS finished."
