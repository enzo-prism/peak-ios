# Peak Tooling & Release Setup

This document keeps the repository’s external tooling setup aligned for fast iteration and release work.

## ASC CLI (App Store Connect)

- Install either:
  - Apple `asc` CLI (preferred)
  - or `asc-codex` (legacy compatibility)
- Authenticate once:
  - `asc auth login` (or `asc-codex auth login` for legacy clients)
- Configure the app target in `.asc/project.json`:
  - `app_id`: `6757644027`
  - `default_key_name`: `codex`
  - `default_platform`: `IOS`
- Verify before a release sweep:
  - `./scripts/asc-sync.sh doctor`
  - `./scripts/asc-sync.sh status`
  - `./scripts/asc-sync.sh snapshot`

## Xcode MCP / Xcode-driven automation

- MCP config is versioned at `.xcodebuildmcp/config.yaml`.
- Keep defaults aligned with local testing:
  - `workspacePath: Peak.xcodeproj/project.xcworkspace`
  - `scheme: Peak`
  - `platform: iOS`
  - `simulatorName: iPhone 16 Pro`
- Use the repo scripts for fast local loops:
  - `./scripts/boot-sim.sh`
  - `./scripts/build-sim.sh`
  - `./scripts/test.sh`
- Validate toolchain + ASC + sim path together:
  - `./scripts/tooling-doctor.sh`

## GitHub CLI

- Install GitHub CLI (`gh`) and authenticate with:
  - `gh auth login`
  - `gh auth setup-git` (optional, useful for signed checkout workflows)
- Quick repo snapshot:
  - `./scripts/gh-tooling.sh status`
- Issue/PR/workflow views:
  - `./scripts/gh-tooling.sh prs 10`
  - `./scripts/gh-tooling.sh issues 10`
  - `./scripts/gh-tooling.sh workflows 10`

## Release check flow

1. `./scripts/tooling-doctor.sh`
2. `./scripts/test.sh`
3. `./scripts/asc-sync.sh status`
4. `./scripts/asc-sync.sh latest-build`
5. `./scripts/asc-ops.sh next-build <VERSION> IOS`

## Push flow (to `main`)

When local changes are ready:

1. `git status`
2. `git add` your intended files
3. `git commit -m "doc: update tooling and workflow docs"`
4. `git checkout main`
5. `git pull --rebase`
6. `git merge --ff-only <your-branch>` (or rebase + fast-forward as your workflow prefers)
7. `git push origin main`

## Test environment notes

- For deterministic UI tests, we set `UITESTS_FIXED_DATE` and `UITESTS_SESSION_MARKER` in the test launch environment.
- Marker flow allows E2E selectors to target the newly created session row that includes the marker note text.
