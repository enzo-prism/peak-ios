#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"

if ! command -v asc-codex >/dev/null 2>&1; then
  echo "error: asc-codex not found. Install/setup ASC Codex tooling first." >&2
  exit 127
fi

read_json_key() {
  local file_path="$1"
  local key="$2"
  if [[ ! -f "${file_path}" ]]; then
    return
  fi
  python3 - "${file_path}" "${key}" <<'PY' || true
import json
import sys

path, key = sys.argv[1], sys.argv[2]
try:
    with open(path, "r", encoding="utf-8") as f:
        data = json.load(f)
except Exception:
    sys.exit(0)

value = data.get(key)
if isinstance(value, str) and value.strip():
    print(value.strip())
PY
}

app_id="${ASC_APP_ID:-}"
if [[ -z "${app_id}" && -f "${ROOT_DIR}/.asc/project.json" ]]; then
  app_id="$(read_json_key "${ROOT_DIR}/.asc/project.json" "app_id")"
fi
if [[ -z "${app_id}" && -f "${ROOT_DIR}/.asc/config.json" ]]; then
  app_id="$(read_json_key "${ROOT_DIR}/.asc/config.json" "app_id")"
fi
if [[ -z "${app_id}" ]]; then
  echo "error: missing app id. Set ASC_APP_ID or define .asc/project.json app_id." >&2
  exit 2
fi

usage() {
  cat <<USAGE
Usage:
  ./scripts/asc-sync.sh doctor
  ./scripts/asc-sync.sh status
  ./scripts/asc-sync.sh latest-build
  ./scripts/asc-sync.sh next-build [VERSION] [PLATFORM]
  ./scripts/asc-sync.sh versions
  ./scripts/asc-sync.sh snapshot

Notes:
  - App ID defaults to ASC_APP_ID, then .asc/project.json app_id, then .asc/config.json app_id.
  - PLATFORM defaults to IOS.
USAGE
}

cmd="${1:-status}"
shift || true

case "${cmd}" in
  doctor)
    asc-codex auth doctor
    asc-codex auth status --validate
    ;;
  status)
    asc-codex apps get --id "${app_id}" --output table
    asc-codex versions list --app "${app_id}" --limit 5 --output table
    ;;
  latest-build)
    asc-codex builds latest --app "${app_id}" --output table
    ;;
  next-build)
    version="${1:-}"
    platform="${2:-IOS}"
    if [[ -z "${version}" ]]; then
      echo "error: VERSION is required for next-build." >&2
      echo "example: ./scripts/asc-sync.sh next-build 1.7 IOS" >&2
      exit 2
    fi
    asc-codex builds latest --app "${app_id}" --version "${version}" --platform "${platform}" --next --output table
    ;;
  versions)
    asc-codex versions list --app "${app_id}" --limit 10 --output table
    asc-codex pre-release-versions list --app "${app_id}" --limit 10 --output table
    ;;
  snapshot)
    asc-codex-snapshot "${app_id}"
    ;;
  --help|-h|help)
    usage
    ;;
  *)
    echo "error: unknown command '${cmd}'." >&2
    usage >&2
    exit 2
    ;;
esac
