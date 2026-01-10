#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=/dev/null
source "${SCRIPT_DIR}/_common.sh"

init_common

export DESTINATION_NAME
"${SCRIPT_DIR}/boot-sim.sh"

xcodebuild build \
  "${XCODE_CONTAINER_ARGS[@]}" \
  -scheme "${SCHEME}" \
  -configuration "${CONFIGURATION}" \
  -destination "${DESTINATION}" \
  -derivedDataPath "${DERIVED_DATA}"

echo "Build succeeded for ${SCHEME} (${CONFIGURATION}) on ${DESTINATION_NAME}."
