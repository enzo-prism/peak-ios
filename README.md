# Peak - Surf Log

Peak is a fast, private surf-session logbook. Track when you surfed, where you paddled out, what gear you rode, who you surfed with, and the conditions, then look back anytime.

## Current state

- **App Store (live):** `2.6`
- **App Store (in review):** `3.2` build **1** (submitted 2026-07-29) — first public
  release since 2.6; carries the 2.7–3.2 trains plus both audit-fix rounds.
- **`main` (unreleased):** 3.3 system integration on top of 3.2 — Spotlight/`OpenIntent`,
  iPad sidebar + split navigation, unlogged Watch-surf Log card, Last Session
  widget deep links, session route map, plus the performance and library-UX
  passes (predicate library fetches, dedicated Search prompt, HIG detail chrome).
  No schema change. See `CHANGELOG.md`. Does not replace the in-review 3.2 App
  Store binary.
- **`prod`:** git snapshot at the same SHA as `main`. App Store production remains
  the in-review `3.2` train; pushing `prod` is not a store submit. See
  `RELEASE_PLAYBOOK.md`.
- **Not merged, not shipped:** the `3.1` watchOS companion lives on
  `feature/3.1-watchos`. It is code-complete and its pure logic is unit-tested, but
  it has never recorded a real surf; it stays off `main` until it passes real-device
  ocean testing.
- **Test baseline on `main`:** 546 unit, 54 UI after the performance and library-UX passes (was 525; iPhone; 8 of the 54 currently fail on the iPad leg of `design-check.sh` — pre-existing breakage, see AGENTS.md).
- **App Group** `group.com.designprism.peak` is registered (2026-07-29). Device
  archives use manual signing — see `RELEASE_PLAYBOOK.md`.

## Product scope
- Offline-first, on-device storage only — no accounts, social features, or analytics
- Quick session logging (date + spot required; location/pin optional)
- Optional wind, wave height, and tide conditions
- Optional auto-fill of surf conditions via Open-Meteo (only when triggered)
- Quick-start session scaffolding in New Session (use last session setup, recent spots, and recent gear)
- Photo and video attachments per session
- History timeline with search + filters (spot, gear, buddy, rating, date range)
- Stats 2.0 (time in water, streaks, heatmap, monthly bars, spot mix, conditions insights)
- Spot library + map of pinned breaks (name-only spots are fine)
- Home/Lock Screen widgets, Siri/Shortcuts intents, Control Center control, and a Live Activity session timer
- Wave stats (count, top speed, longest ride, paddle distance) estimated from Apple Watch workout routes — always editable
- Board Report, On This Day, Year in Review, and opt-in monthly goals
- Optional on-device narrative insights (Apple Intelligence devices only), where every figure is still computed by Peak
- Optional Apple Health (save surfing workouts; import Watch HR/calories/routes; Log-tab card for an unlogged Watch surf; optional local notify) — iPhone, opt-in
- Session GPS overlay on detail (transient HealthKit route; coordinates never stored)
- iPad sidebar + split views (iOS 18); Spotlight search for sessions, spots, and gear
- JSON + CSV export; full `.peakbackup` with media; JSON/backup restore (merge or replace)
- Session share card

## Surf conditions auto-fill
- Requires a session start time, duration, and a surf break with a pinned location.
- Pulls marine + wind data from Open-Meteo, averages across the session window, and stores the source + fetch time.
- Also records tide: `sea_level_height_msl` relative to mean sea level plus a rising / high / falling / low trend, read from the hourly curve either side of the session.
- `TideService` (NOAA CO-OPS, US stations) is built and unit-tested but **not yet wired** into auto-fill. Every tide reading on screen today is the Open-Meteo modelled curve. Wiring the station layer is open work — see `ARCHITECTURE.md`.
- Never runs automatically; it only fires when the user taps **Auto-fill Conditions**.

