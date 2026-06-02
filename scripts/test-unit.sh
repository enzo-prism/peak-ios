#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"

export SCHEME="${SCHEME:-PeakUnit}"
export RESULT_BUNDLE="${RESULT_BUNDLE:-${ROOT_DIR}/.build/UnitTests.xcresult}"

# shellcheck source=/dev/null
source "${SCRIPT_DIR}/_common.sh"

init_common

export DESTINATION_NAME
export DESTINATION_UDID
"${SCRIPT_DIR}/boot-sim.sh"

mkdir -p "$(dirname "${RESULT_BUNDLE}")"
if [[ -e "${RESULT_BUNDLE}" ]]; then
  rm -rf "${RESULT_BUNDLE}"
fi

set +e
xcodebuild test \
  "${XCODE_CONTAINER_ARGS[@]}" \
  -scheme "${SCHEME}" \
  -configuration "${CONFIGURATION}" \
  -destination "${DESTINATION}" \
  -derivedDataPath "${DERIVED_DATA}" \
  -resultBundlePath "${RESULT_BUNDLE}" \
  -only-testing:PeakTests \
  CODE_SIGNING_ALLOWED=NO \
  CODE_SIGNING_REQUIRED=NO
status=$?
set -e

if [[ ${status} -ne 0 ]]; then
  echo "Unit tests failed. Results bundle: ${RESULT_BUNDLE}"
  exit "${status}"
fi

echo "Unit tests passed for PeakTests (${CONFIGURATION}) on ${DESTINATION_NAME}."
