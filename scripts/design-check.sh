#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"

export DERIVED_DATA="${DERIVED_DATA:-${ROOT_DIR}/.derivedData}"
export CONFIGURATION="${CONFIGURATION:-Debug}"

# shellcheck source=/dev/null
source "${SCRIPT_DIR}/_common.sh"

detect_container
detect_scheme

DESIGN_DEVICE="${DESIGN_DEVICE:-all}"
case "${DESIGN_DEVICE}" in all|iphone|ipad) ;; *) echo "DESIGN_DEVICE must be all, iphone, or ipad" >&2; exit 2 ;; esac

SUMMARY_READY=0
IPHONE_NAME=""
IPHONE_UDID=""
IPAD_NAME=""
IPAD_UDID=""
IPHONE_DIR=""
IPAD_DIR=""

print_summary() {
  if [[ "${SUMMARY_READY}" -ne 1 ]]; then
    return
  fi
  echo "Design check summary (${DESIGN_DEVICE}):"
  if [[ "${DESIGN_DEVICE}" != "ipad" ]]; then
    echo "- iPhone: ${IPHONE_NAME} (${IPHONE_UDID})"
    echo "- Unit/UI results and screenshot: ${IPHONE_DIR}"
  fi
  if [[ "${DESIGN_DEVICE}" != "iphone" ]]; then
    echo "- iPad: ${IPAD_NAME} (${IPAD_UDID})"
    echo "- UI results and screenshot: ${IPAD_DIR}"
  fi
}

trap 'exit_code=$?; print_summary; if [[ $exit_code -ne 0 ]]; then echo "Design check failed (exit ${exit_code})."; fi' EXIT

pick_device() {
  local kind="$1"
  local override_name="${2:-}"
  local strict_override="${3:-0}"
  python3 - "${kind}" "${override_name}" "${strict_override}" <<'PY'
import json
import re
import subprocess
import sys

kind = sys.argv[1]
override = sys.argv[2].strip() if len(sys.argv) > 2 else ""
override = override or None
strict = (sys.argv[3].strip().lower() in {"1", "true", "yes", "on"}) if len(sys.argv) > 3 else False

data = json.loads(subprocess.check_output(["xcrun", "simctl", "list", "devices", "available", "-j"]))
devices = data.get("devices", {})

candidates = []
for runtime, device_list in devices.items():
    if "iOS" not in runtime:
        continue
    m = re.search(r"iOS-(\d+)(?:-(\d+))?", runtime)
    major = int(m.group(1)) if m else 0
    minor = int(m.group(2) or 0) if m else 0
    runtime_key = (major, minor)
    for device in device_list:
        name = device.get("name", "")
        if kind == "iphone" and not name.startswith("iPhone"):
            continue
        if kind == "ipad" and not name.startswith("iPad"):
            continue
        udid = device.get("udid")
        if not udid:
            continue
        candidates.append((name, udid, runtime_key))

if override:
    exact = [c for c in candidates if c[0] == override]
    if exact:
        candidates = exact
        status = "exact"
    else:
        if strict:
            sys.exit(f"No available {kind} simulator named '{override}'.")
        status = "fallback"
else:
    status = "auto"

if not candidates:
    sys.exit(f"No available {kind} simulators found.")

def iphone_score(name, runtime):
    m = re.search(r"iPhone (\d+)", name)
    number = int(m.group(1)) if m else 0
    variant = 0
    if "Pro Max" in name:
        variant = 3
    elif "Pro" in name:
        variant = 2
    elif "Plus" in name:
        variant = 1
    return (number, variant, runtime[0], runtime[1], name)

def ipad_score(name, runtime):
    family = 1
    if "iPad Pro" in name:
        family = 3
    elif "iPad Air" in name:
        family = 2
    elif "iPad mini" in name:
        family = 0
    size = 0.0
    m = re.search(r"(\d+(?:\.\d+)?)-inch", name)
    if m:
        size = float(m.group(1))
    generation = 0
    m = re.search(r"(\d+)(?:st|nd|rd|th) generation", name)
    if m:
        generation = int(m.group(1))
    return (family, size, generation, runtime[0], runtime[1], name)

if kind == "iphone":
    best = max(candidates, key=lambda c: iphone_score(c[0], c[2]))
else:
    best = max(candidates, key=lambda c: ipad_score(c[0], c[2]))

print(f"{best[0]}|{best[1]}|{status}")
PY
}

detect_ui_test_target() {
  local json_output=""
  json_output="$(xcodebuild -list -json "${XCODE_CONTAINER_ARGS[@]}")"
  python3 -c 'import json,sys; data=json.load(sys.stdin); container=data.get("workspace") or data.get("project") or {}; targets=container.get("targets") or []; ui=[t for t in targets if t.endswith("UITests")]; print("PeakUITests" if "PeakUITests" in ui else (ui[0] if ui else ""))' <<<"${json_output}" || true
}

