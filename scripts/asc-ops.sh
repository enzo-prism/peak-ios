#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
MIN_ASC_VERSION="${MIN_ASC_VERSION:-0.29.2}"

usage() {
  cat <<USAGE
Usage:
  ./scripts/asc-ops.sh doctor
  ./scripts/asc-ops.sh status [PLATFORM]
  ./scripts/asc-ops.sh latest-version [PLATFORM]
  ./scripts/asc-ops.sh relationships [TYPE] [PLATFORM]
  ./scripts/asc-ops.sh next-build VERSION [PLATFORM]
  ./scripts/asc-ops.sh validate-latest [PLATFORM]
  ./scripts/asc-ops.sh workflow-list
  ./scripts/asc-ops.sh workflow-validate
  ./scripts/asc-ops.sh workflow-run NAME [KEY:VALUE ...]

Defaults:
  PLATFORM defaults to ASC_PLATFORM, then .asc/project.json default_platform, then IOS.
  APP ID defaults to ASC_APP_ID, then .asc/project.json app_id, then .asc/config.json app_id.
USAGE
}

require_cmd() {
  local cmd="$1"
  if ! command -v "$cmd" >/dev/null 2>&1; then
    echo "error: required command '$cmd' is not installed or not on PATH." >&2
    exit 127
  fi
}

read_json_key() {
  local file_path="$1"
  local key="$2"
  if [[ ! -f "$file_path" ]]; then
    return
  fi
  jq -r --arg key "$key" '.[$key] // empty' "$file_path" 2>/dev/null || true
}

version_gte() {
  local current="$1"
  local required="$2"
  python3 - "$current" "$required" <<'PY'
import re
import sys

def norm(v: str):
    m = re.search(r"(\d+)\.(\d+)\.(\d+)", v)
    if not m:
        return (0, 0, 0)
    return tuple(int(x) for x in m.groups())

current = norm(sys.argv[1])
required = norm(sys.argv[2])
print("1" if current >= required else "0")
PY
}

resolve_platform() {
  local cli_platform="${1:-}"
  if [[ -n "$cli_platform" ]]; then
    echo "$cli_platform"
    return
  fi

  local project_platform
  project_platform="$(read_json_key "${ROOT_DIR}/.asc/project.json" "default_platform")"
  if [[ -n "$project_platform" ]]; then
    echo "$project_platform"
    return
  fi

  echo "${ASC_PLATFORM:-IOS}"
}

resolve_app_id() {
  local app_id="${ASC_APP_ID:-}"
  if [[ -z "$app_id" ]]; then
    app_id="$(read_json_key "${ROOT_DIR}/.asc/project.json" "app_id")"
  fi
  if [[ -z "$app_id" ]]; then
    app_id="$(read_json_key "${ROOT_DIR}/.asc/config.json" "app_id")"
  fi

  if [[ -z "$app_id" ]]; then
    echo "error: missing app id. Set ASC_APP_ID or define .asc/project.json app_id." >&2
    exit 2
  fi

  echo "$app_id"
}

latest_version_id() {
  local app_id="$1"
  local platform="$2"

  asc versions list --app "$app_id" --platform "$platform" --limit 200 --output json \
    | jq -r '.data | sort_by(.attributes.createdDate // "") | reverse | .[0].id // empty'
}

doctor() {
  require_cmd asc
  require_cmd jq
  require_cmd python3

  local asc_version
  asc_version="$(asc --version 2>/dev/null || true)"
  if [[ -z "$asc_version" ]]; then
    echo "error: failed to read asc version." >&2
    exit 1
  fi

  if [[ "$(version_gte "$asc_version" "$MIN_ASC_VERSION")" != "1" ]]; then
    echo "error: asc version is too old: '$asc_version' (required >= $MIN_ASC_VERSION)." >&2
    exit 1
  fi

  echo "asc version: $asc_version"
  asc auth status --validate

  if [[ -f "${ROOT_DIR}/.asc/workflow.json" ]]; then
    asc workflow validate --file "${ROOT_DIR}/.asc/workflow.json"
  else
    echo "warning: .asc/workflow.json not found; skipping workflow validation."
  fi
}

status() {
  local platform
  platform="$(resolve_platform "${1:-}")"
  local app_id
  app_id="$(resolve_app_id)"

  asc apps get --id "$app_id" --output table
  asc builds latest --app "$app_id" --platform "$platform" --output table
  asc versions list --app "$app_id" --platform "$platform" --limit 5 --output table
}

latest_version() {
  local platform
  platform="$(resolve_platform "${1:-}")"
  local app_id
  app_id="$(resolve_app_id)"

  local version_id
  version_id="$(latest_version_id "$app_id" "$platform")"
  if [[ -z "$version_id" ]]; then
    echo "error: no App Store versions found for app $app_id on platform $platform." >&2
    exit 3
  fi

  asc versions get --version-id "$version_id" --include-build --include-submission --output table
}

relationships() {
  local rel_type="${1:-appStoreVersionSubmission}"
  local platform
  platform="$(resolve_platform "${2:-}")"
  local app_id
  app_id="$(resolve_app_id)"

  local version_id
  version_id="$(latest_version_id "$app_id" "$platform")"
  if [[ -z "$version_id" ]]; then
    echo "error: no App Store versions found for app $app_id on platform $platform." >&2
    exit 3
  fi

  asc versions relationships --version-id "$version_id" --type "$rel_type" --output table
}

next_build() {
  local version="${1:-}"
  if [[ -z "$version" ]]; then
    echo "error: VERSION is required." >&2
    echo "example: ./scripts/asc-ops.sh next-build 1.7 IOS" >&2
    exit 2
  fi

  local platform
  platform="$(resolve_platform "${2:-}")"
  local app_id
  app_id="$(resolve_app_id)"

  asc builds latest --app "$app_id" --version "$version" --platform "$platform" --next --output table
}

validate_latest() {
  local platform
  platform="$(resolve_platform "${1:-}")"
  local app_id
  app_id="$(resolve_app_id)"

  local version_id
  version_id="$(latest_version_id "$app_id" "$platform")"
  if [[ -z "$version_id" ]]; then
    echo "error: no App Store versions found for app $app_id on platform $platform." >&2
    exit 3
  fi

  asc validate --app "$app_id" --version-id "$version_id" --platform "$platform" --output table
}

workflow_list() {
  asc workflow list --file "${ROOT_DIR}/.asc/workflow.json"
}

workflow_validate() {
  asc workflow validate --file "${ROOT_DIR}/.asc/workflow.json"
}

workflow_run() {
  local name="${1:-}"
  if [[ -z "$name" ]]; then
    echo "error: workflow NAME is required." >&2
    exit 2
  fi
  shift || true
  asc workflow run --file "${ROOT_DIR}/.asc/workflow.json" "$name" "$@"
}

cmd="${1:-doctor}"
shift || true

case "$cmd" in
  doctor)
    doctor
    ;;
  status)
    status "$@"
    ;;
  latest-version)
    latest_version "$@"
    ;;
  relationships)
    relationships "$@"
    ;;
  next-build)
    next_build "$@"
    ;;
  validate-latest)
    validate_latest "$@"
    ;;
  workflow-list)
    workflow_list
    ;;
  workflow-validate)
    workflow_validate
    ;;
  workflow-run)
    workflow_run "$@"
    ;;
  -h|--help|help)
    usage
    ;;
  *)
    echo "error: unknown command '$cmd'." >&2
    usage >&2
    exit 2
    ;;
esac
