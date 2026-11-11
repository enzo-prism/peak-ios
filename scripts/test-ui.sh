#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=/dev/null
source "${SCRIPT_DIR}/_common.sh"

init_common

UI_TEST_TARGET="${UI_TEST_TARGET:-PeakUITests}"

# Optional SDK/runtime integration lane. Keep the framework out of the normal
# test bundle: mismatched Apple runtimes can otherwise fail before XCTest loads.
# This override affects this test build only; shipping targets retain iOS 17.
EXTRA_BUILD_ARGS=(CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO)
if [[ "${PEAK_SYSTEM_INTENT_TESTS:-0}" == "1" ]]; then
  EXTRA_BUILD_ARGS+=('OTHER_SWIFT_FLAGS=$(inherited) -DPEAK_SYSTEM_INTENT_TESTS' 'IPHONEOS_DEPLOYMENT_TARGET=27.0')
fi

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
  -only-testing:"${UI_TEST_TARGET}" \
  "${EXTRA_BUILD_ARGS[@]}"
status=$?
set -e

if [[ ${status} -ne 0 ]]; then
  echo "UI tests failed. Results bundle: ${RESULT_BUNDLE}"
  exit "${status}"
fi

echo "UI tests passed for ${UI_TEST_TARGET} on ${DESTINATION_NAME}."
