#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"

CONFIGURATION="${CONFIGURATION:-Debug}"
DERIVED_DATA="${DERIVED_DATA:-${ROOT_DIR}/.derivedData}"
RESULT_BUNDLE="${RESULT_BUNDLE:-${ROOT_DIR}/.build/TestResults.xcresult}"

die() {
  echo "error: $*" >&2
  exit 1
}

detect_container() {
  local workspaces=()
  local projects=()

  shopt -s nullglob
  workspaces=("${ROOT_DIR}"/*.xcworkspace)
  projects=("${ROOT_DIR}"/*.xcodeproj)
  shopt -u nullglob

  if [[ ${#workspaces[@]} -gt 0 ]]; then
    XCODE_CONTAINER="${workspaces[0]}"
    XCODE_CONTAINER_FLAG="-workspace"
  elif [[ ${#projects[@]} -gt 0 ]]; then
    XCODE_CONTAINER="${projects[0]}"
    XCODE_CONTAINER_FLAG="-project"
  else
    die "No .xcworkspace or .xcodeproj found in repo root."
  fi

  XCODE_CONTAINER_ARGS=("${XCODE_CONTAINER_FLAG}" "${XCODE_CONTAINER}")
}

detect_scheme() {
  if [[ -n "${SCHEME:-}" ]]; then
    return
  fi

  local scheme=""
  local json_output=""

  json_output="$(xcodebuild -list -json "${XCODE_CONTAINER_ARGS[@]}" 2>/dev/null || true)"
  if [[ -n "${json_output}" ]]; then
    scheme="$(python3 -c 'import json,sys; data=json.load(sys.stdin); container=data.get("workspace") or data.get("project") or {}; schemes=container.get("schemes") or []; print("Peak" if "Peak" in schemes else (schemes[0] if schemes else ""))' <<<"${json_output}" || true)"
  fi

  if [[ -z "${scheme}" ]]; then
    local list_output=""
    local schemes=""
    list_output="$(xcodebuild -list "${XCODE_CONTAINER_ARGS[@]}")"
    schemes="$(printf '%s\n' "${list_output}" | awk '
      /^Schemes:/ {in_schemes=1; next}
      in_schemes && NF {
        sub(/^[[:space:]]+/, "", $0)
        print
      }
    ')"
    if printf '%s\n' "${schemes}" | grep -qx "Peak"; then
      scheme="Peak"
    else
      scheme="$(printf '%s\n' "${schemes}" | head -n 1)"
    fi
  fi

  if [[ -z "${scheme}" ]]; then
    die "Unable to determine scheme name. Set SCHEME env var."
  fi

  SCHEME="${scheme}"
}

resolve_destination() {
  local requested_name="${DESTINATION_NAME:-}"
  local output=""
  if [[ -n "${requested_name}" ]]; then
    output="$(python3 - "${requested_name}" <<'PY'
import json
import re
import subprocess
import sys

requested = sys.argv[1]
data = json.loads(subprocess.check_output(["xcrun", "simctl", "list", "devices", "available", "-j"]))
devices = data.get("devices", {})
by_name = {}
for runtime, device_list in devices.items():
    if "iOS" not in runtime:
        continue
    m = re.search(r"iOS-(\d+)(?:-(\d+))?", runtime)
    major = int(m.group(1)) if m else 0
    minor = int(m.group(2) or 0) if m else 0
    for device in device_list:
        name = device.get("name", "")
        if not name.startswith("iPhone"):
            continue
        udid = device.get("udid")
        if not udid:
            continue
        by_name.setdefault(name, []).append(((major, minor), udid))

if requested not in by_name:
    sys.exit(f"Simulator '{requested}' not found.")

by_name[requested].sort(key=lambda item: item[0], reverse=True)
runtime, udid = by_name[requested][0]
print(f"{requested}|{udid}")
PY
)"
  else
    output="$(python3 - <<'PY'
import json
import re
import subprocess
import sys

data = json.loads(subprocess.check_output(["xcrun", "simctl", "list", "devices", "available", "-j"]))
devices = data.get("devices", {})
by_name = {}
for runtime, device_list in devices.items():
    if "iOS" not in runtime:
        continue
    m = re.search(r"iOS-(\d+)(?:-(\d+))?", runtime)
    major = int(m.group(1)) if m else 0
    minor = int(m.group(2) or 0) if m else 0
    for device in device_list:
        name = device.get("name", "")
        if not name.startswith("iPhone"):
            continue
        udid = device.get("udid")
        if not udid:
            continue
        by_name.setdefault(name, []).append(((major, minor), udid))

if not by_name:
    sys.exit("No available iPhone simulators found.")

def score(name):
    m = re.search(r"(\\d+)", name)
    number = int(m.group(1)) if m else 0
    variant = 0
    if "Pro Max" in name:
        variant = 3
    elif "Pro" in name:
        variant = 2
    elif "Plus" in name:
        variant = 1
    return (number, variant, name)

best_name = sorted(by_name.keys(), key=score, reverse=True)[0]
by_name[best_name].sort(key=lambda item: item[0], reverse=True)
runtime, udid = by_name[best_name][0]
print(f"{best_name}|{udid}")
PY
)"
  fi

  if [[ -z "${output}" ]]; then
    die "Unable to select a simulator destination."
  fi

  DESTINATION_NAME="${output%%|*}"
  DESTINATION_UDID="${output##*|}"
  DESTINATION="platform=iOS Simulator,id=${DESTINATION_UDID}"
}

init_common() {
  detect_container
  detect_scheme
  resolve_destination
}
