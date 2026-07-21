# Peak iOS Release Playbook

## Current state (as of July 21, 2026)
- App: `peak.surf` (`com.designprism.peak`)
- App ID: `6757644027` · Team: `L49MKXGVM4`
- **App Store (live):** `2.0` (`READY_FOR_SALE`, since June 11, 2026)
- **TestFlight (beta):** `2.6` — build 1, uploaded 2026-07-13 (`2.5` build 1 previously in beta)
- Versions `2.1`–`2.6` have shipped to **TestFlight only**; the public App Store
  listing is still `2.0`. See `CHANGELOG.md` for what each build contains.
- **`main` carries five unshipped release trains:** `2.7` (ecosystem), `2.8` (tide
  + Best Window Today), `2.9` (quiver analytics / memory / first run), `3.0` (wave
  stats), `3.2` (on-device insights). `MARKETING_VERSION` in `project.pbxproj` is
  still **`2.6`** — none of these has been archived or uploaded. Pick the version
  train deliberately when you cut the next build, and set `MARKETING_VERSION` in
  **both** build configs.
- **Suite baseline on `main`: 434 unit tests, 51 UI tests.**

> 🚫 **Release blocker — App Group not registered.** See the next section. Widgets
> and Live Activity cannot be built for a device or archived until it is fixed, so
> **no `2.7`+ archive can succeed today.**

> ⚠️ **Branch strategy.** `main` is the active trunk. Land every fix on a short
> branch off `main`, PR it, and merge.
> - **`feature/streamlined-log-session` is a STALE divergent branch (pre-2.0
>   design) — do NOT ship from it or merge it into `main`; it would regress the trunk.**
> - **`feature/3.1-watchos` is code-complete but must NOT be merged or shipped.**
>   The watch app has never recorded a real surf; it is gated on real-device ocean
>   testing to validate the `WaveAnalyzer` constants. Do not list watchOS support in
>   any release note, App Store metadata, or screenshot set.

## App Group registration (blocks widgets, Live Activity, and every 2.7+ archive)

`group.com.designprism.peak` is declared in both entitlements files
(`Peak/Peak.entitlements`, `PeakWidgets/PeakWidgets.entitlements`) but is **still
unregistered in the Developer portal**. Until it exists:

- simulator builds and the full test suite are fine (code signing is disabled there);
- **any device build or `asc xcode archive` of `Peak` or `PeakWidgets` fails to sign.**

What is already done:
- The `APP_GROUPS` capability **is** enabled on both `com.designprism.peak` and
  `com.designprism.peak.PeakWidgets`.

What remains, and it is human-only:
- Create the App Group itself (Developer portal → Identifiers → App Groups, team
  `L49MKXGVM4`) and associate it with both bundle IDs.
- **The App Store Connect API cannot create App Groups.** Neither `asc` nor
  `-allowProvisioningUpdates` can do this — it is portal UI or the Xcode
  Signing & Capabilities GUI, nothing else. Do not spend time scripting around it.

## 30-second status check
```bash
./scripts/release-cli.sh 2.6 IOS
./scripts/asc-sync.sh status
./scripts/asc-sync.sh latest-build
./scripts/asc-sync.sh next-build 2.6 IOS
./scripts/gh-tooling.sh status
```

## Cut a TestFlight build (asc CLI, end-to-end)
The release path runs entirely through the **asc CLI**; build artifacts land in
`.asc/artifacts/` (gitignored). From a clean `main` (or a branch off it) with tests
green — and, for anything `2.7`+, with the App Group registered:

