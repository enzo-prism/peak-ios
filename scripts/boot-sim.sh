#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=/dev/null
source "${SCRIPT_DIR}/_common.sh"

init_common

echo "Using simulator: ${DESTINATION_NAME} (${DESTINATION_UDID})"
xcrun simctl boot "${DESTINATION_UDID}" >/dev/null 2>&1 || true
xcrun simctl bootstatus "${DESTINATION_UDID}" -b
open -a Simulator
