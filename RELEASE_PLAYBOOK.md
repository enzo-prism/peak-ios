# Peak iOS Release Playbook

## Current state (as of July 15, 2026)
- App: `peak.surf` (`com.designprism.peak`)
- App ID: `6757644027` · Team: `L49MKXGVM4`
- **App Store (live):** `2.4` (`READY_FOR_SALE`)
- **Shipping train:** `2.6` build **2** — Stats 2.0, Apple Health (opt-in), full backup, History search, spots map, HIG polish + privacy policy aligned for review
- See `CHANGELOG.md` for full 2.5 + 2.6 notes (users jump from live **2.4** → **2.6**)

> ⚠️ **Branch strategy.** `main` is the active trunk.
> **`feature/streamlined-log-session` is STALE (pre-2.0 design) — do NOT ship or merge it.**
> **`feature/2.5-widgets` is deferred** (needs one-time App Group registration) — do not claim widgets in store copy.
> Land fixes on short branches off `main`, PR, merge.

## 30-second status check
```bash
./scripts/release-cli.sh 2.6 IOS
./scripts/asc-sync.sh status
./scripts/asc-sync.sh latest-build
./scripts/asc-sync.sh next-build 2.6 IOS
./scripts/gh-tooling.sh status
asc review status --app 6757644027
asc validate --app 6757644027 --version 2.6 --platform IOS
```

## Cut a TestFlight build (asc CLI, end-to-end)
Artifacts land in `.asc/artifacts/`. From clean `main` with tests green:

```bash
# 1. Next build number + set CURRENT_PROJECT_VERSION
asc builds next-build-number --app 6757644027 --version 2.6 --platform IOS
asc xcode version edit --version 2.6 --build-number N
#    If MARKETING_VERSION changes, edit BOTH build configs in project.pbxproj.

# 2. Archive → export → upload
asc xcode archive --project Peak.xcodeproj --scheme Peak --configuration Release \
  --archive-path .asc/artifacts/Peak-2.6-N.xcarchive --overwrite
asc xcode export --archive-path .asc/artifacts/Peak-2.6-N.xcarchive \
  --export-options .asc/export-options-app-store.plist \
  --ipa-path .asc/artifacts/Peak-2.6-N.ipa
asc builds upload --app 6757644027 --ipa .asc/artifacts/Peak-2.6-N.ipa

# 3. Wait until processingState == VALID
asc builds wait --app 6757644027 --latest

# 4. REQUIRED: export compliance (standard HTTPS only → exempt)
asc builds update --app 6757644027 --latest --uses-non-exempt-encryption=false
```

Peak only uses standard HTTPS (Open-Meteo auto-fill). Always set
`--uses-non-exempt-encryption=false`.

## Promote a version to the App Store (review)
Preferred path when a VALID build already exists (e.g. 2.6 build 1):

```bash
# Stage: create version, copy metadata, attach build, readiness checks
# After build 2 is VALID:
BUILD_ID=$(asc builds list --app 6757644027 --limit 1 --output json | jq -r '.data[0].id')

asc release stage \
  --app 6757644027 \
  --version 2.6 \
  --build "$BUILD_ID" \
  --copy-metadata-from 2.4 \
  --exclude-fields whatsNew,promotionalText \
  --confirm

# Then set What's New + review notes (see below), validate, submit:
asc validate --app 6757644027 --version 2.6 --platform IOS
asc review submit --app 6757644027 --version 2.6 \
  --build "$BUILD_ID" --confirm
asc status --app 6757644027
```

### App Review notes template (2.6)
- Offline-first surf log. **No sign-in / accounts / demo credentials.**
- Main path: Log → Log Session → spot name → Save Session → appears in History + Stats.
- Location is **optional** (pins unlock map + conditions auto-fill only).
- Apple Health is **opt-in** (Settings → Apple Health): save surfing workouts; import Watch HR/calories.
- Auto-fill Conditions: user-tapped only; HTTPS GET to Open-Meteo with coordinates + time window.
- Photos: system PhotosPicker (no full-library permission).
- Encryption: standard HTTPS only (exempt).

### What's New guidance
Cover **user-visible 2.5 + 2.6** because live users are on **2.4**. Do not mention widgets.

## Definition of done before any upload / submit
- `./scripts/test.sh` green
- `./scripts/design-check.sh` for UI changes
- Changes on `main` (PR'd if branch work)
- `CHANGELOG.md` + this playbook current
- Privacy policy mentions Health, location, Open-Meteo, local-only storage
- Export compliance set on the build
- `asc validate` clean before `asc review submit`