```bash
# 0. Pre-flight: any NEW bundle id or capability must be registered BEFORE archiving.
#    `-allowProvisioningUpdates` cannot create portal resources with an API key,
#    and App Groups cannot be created by the API at all (see above).

# 1. Determine + set the next build number
asc builds next-build-number --app 6757644027 --version 2.7 --platform IOS   # → next build N
asc xcode version edit --version 2.7 --build-number N
#   NOTE: `version edit` updates CURRENT_PROJECT_VERSION only. If MARKETING_VERSION
#   changes too — it does for every train on main right now, which still says 2.6 —
#   edit BOTH build configs in Peak.xcodeproj/project.pbxproj. Keep the PeakWidgets
#   target's version aligned with the app's — it drifted once during 2.7 development,
#   alongside a stale DEVELOPMENT_TEAM that failed as "No Account for Team".

# 2. Archive (Release) -> export (App Store Connect) -> upload
asc xcode archive --project Peak.xcodeproj --scheme Peak --configuration Release \
  --archive-path .asc/artifacts/Peak-2.7-N.xcarchive --overwrite
asc xcode export --archive-path .asc/artifacts/Peak-2.7-N.xcarchive \
  --export-options .asc/export-options-app-store.plist \
  --ipa-path .asc/artifacts/Peak-2.7-N.ipa
asc builds upload --app 6757644027 --ipa .asc/artifacts/Peak-2.7-N.ipa

# 3. Wait for processing (~2-15 min) until processingState == VALID
asc builds list --app 6757644027 --limit 3        # or ./scripts/asc-sync.sh latest-build

# 4. REQUIRED: declare export compliance, or the build stays
#    MISSING_EXPORT_COMPLIANCE and testers cannot install it.
asc builds update --app 6757644027 --latest --uses-non-exempt-encryption=false
#    -> internalBuildState flips to IN_BETA_TESTING. Internal Test Group A receives
#       it automatically; internal testing needs no beta review.
```

Peak only makes standard HTTPS calls (Open-Meteo conditions auto-fill, NOAA CO-OPS
tide predictions), so encryption is exempt — `--uses-non-exempt-encryption=false`
is always correct here. On-device model inference adds no network call and does not
change this answer.

The `ExportOptions` plist (`destination=export`, `method=app-store-connect`,
`signingStyle=automatic`, `teamID=L49MKXGVM4`, `manageAppVersionAndBuildNumber=false`)
is reusable across builds. **The tracked copy is `.asc/export-options-app-store.plist`** —
`.asc/artifacts/` is gitignored, so the per-build plists in there exist only on the
machine that made them and must not be referenced as if checked in.

### App Review notes for the current trains
- Widgets, App Intents, and the Live Activity render **local data only** — no
  accounts, no backend, no push token (the timer uses `Text(timerInterval:)`).
- Wave stats are derived on-device from HealthKit workout routes the user already
  has, behind an opt-in, and are presented as editable estimates.
- On-device insights use Apple's Foundation Models; nothing is sent off-device.

## Promote a version to the App Store
When taking a train from TestFlight to the public listing:
1. Create/select the App Store version and attach the chosen build.
2. Update "What's New", screenshots, and metadata (`asc versions`,
   `asc localizations`, `asc screenshots`, `asc metadata`).
3. Validate readiness, then submit for review.
4. Track via `./scripts/asc-sync.sh status` and `./scripts/asc-ops.sh workflow-run release_readiness`.

## Definition of done before any upload
- `./scripts/test.sh` green (or the targeted UI tests for the touched surface),
  **run one at a time** — the simulator is a shared resource and concurrent
  `xcodebuild` runs produce false passes and false failures. See `AGENTS.md`.
- Test counts reconciled against the baseline (434 unit / 51 UI). A smaller count
  with no failures means a stale test runner, not a green suite.
- `./scripts/design-check.sh` for any UI change.
- For `2.7`+: App Group registered, or the archive will not sign.
- `MARKETING_VERSION` bumped in **both** build configs, app and widget target aligned.
- Changes committed on a branch off `main`, PR'd via `gh`, and merged.
- `CHANGELOG.md` updated with the build's entry, and its "Status at a glance"
  header updated to the new TestFlight train.
