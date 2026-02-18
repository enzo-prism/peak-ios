#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"

CONFIGURATION="${CONFIGURATION:-Debug}"
DERIVED_DATA="${DERIVED_DATA:-${ROOT_DIR}/.derivedData}"
RESULT_BUNDLE="${RESULT_BUNDLE:-${ROOT_DIR}/.build/TestResults.xcresult}"
DEFAULT_DESTINATION_NAME="${DEFAULT_DESTINATION_NAME:-iPhone 16 Pro}"
DEFAULT_DESTINATION_OS="${DEFAULT_DESTINATION_OS:-18.5}"

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
  local requested_name="${DESTINATION_NAME:-${DEFAULT_DESTINATION_NAME}}"
  local requested_os=""
  local strict_destination="${STRICT_DESTINATION:-0}"
  local output=""
  if [[ -n "${DESTINATION_OS:-}" ]]; then
    requested_os="${DESTINATION_OS}"
  elif [[ -z "${DESTINATION_NAME:-}" ]]; then
    requested_os="${DEFAULT_DESTINATION_OS}"
  fi

  if ! output="$(python3 - "${requested_name}" "${requested_os}" "${strict_destination}" <<'PY' 2>&1
import json
import re
import subprocess
import sys

requested_name = (sys.argv[1] or "").strip() or None
requested_os_raw = (sys.argv[2] or "").strip() or None
strict = (sys.argv[3] or "0").strip().lower() in {"1", "true", "yes", "on"}

def parse_os(raw: str):
    if raw.lower() in {"latest", "any"}:
        return None
    m = re.match(r"^(\d+)(?:\.(\d+))?$", raw)
    if not m:
        raise ValueError(f"Invalid DESTINATION_OS '{raw}'. Use formats like 18.5 or 26.2.")
    return (int(m.group(1)), int(m.group(2) or 0))

requested_os = None
if requested_os_raw:
    requested_os = parse_os(requested_os_raw)

data = json.loads(subprocess.check_output(["xcrun", "simctl", "list", "devices", "available", "-j"]))
devices = data.get("devices", {})

candidates = []
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
        candidates.append({"name": name, "udid": udid, "major": major, "minor": minor})

if not candidates:
    print("No available iPhone simulators found.", file=sys.stderr)
    sys.exit(2)

filtered = list(candidates)
constraints = []
if requested_name:
    filtered = [c for c in filtered if c["name"] == requested_name]
    constraints.append(f"name '{requested_name}'")
if requested_os:
    filtered = [c for c in filtered if (c["major"], c["minor"]) == requested_os]
    constraints.append(f"iOS {requested_os[0]}.{requested_os[1]}")

matched = bool(filtered)
if not filtered:
    if strict:
        detail = " and ".join(constraints) if constraints else "requested criteria"
        print(f"No available iPhone simulator matches {detail}.", file=sys.stderr)
        sys.exit(2)
    filtered = list(candidates)

def score(item):
    name = item["name"]
    m = re.search(r"iPhone (\d+)", name)
    number = int(m.group(1)) if m else 0
    variant = 0
    if "Pro Max" in name:
        variant = 3
    elif "Pro" in name:
        variant = 2
    elif "Plus" in name:
        variant = 1
    return (number, variant, item["major"], item["minor"], name)

best = max(filtered, key=score)
runtime = f"{best['major']}.{best['minor']}"
status = "exact" if matched else "fallback"
print(f"{best['name']}|{best['udid']}|{runtime}|{status}")
PY
)"; then
    die "${output}"
  fi

  if [[ -z "${output}" ]]; then
    die "Unable to select a simulator destination."
  fi

  DESTINATION_NAME="${output%%|*}"
  local rest="${output#*|}"
  DESTINATION_UDID="${rest%%|*}"
  rest="${rest#*|}"
  local destination_runtime="${rest%%|*}"
  local destination_status="${rest##*|}"
  DESTINATION="platform=iOS Simulator,id=${DESTINATION_UDID}"

  if [[ "${destination_status}" == "fallback" ]]; then
    echo "warning: preferred simulator '${requested_name}'${requested_os:+ on iOS ${requested_os}} not available; using ${DESTINATION_NAME} (iOS ${destination_runtime}). Set STRICT_DESTINATION=1 to fail instead."
  fi
}

init_common() {
  detect_container
  detect_scheme
  resolve_destination
}