capture_screenshot() {
  local udid="$1"
  local path="$2"
  local label="$3"
  local bundle_id="com.designprism.peak"

  if ! xcrun simctl launch "${udid}" "${bundle_id}" >/dev/null 2>&1; then
    echo "warning: unable to launch ${bundle_id} on ${label} (${udid}); taking screenshot anyway."
  fi
  xcrun simctl io "${udid}" screenshot "${path}"
}

run_ui_tests() {
  local label="$1"
  local udid="$2"
  local result_path="$3"

  echo "Running UI tests on ${label}: ${UI_TEST_TARGET}"
  rm -rf "${result_path}"
  xcodebuild test \
    "${XCODE_CONTAINER_ARGS[@]}" \
    -scheme "${SCHEME}" \
    -configuration "${CONFIGURATION}" \
    -destination "platform=iOS Simulator,id=${udid}" \
    -derivedDataPath "${DERIVED_DATA}" \
    -resultBundlePath "${result_path}" \
    -only-testing:"${UI_TEST_TARGET}" \
    CODE_SIGNING_ALLOWED=NO \
    CODE_SIGNING_REQUIRED=NO
}

IPHONE_PREF_NAME="${IPHONE_DESTINATION_NAME:-iPhone 16 Pro}"
IPAD_PREF_NAME="${IPAD_DESTINATION_NAME:-iPad Pro 11-inch (M4)}"
STRICT_DESIGN_DESTINATION="${STRICT_DESIGN_DESTINATION:-0}"

IPHONE_INFO="$(pick_device "iphone" "${IPHONE_PREF_NAME}" "${STRICT_DESIGN_DESTINATION}")"
IPAD_INFO="$(pick_device "ipad" "${IPAD_PREF_NAME}" "${STRICT_DESIGN_DESTINATION}")"

IPHONE_NAME="${IPHONE_INFO%%|*}"
IPHONE_REST="${IPHONE_INFO#*|}"
IPHONE_UDID="${IPHONE_REST%%|*}"
IPHONE_STATUS="${IPHONE_INFO##*|}"
IPAD_NAME="${IPAD_INFO%%|*}"
IPAD_REST="${IPAD_INFO#*|}"
IPAD_UDID="${IPAD_REST%%|*}"
IPAD_STATUS="${IPAD_INFO##*|}"

if [[ "${IPHONE_STATUS}" == "fallback" ]]; then
  echo "warning: preferred iPhone simulator '${IPHONE_PREF_NAME}' not available; using ${IPHONE_NAME} (${IPHONE_UDID}). Set STRICT_DESIGN_DESTINATION=1 to fail instead."
fi
if [[ "${IPAD_STATUS}" == "fallback" ]]; then
  echo "warning: preferred iPad simulator '${IPAD_PREF_NAME}' not available; using ${IPAD_NAME} (${IPAD_UDID}). Set STRICT_DESIGN_DESTINATION=1 to fail instead."
fi

ARTIFACTS_DIR="${ROOT_DIR}/artifacts/design-check"
IPHONE_DIR="${ARTIFACTS_DIR}/iphone"
IPAD_DIR="${ARTIFACTS_DIR}/ipad"
mkdir -p "${IPHONE_DIR}" "${IPAD_DIR}"
SUMMARY_READY=1

if [[ "${DESIGN_DEVICE}" != "ipad" ]]; then
  echo "Running unit tests on iPhone: ${IPHONE_NAME}"
  RESULT_BUNDLE="${IPHONE_DIR}/UnitTests.xcresult" \
  DESTINATION_NAME="${IPHONE_NAME}" \
  DERIVED_DATA="${DERIVED_DATA}" \
  CONFIGURATION="${CONFIGURATION}" \
  "${SCRIPT_DIR}/test-unit.sh"
fi

UI_TEST_TARGET="${UI_TEST_TARGET:-$(detect_ui_test_target)}"
if [[ -z "${UI_TEST_TARGET}" ]]; then
  UI_TEST_TARGET="PeakUITests"
  echo "warning: UI test target not found via xcodebuild -list; defaulting to ${UI_TEST_TARGET}."
fi

if [[ "${DESIGN_DEVICE}" != "ipad" ]]; then
  run_ui_tests "iPhone: ${IPHONE_NAME}" "${IPHONE_UDID}" "${IPHONE_DIR}/UITests.xcresult"
  if [[ "${SKIP_SCREENSHOTS:-}" != "1" ]]; then
    capture_screenshot "${IPHONE_UDID}" "${IPHONE_DIR}/screenshot.png" "iPhone"
  fi
fi

if [[ "${DESIGN_DEVICE}" != "iphone" ]]; then
  DESTINATION_NAME="${IPAD_NAME}" DESTINATION_UDID="${IPAD_UDID}" "${SCRIPT_DIR}/boot-sim.sh"
  run_ui_tests "iPad: ${IPAD_NAME}" "${IPAD_UDID}" "${IPAD_DIR}/UITests.xcresult"
  if [[ "${SKIP_SCREENSHOTS:-}" != "1" ]]; then
    capture_screenshot "${IPAD_UDID}" "${IPAD_DIR}/screenshot.png" "iPad"
  fi
fi
