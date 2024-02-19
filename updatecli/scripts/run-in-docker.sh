#!/bin/bash
set -eux -o pipefail

if ! command -v docker >/dev/null 2>&1
then
  echo "ERROR: command line 'docker' required but not found. Exiting."
  exit 1
fi

SCRIPT_PATH=$1
shift
ABS_SCRIPT_PATH="$(readlink -f "${SCRIPT_PATH}")"
SCRIPT_DIR=$(cd "$(dirname "${ABS_SCRIPT_PATH}")" && pwd -P)

docker run --rm --volume="${SCRIPT_DIR}:${SCRIPT_DIR}":ro --entrypoint=bash ubuntu:22.04 "${ABS_SCRIPT_PATH}" "$@"
