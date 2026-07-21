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

# Silence the first-run keyboard alerts before any test types a character.
# On a freshly created or erased simulator — which is exactly what CI gets —
# springboard raises "Enable Dictation?" over the app the first time a keyboard
# appears. It is a system alert, so it steals taps from whatever is underneath:
# a stepper tap lands on the alert instead of the app, and the test fails
# reporting a control that "did nothing". Pre-answering these makes a fresh
# simulator behave like a warm one.
suppress_keyboard_prompts() {
  xcrun simctl spawn "${DESTINATION_UDID}" defaults write com.apple.assistant.support "Dictation Enabled" -bool false
  xcrun simctl spawn "${DESTINATION_UDID}" defaults write com.apple.Preferences DidShowContinuousPathIntroduction -bool true
  xcrun simctl spawn "${DESTINATION_UDID}" defaults write com.apple.keyboard.preferences DidShowGestureKeyboardIntroduction -bool true
}
suppress_keyboard_prompts >/dev/null 2>&1 || true

open -a Simulator
