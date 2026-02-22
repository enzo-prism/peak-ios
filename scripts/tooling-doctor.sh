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

assert_asc_cli() {
  if command -v asc >/dev/null 2>&1; then
    return
  fi

  if command -v asc-codex >/dev/null 2>&1; then
    return
  fi

  echo "error: required ASC CLI not found. Install either 'asc' or 'asc-codex'." >&2
  exit 127
}

require_cmd xcodebuild
require_cmd xcrun
require_cmd python3
assert_asc_cli

step "ASC auth doctor"
"${SCRIPT_DIR}/asc-sync.sh" doctor

step "ASC app status"
"${SCRIPT_DIR}/asc-sync.sh" status

step "Boot simulator"
"${SCRIPT_DIR}/boot-sim.sh"

step "Build simulator target"
"${SCRIPT_DIR}/build-sim.sh"

if command -v gh >/dev/null 2>&1; then
  step "GitHub CLI auth"
  if ! gh auth status >/dev/null 2>&1; then
    echo "warning: GitHub CLI is installed but not authenticated. Run 'gh auth login' to enable PR/run workflows flows."
  fi
fi

echo
echo "Tooling doctor complete: ASC auth + simulator build path look healthy."
