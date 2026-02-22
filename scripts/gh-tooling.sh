#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<USAGE
Usage:
  ./scripts/gh-tooling.sh status
  ./scripts/gh-tooling.sh prs [LIMIT]
  ./scripts/gh-tooling.sh issues [LIMIT]
  ./scripts/gh-tooling.sh workflows [LIMIT]

Defaults:
  LIMIT defaults to 8 for issue/PR/workflow listings.
USAGE
}

require_cmd() {
  local cmd="$1"
  if ! command -v "$cmd" >/dev/null 2>&1; then
    echo "error: required command '$cmd' is not installed or not on PATH." >&2
    exit 127
  fi
}

require_cmd gh

cmd="${1:-status}"
shift || true

ensure_auth() {
  if ! gh auth status >/dev/null 2>&1; then
    echo "error: GitHub CLI is not authenticated. Run 'gh auth login' and re-run this command." >&2
    exit 1
  fi
}

case "${cmd}" in
  status)
    ensure_auth

    echo
    echo "Repository snapshot:"
    gh repo view --json nameWithOwner,description,isPrivate,defaultBranchRef,url --template $'{{.nameWithOwner}}\nPrivate: {{if .isPrivate}}yes{{else}}no{{end}}\nDefault branch: {{.defaultBranchRef.name}}\nURL: {{.url}}\n'

    echo
    echo "Open pull requests (latest):"
    gh pr list --state open --limit "${GH_PR_LIMIT:-8}"

    echo
    echo "Open issues (latest):"
    gh issue list --state open --limit "${GH_ISSUE_LIMIT:-8}"

    echo
    echo "Recent CI runs:"
    gh run list --limit "${GH_WORKFLOW_LIMIT:-8}"
    ;;
  prs)
    ensure_auth
    gh pr list --state open --limit "${1:-${GH_PR_LIMIT:-8}}"
    ;;
  issues)
    ensure_auth
    gh issue list --state open --limit "${1:-${GH_ISSUE_LIMIT:-8}}"
    ;;
  workflows)
    ensure_auth
    gh run list --limit "${1:-${GH_WORKFLOW_LIMIT:-8}}"
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
