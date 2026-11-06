#!/usr/bin/env bash
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/_common.sh"
if pgrep -x xcodebuild >/dev/null; then
  die "Another xcodebuild is active. Wait for it before building the Watch companion."
fi
detect_container
xcodebuild build "${XCODE_CONTAINER_ARGS[@]}" -scheme PeakWatch \
  -configuration "${CONFIGURATION}" -destination 'generic/platform=watchOS Simulator' \
  -derivedDataPath "${DERIVED_DATA:-${ROOT_DIR}/.derivedData-watch}" \
  CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO
