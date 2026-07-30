# Peak Architecture

This document describes the runtime structure, data model, and key flows in Peak. It is intended for contributors and maintainers.

**Overview**
- UI is built in SwiftUI with a tab-based shell.
- Data is stored locally in SwiftData with migration support (currently schema V10).
- Two targets ship in the app: `Peak` and the `PeakWidgets` extension (widgets, Control Center control, Live Activity). They share state through App Group `group.com.designprism.peak` and never through the SwiftData store.
- No backend, accounts, or analytics. Networking is only ever a user-initiated HTTPS call to Open-Meteo or NOAA CO-OPS. On-device language-model inference adds no network call.
- Deployment target is iOS 17.0. Everything newer — Control Center controls (18), Foundation Models (26), interactive snippets (26) — is availability-gated and degrades to silence, never to a broken surface.

**App Shell & Navigation**
- Entry point: `Peak/PeakApp.swift`
- Tabs and routes: `Peak/ContentView.swift`
- Tabs: Log, History, Stats, Quiver, More
- Styling: `Peak/Supporting/Theme.swift` and `Peak/Supporting/GlassHelpers.swift`
- Deep links: widgets and the Live Activity hand back `peak://new-session`, resolved in `ContentView.onOpenURL` (`Peak/WidgetSnapshot.swift` owns the URL constants and the host/path normalization)

**Data Model & Storage**
- SwiftData models: `Peak/Models/SurfSession.swift`, `Peak/Models/Spot.swift`, `Peak/Models/Gear.swift`, `Peak/Models/Buddy.swift`, `Peak/Models/SessionMedia.swift`
- Draft/edit state: `Peak/Models/SessionDraft.swift`
- Schema + migrations: `Peak/Supporting/ModelSchema.swift` (see `PeakMigrationPlan`); the live container targets the HEAD versioned schema in `Peak/Supporting/PeakDataStore.swift`
- Storage is local only; UI tests seed in-memory data via `Peak/Supporting/PreviewData.swift`
- **Schema invariant:** every past `PeakSchemaVn` is a *frozen* inline snapshot of the model shape it shipped with; only the HEAD schema (`PeakSchemaV10`, `Schema.Version(1, 9, 0)`) references the live model classes. Editing a live `@Model` field therefore silently redefines the shipped HEAD version — so before changing any field, freeze the current HEAD as the next `Vn` snapshot and add a new live-referencing HEAD carrying the delta plus a `.lightweight` stage. Guards in `ModelMigrationTests` enforce this: `testHeadSchemaShapeIsPinned` fails the moment HEAD's field set drifts, `testFrozenV8SnapshotShapeIsPinned` / `testFrozenV9SnapshotShapeIsPinned` fail if a frozen snapshot is ever touched, and `testV7ToV8…` / `testV8ToV9…` / `testV9ToV10MigrationAddsWaveStatFieldsAsNil` each exercise a real on-disk staged migration. Note: SwiftData rejects two identical-shape schemas in one plan ("duplicate version checksums"), so a no-op version bump is invalid — freeze only alongside a genuine shape change.
- **Schema history (recent):**
  - **V9** (`1.8.0`, release 2.8) — `SurfSession.seaLevelHeightM`, `SurfSession.tideTrend`, `Spot.tideStationId`. V8 frozen in the same change.
  - **V10** (`1.9.0`, release 3.0) — `SurfSession.waveCount`, `topSpeedKph`, `longestRideSeconds`, `longestRideMeters`, `paddleDistanceMeters`, `waveStatsSource`, `linkedWorkoutID`. V9 frozen in the same change.
  - Both are additive and `.lightweight`; every new field is optional and migrates in as `nil`. No route coordinates are persisted — only the workout UUID.
- **CloudKit note:** the models are intentionally *not* CloudKit-ready — `Spot`/`Gear`/`Buddy` use `@Attribute(.unique) key`, and several attributes are non-optional without defaults. Adding sync later would be a schema-wide breaking migration (drop uniques, make everything optional/defaulted, dedupe in code), not an additive change. This is a deliberate offline-first trade-off.

**Session Logging Flow**
- Log screen: `Peak/Views/Log/LogView.swift`
- Editor: `Peak/Views/Log/SessionEditorView.swift`
- Session editor writes to `SessionDraft`, then commits to `SurfSession`
- First paint is one focused card (date/time prefilled to now + spot); everything else lives in collapsed disclosure groups (progressive disclosure)
- Required input: a spot (a spot itself only requires a name — location/pin are optional and can be added later)
- Optional inputs: duration, rating, notes, gear, buddies, media, wind/wave (menu pickers), tide, wave stats
- The Log hero also carries **Start Session** beside Log Session, and shows a running timer with End Session while a session is in progress
- The Log tab additionally hosts the Best Window Today, On This Day, and (in December) Year in Review cards, so it queries the full session history — the recents list stays limited to three
- First launch shows `WelcomeView` before any of this, once, behind `@AppStorage("hasSeenWelcome")`

**Surf Conditions Auto-Fill**
- Triggered by the user in `SessionEditorView`
- Requirements: duration + surf break with pinned latitude/longitude
- Service layer: `Peak/Supporting/SurfConditionsService.swift`
- Mapping and display helpers: `Peak/Supporting/SurfConditionsMapping.swift`, `Peak/Supporting/SurfConditionsFormatter.swift`
- Data stored on session: wind, wave, swell, water temperature, tide, source, fetch time, and coordinates
- Fetched data is averaged across the session time window

**Tide**
- The marine request asks for `sea_level_height_msl` and extends three hours either side of the session window, so the hourly curve has enough shape to read a turning point. Every other reading still averages over the session window only.
- Trend (rising / high / falling / low) is derived from that curve; `TideTrend` lives in `Peak/Models/TideTrend.swift` because SwiftData stores its raw value on `SurfSession`.
- Optional US precision (**built, not yet wired in**): `Peak/Supporting/TideService.swift` resolves the nearest NOAA CO-OPS station once per spot (to be cached on `Spot.tideStationId`, the V9 field reserved for it) and fetches harmonic high/low predictions. Free, no key, no account. The service is complete and covered by `SurfConditionsServiceTests`, but nothing calls it from the app yet — every tide reading a user sees today comes from the Open-Meteo modelled curve, and `Spot.tideStationId` is never written. Wiring it into the auto-fill path is the open work.
- **Every failure path resolves to `nil` and the caller silently keeps the Open-Meteo curve.** No station nearby, station list unreachable, malformed response, spot outside the US — none of these is an error, and none is ever presented as one. A 120 km cap stops a spot in Baja or Nova Scotia adopting a distant American gauge.
- Only the NOAA layer quotes a datum (MLLW), because only it has one. Copy never claims chart-datum height or exact turn times from the modelled curve.

**Best Window Today**
- UI: `Peak/Views/Today/BestWindowTodayCard.swift`, a card at the top of the Log tab for the user's most-logged located spots
- Orchestration: `Peak/Supporting/TodayWindowService.swift` fetches the next 24 hours of marine + wind + sea level
- Scoring: `Peak/Supporting/WindowScorer.swift` — rating-weighted kernel regression over the user's own rated sessions at that spot, with leave-one-out self-calibration and missing readings imputed at expected distance rather than skipped. Stateless, deterministic, pure Foundation, and never emits NaN or infinity.
- **No break physics is modelled.** No coastline orientation, no bathymetry, no offshore/onshore classification — those need per-spot data Peak does not have and will not guess. The surfer's rated history *is* the spot model, so wind is described by strength and bearing instead.
- **Confidence gates the card, not the predicted rating.** With zero or one rated session confidence is exactly zero by construction, and a logbook where every session got the same rating carries no signal however large it is. Below threshold the card asks for more rated sessions; it never shows a fabricated window.
- Networking is idle until the user taps "Check conditions", unless they opt into the Settings toggle (off by default). Ranking is `@concurrent` — it costs well over a frame on a deep logbook.