## Best Window Today
- A card at the top of the Log tab for the user's most-logged located spots: the best few hours today, with the rated session it resembles.
- `WindowScorer` ranks each forecast hour by similarity to that surfer's own rated sessions at that spot — rating-weighted kernel regression, no coastline orientation or break physics modelled.
- Gated on **confidence**, not on the predicted rating: below the threshold the card asks for more rated sessions rather than inventing a window.
- Idle until you tap **Check conditions**, unless you opt in to Settings → "Refresh automatically when I open Peak" (**off by default**).

## Wave stats
- Peak reads the GPS route Apple Watch already stores with a surf workout and derives wave count, top speed, longest ride (duration + distance), and paddle distance on-device.
- `WaveAnalyzer` is CoreLocation-free and deterministic, so its whole suite runs on synthetic routes — no device, no entitlement, no ocean.
- **Everything is an editable estimate.** Editing a value marks the session `edited`/`manual`, after which no import overwrites it. Manual entry works with no workout at all.
- Only the workout UUID is persisted; the route is re-read from HealthKit on demand. Route reads stay behind the existing `healthSyncEnabled` opt-in.
- Personal records (most waves, fastest wave, longest ride) surface on Stats and are suppressed entirely when no session carries wave stats.

## On-device insights (optional)
- `InsightsEngine` turns pre-aggregated calculator output into a small facts value, and Apple's on-device model supplies **connective language only**.
- Three independent guarantees that no figure is model-generated: the prompt contains no numerals, the `@Generable` schema has no numeric field, and `InsightsSanitizer` discards any generated text containing a digit, number word, or unknown capitalised word.
- Availability-gated and silent: on a device that cannot run the model (pre-iOS 26, ineligible hardware, Apple Intelligence off) the same surfaces render the identical facts as plain stats.
- No network call was added. Inference is on-device.

## Widgets, Siri & Live Activity
- **Widgets**: *Surf Streak* (opens a new session) and *Last Session* (opens **that** session via `peak://session?id=`; empty state still uses `peak://new-session`). Last Session supports small/medium/extra-large plus accessory, a configurable spot from snapshot glances, and Start Session on medium and extra-large.
- Widgets never open the SwiftData store. The app derives a small `PeakWidgetSnapshot` and publishes it to the shared App Group container.
- **App Intents**: `SurfSessionEntity`, `SpotEntity`, and `GearEntity` are donated to an on-device Spotlight index (`PeakLogbook`). Log / Start / End / Last Session / Sessions This Month / Search ship with Siri phrases; iOS 18 `OpenIntent`s open the matching detail.
- **Live Activity**: a session timer on the Lock Screen and in the Dynamic Island, drawn with `Text(timerInterval:)` so Peak sends no push updates and holds no push token.
- The in-progress session lives in App-Group `UserDefaults`, **not** SwiftData.

## Architecture overview
- **UI**: SwiftUI tabs (`Log`, `History`, `Stats`, `Quiver`, `More`) with shared glass styling in `Peak/Supporting/Theme.swift`. iOS 18 adds a Search tab and a Library sidebar (Spots / Buddies) via `.sidebarAdaptable` on regular width.
- **Data**: SwiftData models (`SurfSession`, `Spot`, `Gear`, `Buddy`, `SessionMedia`) with local-only storage, currently at schema **V10**.
- **Navigation**: `PeakNavigationCoordinator` routes widget, Spotlight, and Siri opens (`peak://session`, `spot`, `gear`, `search`, `new-session`).
- **Editing**: `SessionDraft` stages changes before saving to a `SurfSession`.
- **Media**: Photos stored inline; videos stored in `Application Support/SessionMedia` and referenced by filename.
- **Conditions**: `SurfConditionsService` calls Open-Meteo marine + weather endpoints when auto-fill is tapped; `TideService` adds optional NOAA CO-OPS precision for US spots.
- **Today**: `WindowScorer` + `TodayWindowService` back the Best Window Today card.
- **Wave stats**: `WaveAnalyzer` derives estimates from HealthKit workout routes; `WaveStatsCalculator` computes records.
- **Insights**: `InsightsEngine` (pure Foundation, iOS 17) with `FoundationModelsInsights` behind an availability gate.
- **Stats**: `StatsCalculator`, `UsageMetricsCalculator`, `GearInsightsCalculator`, `YearInReviewCalculator`, `MonthlyGoalCalculator`, `OnThisDayProvider`.
- **Extension**: `PeakWidgets/` hosts the widgets, the Control Center control, and the Live Activity; it shares state with the app through App Group `group.com.designprism.peak`.
- **Export/Import**: `PeakExportManager` handles JSON/CSV export and JSON restore; `BackupManager` handles media-inclusive `.peakbackup` archives.

