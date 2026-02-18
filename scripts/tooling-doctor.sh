#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

step() {
  echo
  echo "==> $*"
}

require_cmd() {
  local cmd="$1"
  if ! command -v "${cmd}" >/dev/null 2>&1; then
    echo "error: required command '${cmd}' is not installed or not on PATH." >&2
    exit 127
  fi
}

require_cmd xcodebuild
require_cmd xcrun
require_cmd python3
require_cmd asc-codex

step "ASC auth doctor"
"${SCRIPT_DIR}/asc-sync.sh" doctor

step "ASC app status"
"${SCRIPT_DIR}/asc-sync.sh" status

step "Boot simulator"
"${SCRIPT_DIR}/boot-sim.sh"

step "Build simulator target"
"${SCRIPT_DIR}/build-sim.sh"

echo
echo "Tooling doctor complete: ASC auth + simulator build path look healthy."