**Media Handling**
- Photos are stored inline on `SessionMedia` (external storage attribute)
- Videos are stored as files in `Application Support/SessionMedia`
- Storage helpers: `Peak/Supporting/SessionMediaStore.swift`
- Display: `Peak/Views/History/SessionDetailView.swift`, `Peak/Views/Components/SessionMediaThumbnailView.swift`

**History & Detail Views**
- History list: `Peak/Views/History/HistoryView.swift`
- Session detail: `Peak/Views/History/SessionDetailView.swift`
- Filters for spot, gear, and buddy are applied in History

**Stats & Trends**
- Stats UI: `Peak/Views/Stats/StatsView.swift` and the cards beside it (`GearInsightsCard`, `MonthlyGoalCard`, `MonthlyRecapCard`, `WaveRecordsCard`, `ConsistencyHeatmapCard`, `MonthlyBarsCard`, `SpotMixDonutCard`, `ConditionsInsightsCard`)
- Calculations: `Peak/Supporting/StatsCalculator.swift`, `Peak/Supporting/UsageMetricsCalculator.swift`
- Every calculator is a stateless enum over session rows; derived values are recomputed rather than cached, so they stay correct under session edit and delete

**Wave Stats (HealthKit route mining)**
- Analyzer: `Peak/Supporting/WaveAnalyzer.swift` — turns a gappy, noisy wrist-GPS track into wave count, top speed, ride lengths and paddle distance. Accuracy-gated fixes, a least-squares speed fit de-biased for the fixes' own noise floor, rolling-median spike rejection, hysteresis thresholds with a sustained-evidence rule, distance integrated from speed rather than summed from positions, and a distance-weighted heading-consistency test.
- It is **CoreLocation-free**: the app maps `CLLocation` to the analyzer's `RouteSample` at the `HealthKitService` boundary. That is what lets the whole suite run on synthetic routes with no device, no entitlement and no ocean (`PeakTests/WaveAnalyzerTests.swift`, `PeakTests/WaveRouteGenerator.swift`).
- All tuning constants live in one struct so they can be re-fitted against real recordings. They are physically reasoned, **not yet ocean-validated** — that is a 3.1 gate.
- Route access: `Peak/Supporting/HealthKitService.swift` adds `HKSeriesType.workoutRoute()` to the read set and streams a workout's locations. Behind the existing `healthSyncEnabled` opt-in; a quiet no-op when off, denied, or the workout has no route.
- Surfaces: `Peak/Views/Components/WaveStatsEditor.swift` (all values editable; wave count uses explicit +/- buttons for 44pt targets rather than a `Stepper`), the session-detail hero, `Peak/Views/More/HealthImportView.swift` preview, `Peak/Supporting/WaveStatsCalculator.swift` + `WaveRecordsCard` for personal records, plus the widget snapshot and share card.
- **Provenance rules.** `waveStatsSource` is `auto` / `edited` / `manual`; a human's number outranks a GPS trace, so re-importing never overwrites an edited or hand-entered session. Zero is data (a skunked session), absent is not (a session that was never tracked shows nothing).
- Analysis is `@concurrent` — it walks tens of thousands of fixes and `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor` would otherwise pin it to the UI.

