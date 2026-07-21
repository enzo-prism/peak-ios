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

## ASC Release Workflow (end-to-end)

Cut a TestFlight build entirely through the asc CLI; artifacts land in `.asc/artifacts/`.

1. **Next build number:** `asc builds next-build-number --app 6757644027 --version <V> --platform IOS`, then `asc xcode version edit --version <V> --build-number <N>` (updates `CURRENT_PROJECT_VERSION`; edit `MARKETING_VERSION` in both build configs of `project.pbxproj` if it changes).
2. **Archive (Release):** `asc xcode archive --project Peak.xcodeproj --scheme Peak --configuration Release --archive-path .asc/artifacts/Peak-<V>-<N>.xcarchive --overwrite`
3. **Export to IPA:** `asc xcode export --archive-path … --export-options .asc/artifacts/ExportOptions-2.4-3.plist --ipa-path .asc/artifacts/Peak-<V>-<N>.ipa`
4. **Upload:** `asc builds upload --app 6757644027 --ipa .asc/artifacts/Peak-<V>-<N>.ipa`
5. **Wait for `VALID`:** poll `asc builds list --app 6757644027 --limit 3` (or `./scripts/asc-sync.sh latest-build`).
6. **Declare export compliance (REQUIRED):** `asc builds update --app 6757644027 --latest --uses-non-exempt-encryption=false` → flips the build to `IN_BETA_TESTING` for internal Test Group A. Peak only uses standard HTTPS, so encryption is exempt.

See `RELEASE_PLAYBOOK.md` for current version/build status, the branch-strategy warning, and the App Store submission steps.

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
  - `./scripts/test-unit.sh`
  - `./scripts/test.sh`
  - `./scripts/test-ui.sh`
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
3. `./scripts/design-check.sh` (UI changes)
4. `./scripts/asc-sync.sh status`
5. `./scripts/asc-sync.sh latest-build`
6. `./scripts/asc-ops.sh next-build 2.6 IOS` (or target version)
7. Stage / validate / submit (see `RELEASE_PLAYBOOK.md`):
   - `asc release stage --app 6757644027 --version 2.6 --build <BUILD_ID> --copy-metadata-from 2.4 --confirm`
   - `asc validate --app 6757644027 --version 2.6 --platform IOS`
   - `asc review submit --app 6757644027 --version 2.6 --build <BUILD_ID> --confirm`
8. Monitor: `asc status --app 6757644027` · `./scripts/gh-tooling.sh status`

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

- `./scripts/test-unit.sh` uses the `PeakUnit` shared scheme so fast unit runs are isolated from UI-test compile/runtime failures.
- `./scripts/test.sh` is the default local/CI gate and delegates to the fast unit lane.
- `./scripts/test-ui.sh` runs the iPhone UI suite explicitly when a change needs app-flow coverage.
- `UI_TEST_TARGET="PeakUITests/PeakUILayoutTests" ./scripts/test-ui.sh` runs one UI class on iPhone.
- `UI_TEST_TARGET="PeakUITests/PeakUISmokeTests" ./scripts/design-check.sh` runs one UI class across iPhone and iPad.
- `./scripts/design-check.sh` runs unit tests once, then UI tests on both iPhone and iPad, and writes ignored local artifacts under `artifacts/design-check/`.
- For deterministic UI tests, we set `UITESTS_FIXED_DATE` and `UITESTS_SESSION_MARKER` in the test launch environment.
- Marker flow allows E2E selectors to target the newly created session row that includes the marker note text.
