#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"

export RESULT_BUNDLE="${RESULT_BUNDLE:-${ROOT_DIR}/.build/TestResults.xcresult}"
exec "${SCRIPT_DIR}/test-unit.sh"