## Design system
- Adaptive monochrome palette with full light and dark mode support (ink on paper / foam on ocean)
- Liquid-glass surfaces on iOS 26 with system-material fallbacks on iOS 17–18
- System font (SF Pro) with Dynamic Type text styles; SF Symbols throughout
- Spacing and corner-radius tokens in `Theme.Spacing` / `Theme.Radius`
- Contrast tokens are enforced by automated tests in both color schemes (4.5:1 body, 7:1 key text)
- Theming lives in `Peak/Supporting/Theme.swift` and related helpers

## Architecture
- See `ARCHITECTURE.md` for a full overview of the app structure, data model, and key flows.

## Platform decisions
- Platform: Minimum iOS: 17.0 (SwiftData) — unchanged by every release through 3.3
- Data store: SwiftData (local only), schema V10
- UI: SwiftUI
- Targets: `Peak` (app), `PeakWidgets` (widget extension: widgets, Control Center control, Live Activity), `PeakTests`, `PeakUITests`
- App Group: `group.com.designprism.peak`, shared by the app and widget extension
- iOS 18/26-only API (Control Center controls, Foundation Models, interactive snippets) is availability-gated; nothing raises the floor

## Getting started
1. Open `Peak.xcodeproj` in Xcode 17+
2. Select the `Peak` scheme
3. Run on any iOS 17+ simulator or device

> Only the `Peak` folder is a file-system-synchronized group. New files in
> `PeakTests`, `PeakUITests`, or `PeakWidgets` must be registered in
> `project.pbxproj` before the build can see them — see `AGENTS.md`.

## Development commands
- Boot the simulator: `./scripts/boot-sim.sh`
- Build for simulator: `./scripts/build-sim.sh`
- Run fast unit tests only: `./scripts/test-unit.sh`
- Run the default fast gate: `./scripts/test.sh`
- Run iPhone UI tests: `./scripts/test-ui.sh`
- Run UI/design checks on iPhone + iPad: `./scripts/design-check.sh`
- Full tooling health check (ASC + sim build path): `./scripts/tooling-doctor.sh`
- Quick GitHub CLI status snapshot: `./scripts/gh-tooling.sh status`
- Fast release sweep (local + ASC + GH): `./scripts/release-cli.sh [VERSION] [PLATFORM]`
- Tooling setup and release workflow details: `TOOLING.md`

Optional overrides:
- `SCHEME=PeakUnit ./scripts/test.sh`
- `./scripts/test-unit.sh` (uses the `PeakUnit` shared scheme)
- `DESTINATION_NAME="iPhone 16 Pro" ./scripts/build-sim.sh`
- `DESTINATION_NAME="iPhone 17 Pro" DESTINATION_OS=26.2 ./scripts/test-ui.sh`
- `UI_TEST_TARGET="PeakUITests/PeakUILayoutTests" ./scripts/test-ui.sh`
- `UI_TEST_TARGET="PeakUITests/PeakUISmokeTests" ./scripts/design-check.sh`
- `STRICT_DESTINATION=1 ./scripts/build-sim.sh` (fail if preferred simulator is unavailable)

## App Store Connect CLI (ASC)
- Project ASC defaults live in `.asc/project.json`:
  - `app_id`: `6757644027` (`peak.surf`)
  - `default_key_name`: `codex`
