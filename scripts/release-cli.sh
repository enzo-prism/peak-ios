#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

usage() {
  cat <<USAGE
Usage:
  ./scripts/release-cli.sh [VERSION] [PLATFORM]
  ./scripts/release-cli.sh [options]

Optional:
  VERSION    target app version for next-build lookup (for example: 1.7)
  PLATFORM   ASC platform (default: IOS)

Options:
  --skip-local    skip ./scripts/tooling-doctor.sh
  --skip-gh       skip ./scripts/gh-tooling.sh status
  --snapshot      include './scripts/asc-sync.sh snapshot' at the end
  -h, --help     show this help
USAGE
}

check_command() {
  local cmd="$1"
  if ! command -v "$cmd" >/dev/null 2>&1; then
    echo "error: required command '${cmd}' is not installed or not on PATH." >&2
    exit 127
  fi
}

step() {
  echo
  echo "==> $*"
}

SKIP_LOCAL=0
SKIP_GH=0
RUN_SNAPSHOT=0
VERSION=""
PLATFORM="IOS"

while (($# > 0)); do
  case "$1" in
    --skip-local)
      SKIP_LOCAL=1
      shift
      ;;
    --skip-gh)
      SKIP_GH=1
      shift
      ;;
    --snapshot)
      RUN_SNAPSHOT=1
      shift
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      if [[ -z "${VERSION}" ]]; then
        VERSION="$1"
        shift
      elif [[ "${PLATFORM}" == "IOS" && "$1" != "" ]]; then
        PLATFORM="$1"
        shift
      else
        echo "error: unexpected argument '$1'." >&2
        usage >&2
        exit 2
      fi
      ;;
  esac
done

check_command bash

if [[ "$SKIP_LOCAL" -eq 0 ]]; then
  check_command xcodebuild
  check_command xcrun
  check_command python3
  check_command "$SCRIPT_DIR/asc-sync.sh"
  step "Running local tooling doctor"
  "${SCRIPT_DIR}/tooling-doctor.sh"
else
  echo "Skipping local tooling doctor (--skip-local)."
fi

if [[ "$SKIP_GH" -eq 0 ]]; then
  check_command gh
  step "Checking GitHub CLI state"
  "${SCRIPT_DIR}/gh-tooling.sh" status
else
  echo "Skipping GitHub CLI status (--skip-gh)."
fi

check_command "${SCRIPT_DIR}/asc-sync.sh"
step "ASC status snapshot"
"${SCRIPT_DIR}/asc-sync.sh" status
"${SCRIPT_DIR}/asc-sync.sh" latest-build

if [[ -n "$VERSION" ]]; then
  step "ASC next build lookup"
  "${SCRIPT_DIR}/asc-sync.sh" next-build "$VERSION" "$PLATFORM"
else
  echo "Tip: pass a VERSION to run next-build (for example: ./scripts/release-cli.sh 1.8 IOS)."
fi

if [[ "$RUN_SNAPSHOT" -eq 1 ]]; then
  step "ASC snapshot"
  "${SCRIPT_DIR}/asc-sync.sh" snapshot
fi

echo

echo "Release CLI check complete."