**Insights & Memory**
- `Peak/Supporting/GearInsightsCalculator.swift` — Board Report: per-gear rating averages bucketed by wave-height band and swell-period band (short <10 s / mid / long 13 s+), with a **minimum of three rated sessions per bucket** before a number is shown. Surfaces on `GearInsightsCard` (boards only) and `BoardReportCard` in gear detail.
- `Peak/Supporting/OnThisDayProvider.swift` — a prior-year session within ±3 days of today, walking backwards a year at a time so New Year's week and Feb 29 behave. Renders as `Peak/Views/Log/OnThisDayCard.swift`.
- `Peak/Supporting/YearInReviewCalculator.swift` + `Peak/Views/More/YearInReviewView.swift` — on-demand recap, exported as a branded image by `RecapShareCard` through the same off-main decode + `ImageRenderer` pipeline as `SessionShareCard`.
- `Peak/Supporting/MonthlyGoalCalculator.swift` — a monthly target in sessions *or* hours, stored in `@AppStorage`, **opt-in and off by default** (a zero target hides the ring). Goals get top billing over streaks deliberately: surfing is condition-gated, and a rigid streak turns a flat week into a failure the surfer could not have prevented.
- First run: `Peak/Views/Onboarding/WelcomeView.swift` behind `@AppStorage("hasSeenWelcome")`, plus `Peak/Supporting/PeakTips.swift` (TipKit). Both are hard-disabled under UI-test, ad-capture, and screenshot modes so existing baselines are untouched.
- Note: the board report's period bands (10 s / 13 s) are deliberately coarser than the Best-Conditions card's (8 s / 11 s) — board choice and session quality do not split at the same thresholds.

**On-Device Insights (optional)**
- `Peak/Supporting/InsightsEngine.swift` is pure Foundation and compiles on iOS 17. It reduces `StatsCalculator` / `GearInsightsCalculator` / `YearInReviewCalculator` output to a small bounded `…Facts` value, builds the prompt, screens what comes back, and renders the plain form. A surfer with ten thousand sessions produces exactly the same prompt size as one with ten; raw session rows never reach the model.
- `Peak/Supporting/FoundationModelsInsights.swift` is the **only** code that touches `SystemLanguageModel`, behind `#if canImport(FoundationModels)` + `if #available(iOS 26, *)`. Guided generation into a `@Generable` type whose every field is prose. Responses are streamed, so a reply that hits its token ceiling still yields its finished prefix.
- **The model contributes language, never fact.** Three independent measures, any one of which would have to fail silently for a wrong number to reach the screen: (1) the prompt contains no numerals at all — facts are handed over as qualitative descriptors; (2) the `@Generable` schema has no numeric field; (3) `InsightsSanitizer` discards any generated text containing a digit, number word, star or percent sign, or a capitalised word absent from an allow-list built from the facts. A rejected field is dropped rather than repaired; a rejected headline drops the whole draft back to plain figures. The only digits permitted are those inside names the surfer typed themselves.
- Every figure on screen is interpolated by the `plain…` properties in `InsightsEngine`, which are *also* the non-AI fallback — so the surfaces render identically-truthful content with or without Apple Intelligence.
- **The model boundary is the `InsightsGenerating` protocol.** CI never runs a model: every test drives the pipeline through that injected seam.
- Every unavailability reason (ineligible device, Apple Intelligence off, model downloading, iOS below 26) is silent. Peak never tells a surfer about a feature their phone cannot run.
- `FoundationModelsInsightsGenerator.draft` is `@concurrent`, not merely `nonisolated`: under `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor` a nonisolated async function inherits its caller's actor, and inference takes seconds. Figures render synchronously; prose arrives later and only ever replaces prose.

