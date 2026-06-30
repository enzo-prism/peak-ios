# Peak iOS Release Playbook

## Current state (as of June 29, 2026)
- App: `peak.surf` (`com.designprism.peak`)
- App ID: `6757644027` · Team: `L49MKXGVM4`
- **App Store (live):** `2.0` (`READY_FOR_SALE`, since June 11, 2026)
- **TestFlight (beta):** `2.4` train — latest **build 5** (`IN_BETA_TESTING`, internal **Test Group A**)
  - `2.4 (4)` — media-forward session-detail header
  - `2.4 (5)` — + Log Session recent-spot chips overflow fix
- Versions `2.1`–`2.4` have shipped to **TestFlight only**; the public App Store
  listing is still `2.0`. See `CHANGELOG.md` for what each build contains.

> ⚠️ **Branch strategy.** `main` is the active trunk (the "2.0 design": adaptive
> light/dark, HIG, the `heroWaveHeight` block, `ViewThatFits` chips).
> **`feature/streamlined-log-session` is a STALE divergent branch (pre-2.0 design)
> — do NOT ship from it or merge it into `main`; it would regress the trunk.**
> Land every fix on a short branch off `main`, PR it, and merge.

## 30-second status check
```bash
./scripts/release-cli.sh 2.4 IOS
./scripts/asc-sync.sh status
./scripts/asc-sync.sh latest-build
./scripts/asc-sync.sh next-build 2.4 IOS
./scripts/gh-tooling.sh status
```

## Cut a TestFlight build (asc CLI, end-to-end)
The release path runs entirely through the **asc CLI**; build artifacts land in
`.asc/artifacts/`. From a clean `main` (or a branch off it) with tests green:

```bash
# 1. Determine + set the next build number
asc builds next-build-number --app 6757644027 --version 2.4 --platform IOS   # → next build N
asc xcode version edit --version 2.4 --build-number N
#   NOTE: `version edit` updates CURRENT_PROJECT_VERSION only. If MARKETING_VERSION
#   changes too, edit BOTH build configs in Peak.xcodeproj/project.pbxproj.

# 2. Archive (Release) -> export (App Store Connect) -> upload
asc xcode archive --project Peak.xcodeproj --scheme Peak --configuration Release \
  --archive-path .asc/artifacts/Peak-2.4-N.xcarchive --overwrite
asc xcode export --archive-path .asc/artifacts/Peak-2.4-N.xcarchive \
  --export-options .asc/artifacts/ExportOptions-2.4-3.plist \
  --ipa-path .asc/artifacts/Peak-2.4-N.ipa
asc builds upload --app 6757644027 --ipa .asc/artifacts/Peak-2.4-N.ipa

# 3. Wait for processing (~2-15 min) until processingState == VALID
asc builds list --app 6757644027 --limit 3        # or ./scripts/asc-sync.sh latest-build

# 4. REQUIRED: declare export compliance, or the build stays
#    MISSING_EXPORT_COMPLIANCE and testers cannot install it.
asc builds update --app 6757644027 --latest --uses-non-exempt-encryption=false
#    -> internalBuildState flips to IN_BETA_TESTING. Internal Test Group A receives
#       it automatically; internal testing needs no beta review.
```

Peak only makes standard HTTPS calls (Open-Meteo conditions auto-fill), so
encryption is exempt — `--uses-non-exempt-encryption=false` is always correct here.

The `ExportOptions` plist (`destination=export`, `method=app-store-connect`,
`signingStyle=automatic`, `teamID=L49MKXGVM4`, `manageAppVersionAndBuildNumber=false`)
is reusable across builds; the checked-in copy is `.asc/artifacts/ExportOptions-2.4-3.plist`.

## Promote a version to the App Store
When taking the 2.4 train from TestFlight to the public listing:
1. Create/select the App Store version (e.g. `2.4`) and attach the chosen build.
2. Update "What's New", screenshots, and metadata (`asc versions`,
   `asc localizations`, `asc screenshots`, `asc metadata`).
3. Validate readiness, then submit for review.
4. Track via `./scripts/asc-sync.sh status` and `./scripts/asc-ops.sh workflow-run release_readiness`.

## Definition of done before any upload
- `./scripts/test.sh` green (or the targeted UI tests for the touched surface).
- `./scripts/design-check.sh` for any UI change.
- Changes committed on a branch off `main`, PR'd via `gh`, and merged.
- `CHANGELOG.md` updated with the build's entry.