- Works with both `asc` and legacy `asc-codex` CLIs (prefers modern `asc` when available).
- Optional local overrides can live in `.asc/config.json` (ignored by git).
- Auth + health check: `./scripts/asc-sync.sh doctor`
- App/version status: `./scripts/asc-sync.sh status`
- Latest build: `./scripts/asc-sync.sh latest-build`
- Next build number for a version: `./scripts/asc-sync.sh next-build 2.6 IOS`
- Full snapshot (app, versions, latest build): `./scripts/asc-sync.sh snapshot`
- Advanced ASC workflow commands (requires modern `asc`): `./scripts/asc-ops.sh`
- Release response checklist: `RELEASE_PLAYBOOK.md`

## Xcode MCP
- MCP defaults for this repo are stored in `.xcodebuildmcp/config.yaml`:
  - `scheme: Peak`
  - `platform: iOS`
  - `workspacePath: Peak.xcodeproj/project.xcworkspace`
  - `simulatorName: iPhone 16 Pro`
- Reuse these defaults when doing MCP-driven boot/list/build/test/install flows.

## GitHub CLI (gh)
- Repo status (auth, repo summary, open PRs/issues, recent CI): `./scripts/gh-tooling.sh status`
- Open PR list only: `./scripts/gh-tooling.sh prs 10`
- Open issue list only: `./scripts/gh-tooling.sh issues 10`
- Workflow run list only: `./scripts/gh-tooling.sh workflows 10`

## Testing

Current suite on `main` / `prod`: **546 unit tests** (`PeakTests`) and **54 UI tests** (`PeakUITests`).

> **Run exactly one `xcodebuild` at a time.** The simulator is a single shared
> resource; concurrent runs produce false failures that look like real bugs. See
> `AGENTS.md` → "Build / Test / Simulator Rules".

- Fast unit-only loop:  
  `./scripts/test-unit.sh`
- Default local/CI gate:  
  `./scripts/test.sh`
- iPhone UI suite:  
  `./scripts/test-ui.sh`
- UI/design validation across iPhone and iPad:  
  `./scripts/design-check.sh`
- Targeted UI run:  
  `UI_TEST_TARGET="PeakUITests/PeakUILayoutTests" ./scripts/test-ui.sh`
- UI tests seed in-memory data when `UITESTS=1` is set (handled by the test target)
- Optional: set `UITESTS_FIXED_DATE=2026-02-01T12:00:00Z` to make seeded UI test data deterministic
- Optional: set `UITESTS_SESSION_MARKER=<text>` to mark a newly created session and make history row lookup deterministic in end-to-end tests

## Privacy and support
- Privacy policy: `PRIVACY.md`
- Support contact: `SUPPORT.md`
- Data stays on-device; no accounts or analytics. Optional Open-Meteo and NOAA CO-OPS requests are made only when you use Auto-fill Conditions or Best Window Today.
- On-device insight generation adds no network call; inference runs on the phone.
- HealthKit reads (workouts and workout routes) are behind the `healthSyncEnabled` opt-in and are a quiet no-op when it is off. Optional Watch-surf notifications are a second toggle, off by default. Spotlight indexing is on-device.

## Acceptance criteria
- Users can log a session in under 60 seconds
- Sessions can be filtered by spot, gear, or buddy
- Stats view shows totals, top spots, and most-used gear
- App works fully offline and stores data locally
- Accessible with Dynamic Type and VoiceOver basics
- Auto-fill conditions only runs on tap and requires a duration + pinned spot
- Best Window Today shows a window only when confidence clears the threshold, never a fabricated one
- Every wave stat is presented as an estimate and is correctable in-app; a user's edit always outranks a derived value
- Every number rendered by an insight surface comes from Peak's own calculators, on every device, with or without Apple Intelligence

## UX Notes
- New-session logging now surfaces a `Quick Start` section with a one-tap "Use last session setup" action and recency-based spot/gear chips to reduce logging friction.