**Widget Extension, App Intents & Live Activity**
- Extension target: `PeakWidgets/` — `StreakWidget` and `LastSessionWidget` (small/medium plus accessory families), `StartSessionControl` (Control Center, iOS 18+), and `SessionLiveActivity`.
- **The App-Group boundary is the whole design.** The widget never opens the SwiftData store. The app derives a small `PeakWidgetSnapshot` (`Peak/WidgetSnapshot.swift`) and `WidgetSnapshotWriter` publishes it to the App Group container `group.com.designprism.peak`; the extension only ever reads that value. Consequences: no store migration, no risk to the library, and no schema version cost for anything the widget shows.
- Snapshot refresh points: launch, every session save/delete, backup restore, and each foreground return, each followed by `WidgetCenter.reloadAllTimelines()`. Timeline reloads are skipped under UI test.
- **In-progress session state also lives in App-Group `UserDefaults`, not SwiftData** (`Peak/ActiveSession.swift`). It survives relaunch, the extension can read it, and "session in progress" costs no schema version. `ActiveSessionState` is compiled into both targets, so everything in it is explicitly `nonisolated` — the two targets do not share a default actor isolation setting. The real `SurfSession` is created only when the surfer ends the session and saves the prefilled editor.
- Live Activity: `Peak/SessionActivityController.swift` + `Peak/SessionActivityIntents.swift`. The elapsed timer is drawn with `Text(timerInterval:)`, so Peak sends no push updates and holds no push token. ActivityKit is disabled under UI tests so the suite never depends on Live Activity chrome.
- App Intents: `Peak/Supporting/AppIntentsEntities.swift` (`SurfSessionEntity`, `SpotEntity` — stable identifiers and display representations, which is what puts the logbook in the Spotlight semantic index), `AppIntents+Peak.swift` (Log / Start / End / Last Session / Sessions This Month, with Siri phrases), `SessionIntentQueries.swift`, `QuickLogIntents.swift`.
- Ending a session opens `SessionEditorView(mode: .new)` with a prefilled draft: start time, duration rounded to the nearest 5 minutes, and the spot.
- **Deployment gate:** the App Group must be registered in the Developer portal before any device build or archive of these targets. See `RELEASE_PLAYBOOK.md`.

**Spots, Buddies & Quiver**
- Spots and Buddies are reached from the More tab; Quiver is a top-level tab
- Spot editor (optional pin location): `Peak/Views/Library/SpotEditorView.swift`
- Quiver (gear): `Peak/Views/Quiver/QuiverView.swift` and related gear views
- Spots map + "Use My Location": `Peak/Views/Spots/SpotsMapView.swift`, `Peak/Supporting/LocationService.swift`

**Export / Import**
- Settings UI: `Peak/Views/More/SettingsView.swift`
- Export/import logic: `Peak/Supporting/ExportFormat.swift`
- JSON export, CSV export, and JSON import (merge or replace)

**Privacy & Networking**
- Privacy policy: `PRIVACY.md`, in-app: `Peak/Resources/Privacy.md`
- Network calls are made only when the user triggers auto-fill, taps "Check conditions", or opts into the Best Window Today auto-refresh toggle. The endpoints are Open-Meteo and NOAA CO-OPS; nothing else is contacted.
- Widgets, App Intents, and the Live Activity render local data only.
- Language-model inference is on-device and adds no network call. Route analysis is on-device and persists no coordinates.
- HealthKit reads are behind the `healthSyncEnabled` opt-in.
- No analytics, accounts, or background sync
- Keep `Peak/PrivacyInfo.xcprivacy` accurate when anything privacy-relevant changes

**Testing**
- Unit tests: `PeakTests/*` — **510 tests** on `main`
- UI layout tests: `PeakUITests/*` — **54 tests** on `main`
- Standard commands: `./scripts/build-sim.sh`, `./scripts/test.sh`
- **Run one `xcodebuild` at a time.** The simulator is a single shared resource; concurrent runs produce false failures. See `AGENTS.md`.
- Only the `Peak` folder is a file-system-synchronized group. New files in `PeakTests`, `PeakUITests`, or `PeakWidgets` need explicit `project.pbxproj` registration before the build can see them.

**Not covered here**
- The `3.1` watchOS companion (`PeakWatch`, `PeakWatchWidgets`, `PeakShared`, `WatchSessionBridge`) lives on `feature/3.1-watchos` and is **not merged**. It is deliberately excluded from this document until it passes real-device ocean testing and lands on `main`.
