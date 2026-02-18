#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=/dev/null
source "${SCRIPT_DIR}/_common.sh"

# Reuse an already resolved simulator when called from other scripts.
if [[ -z "${DESTINATION_UDID:-}" || -z "${DESTINATION_NAME:-}" ]]; then
  init_common
fi

echo "Using simulator: ${DESTINATION_NAME} (${DESTINATION_UDID})"
xcrun simctl boot "${DESTINATION_UDID}" >/dev/null 2>&1 || true
xcrun simctl bootstatus "${DESTINATION_UDID}" -b
open -a Simulator
