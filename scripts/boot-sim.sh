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

# A Mac with a hardware keyboard leaves Simulator's "Connect Hardware Keyboard"
# on. The software keyboard then never appears; XCTest still exposes an
# offscreen preview, and keyboard-avoidance tests fail without covering the
# real overlap. Disconnect it for this UDID before Simulator.app reads prefs.
prefer_software_keyboard() {
  python3 - "${DESTINATION_UDID}" <<'PY'
import plistlib
import subprocess
import sys

udid = sys.argv[1]
domain = "com.apple.iphonesimulator"
try:
    exported = subprocess.check_output(["defaults", "export", domain, "-"], stderr=subprocess.DEVNULL)
    data = plistlib.loads(exported)
except (subprocess.CalledProcessError, plistlib.InvalidFileException, ValueError):
    data = {}
if not isinstance(data, dict):
    data = {}
data["ConnectHardwareKeyboard"] = False
prefs = data.get("DevicePreferences")
if not isinstance(prefs, dict):
    prefs = {}
device = prefs.get(udid)
if not isinstance(device, dict):
    device = {}
device["ConnectHardwareKeyboard"] = False
prefs[udid] = device
data["DevicePreferences"] = prefs
subprocess.run(
    ["defaults", "import", domain, "-"],
    input=plistlib.dumps(data, fmt=plistlib.FMT_XML),
    check=True,
)
PY
}

# Simulator.app caches ConnectHardwareKeyboard at launch. Quit the GUI so the
# next open picks up the preference; CoreSimulator devices stay booted.
quit_simulator_app() {
  local pids
  pids="$(pgrep -x Simulator || true)"
  if [[ -z "${pids}" ]]; then
    return 0
  fi
  # Specific Simulator.app PIDs only — not a pattern kill of other processes.
  # shellcheck disable=SC2086
  kill ${pids} >/dev/null 2>&1 || true
  local _i
  for _i in 1 2 3 4 5 6 7 8 9 10; do
    pgrep -xq Simulator || return 0
    sleep 0.2
  done
}

quit_simulator_app
if ! prefer_software_keyboard; then
  echo "warning: could not disconnect the Simulator hardware keyboard; software-keyboard UI tests may fail." >&2
fi

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

# Xcode may live on an external volume and Simulator need not be registered
# with Launch Services. Launch the app belonging to the selected toolchain.
developer_dir="$(xcode-select -p)"
simulator_app="${DEVELOPER_DIR:-${developer_dir}}/Applications/Simulator.app"
if [[ -d "${simulator_app}" ]]; then
  open "${simulator_app}"
else
  # Headless toolchains can boot CoreSimulator without the optional GUI app.
  open -a Simulator >/dev/null 2>&1 || true
fi
