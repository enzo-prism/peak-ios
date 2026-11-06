# Peak Architecture

This document describes the runtime structure, data model, and key flows in Peak. It is intended for contributors and maintainers.

**Overview**
- UI is built in SwiftUI with a tab-based shell.
- Data is stored locally in SwiftData with migration support (currently schema V12).
- Two targets ship in the app: `Peak` and the `PeakWidgets` extension (widgets, Control Center control, Live Activity). They share state through App Group `group.com.designprism.peak` and never through the SwiftData store.
- No backend, accounts, or in-app analytics SDK. Conditions networking is explicit Open-Meteo/NOAA action or an off-by-default forecast refresh opt-in. Optional voice use may download Apple speech assets after explicit recording action; inference remains on-device. User-selected system pickers and Files providers retain their system behavior. See `PRIVACY.md`.
- Deployment target is iOS 17.0. Everything newer — Control Center controls (18), Foundation Models (26), interactive snippets (26) — is availability-gated and degrades to silence, never to a broken surface.

**App Shell & Navigation**
- Entry point: `Peak/PeakApp.swift`
- Tabs and routes: `Peak/ContentView.swift`, coordinated by `Peak/Supporting/PeakNavigationCoordinator.swift`
- Compact tabs: Log, History, Stats, Quiver, More. iOS 18 adds a Search tab (`TabRole.search`) and a Library sidebar (Spots, Buddies, hidden from the compact tab bar) with `.tabViewStyle(.sidebarAdaptable)` on regular width. History, Quiver, and Spots use `NavigationSplitView` on regular width (production navigation remains enabled under UI tests by default; legacy flow tests explicitly set `UITESTS_CLASSIC_NAVIGATION=1`). The Search tab only instantiates `HistoryView` while it is selected — `@Query` on an unused Tab sibling would otherwise fetch the logbook a second time (without media prefetch). Search intents still land on the History tab.
- Styling: `Peak/Supporting/Theme.swift` and `Peak/Supporting/GlassHelpers.swift`
- Deep links: `Peak/WidgetSnapshot.swift` (`PeakDeepLink`) parses `peak://new-session`, `peak://session?id=`, `peak://spot?id=`, `peak://gear?id=`, and `peak://search?q=`. `ContentView.onOpenURL` hands them to the coordinator. Last Session widget taps open **that** session; empty widgets and Streak still use `new-session`.

**Data Model & Storage**
- SwiftData models: `Peak/Models/SurfSession.swift`, `Peak/Models/Spot.swift`, `Peak/Models/Gear.swift`, `Peak/Models/Buddy.swift`, `Peak/Models/SessionMedia.swift`
- Draft/edit state: `Peak/Models/SessionDraft.swift`
- Schema + migrations: `Peak/Supporting/ModelSchema.swift` (see `PeakMigrationPlan`); the live container targets the HEAD versioned schema in `Peak/Supporting/PeakDataStore.swift`
- Storage is local only; UI tests seed in-memory data via `Peak/Supporting/PreviewData.swift`
- **Schema invariant:** every past `PeakSchemaVn` is a *frozen* inline snapshot of the model shape it shipped with; only the HEAD schema (`PeakSchemaV12`, `Schema.Version(1, 11, 0)`) references the live model classes. Editing a live `@Model` field therefore silently redefines the shipped HEAD version — so before changing any field, freeze the current HEAD as the next `Vn` snapshot and add a new live-referencing HEAD carrying the delta plus an appropriate migration stage. Guards in `ModelMigrationTests` enforce this: `testHeadSchemaShapeIsPinned` fails the moment HEAD's field set drifts, `testFrozenV8SnapshotShapeIsPinned` / `testFrozenV9SnapshotShapeIsPinned` fail if a frozen snapshot is ever touched, and `testV7ToV8…` / `testV8ToV9…` / `testV9ToV10MigrationAddsWaveStatFieldsAsNil` each exercise a real on-disk staged migration. Note: SwiftData rejects two identical-shape schemas in one plan ("duplicate version checksums"), so a no-op version bump is invalid — freeze only alongside a genuine shape change.
- **Schema history (recent):**
  - **V9** (`1.8.0`, release 2.8) — `SurfSession.seaLevelHeightM`, `SurfSession.tideTrend`, `Spot.tideStationId`. V8 frozen in the same change.
  - **V10** (`1.9.0`, release 3.0) — `SurfSession.waveCount`, `topSpeedKph`, `longestRideSeconds`, `longestRideMeters`, `paddleDistanceMeters`, `waveStatsSource`, `linkedWorkoutID`. V9 frozen in the same change.
  - Both are additive and `.lightweight`; every new field is optional and migrates in as `nil`. No route coordinates are persisted — only the workout UUID.
- **V11** (`1.10.0`, 3.3): explicit Gear/Buddy inverse collections with a custom V10 migration that preserves relationships by persistent model identity, including duplicate creation timestamps.
- **V12** (`1.11.0`, reliability follow-up): optional persisted `SurfSession.sessionID: UUID?`; new sessions receive UUIDs and custom V11→V12 migration fills missing IDs. V11 is frozen. Creation dates remain timestamps rather than identity. This identity migration is part of the 3.5 baseline; 3.6 changes no model fields.
- Session identity must remain stable across export/import, backup/restore, App Intents and widget links. Legacy timestamp formats require explicit compatibility handling; ambiguous references must not pick an arbitrary session. Cover duplicate timestamps and repeated imports with regression tests and the device protocol in `docs/SURFER_VALIDATION.md`.
- **CloudKit note:** the models are intentionally *not* CloudKit-ready — `Spot`/`Gear`/`Buddy` use `@Attribute(.unique) key`, and several attributes are non-optional without defaults. Adding sync later would be a schema-wide breaking migration (drop uniques, make everything optional/defaulted, dedupe in code), not an additive change. This is a deliberate offline-first trade-off.

**Session Logging Flow**
- Log screen: `Peak/Views/Log/LogView.swift`
- Editor: `Peak/Views/Log/SessionEditorView.swift`
- Session editor writes to `SessionDraft`, then commits to `SurfSession`
- First paint is one focused card (date/time prefilled to now + spot); everything else lives in collapsed disclosure groups (progressive disclosure)
- Required input: a spot (a spot itself only requires a name — location/pin are optional and can be added later)
- Optional inputs: duration, rating, notes, gear, buddies, media, wind/wave (menu pickers), tide, wave stats
- The Log hero also carries **Start Session** beside Log Session, and shows a running timer with End Session while a session is in progress
- The Log tab additionally hosts Best Window Today, the unlogged Watch-surf card (`UnloggedWorkoutCard`, Health sync on only), On This Day, and (in December) Year in Review, so it queries the full session history with spots prefetched — the recents list stays limited to three and is the only Log query that prefetches media
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
- `TideStationCard` is an optional, explicit Best Window action. Find Nearby NOAA Station proposes a station within the service's 120 km cap; Use This Station confirms it and fetches the next 36 hours of high/low predictions. A successful confirmation saves the existing `Spot.tideStationId`; save failure restores its previous value.
- Predictions include station, check time and MLLW datum. They are separate from Open-Meteo MSL session/scorer features. Proximity does not establish break suitability, which the UI explains. Unavailability leaves model conditions usable.

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
- History list: `Peak/Views/History/HistoryView.swift` (split on regular width; Search intents fill this list immediately, skipping debounce). The iOS 18 Search tab keeps the search field always visible (`navigationBarDrawer(displayMode: .always)`) and shows a prompt until the surfer types or filters — it is not a second copy of History.
- Session detail: `Peak/Views/History/SessionDetailView.swift`
- Spot / Gear / Buddy detail: `Peak/Views/Library/*DetailView.swift` — `@Query` uses `SurfSession.sortedByDateDescending(matchingSpotKey:)` (and gear/buddy equivalents) so SQLite returns only related rows. Prefetch is `spot` / `gear` / `buddies` for `SessionRowView`; media stays lazy. Renaming a library item recreates the query (`.id(key)`). Heroes match session detail (large title, combined VoiceOver). Session lists show five recents then a disclosure. A pinned spot offers **Open in Maps**. Destructive actions use `Theme.destructive` and a 44 pt hit target.
- Transient route map: `Peak/Views/History/SessionRouteMapView.swift` — MapKit polyline + wave-segment overlay from `linkedWorkoutID`. Coordinates live only in memory; never written to the store. Display tracks are simplified (`RouteDisplaySimplifier`); analysis still uses the full GPS track.
- Filters for spot, gear, and buddy are applied in History

**Stats & Trends**
- Stats UI: `Peak/Views/Stats/StatsView.swift` and the cards beside it (`GearInsightsCard`, `MonthlyGoalCard`, `MonthlyRecapCard`, `WaveRecordsCard`, `ConsistencyHeatmapCard`, `MonthlyBarsCard`, `SpotMixDonutCard`, `ConditionsInsightsCard`)
- Calculations: `Peak/Supporting/StatsCalculator.swift`, `Peak/Supporting/UsageMetricsCalculator.swift`
- Every calculator is a stateless enum over session rows; derived values are recomputed rather than cached, so they stay correct under session edit and delete. Stats, Quiver, and library lists key that recompute on `SessionQueryStamp` (model ID + `updatedAt`) because SwiftData array identity does not change for in-place edits.

**Wave Stats (HealthKit route mining)**
- Analyzer: `Peak/Supporting/WaveAnalyzer.swift` — turns a gappy, noisy wrist-GPS track into wave count, top speed, ride lengths and paddle distance. Accuracy-gated fixes, a least-squares speed fit de-biased for the fixes' own noise floor, rolling-median spike rejection, hysteresis thresholds with a sustained-evidence rule, distance integrated from speed rather than summed from positions, and a distance-weighted heading-consistency test.
- It is **CoreLocation-free**: the app maps `CLLocation` to the analyzer's `RouteSample` at the `HealthKitService` boundary. That is what lets the whole suite run on synthetic routes with no device, no entitlement and no ocean (`PeakTests/WaveAnalyzerTests.swift`, `PeakTests/WaveRouteGenerator.swift`).
- All tuning constants live in one struct so they can be re-fitted against real recordings. They are physically reasoned, **not yet ocean-validated** — that is a 3.1 gate.
- Route access: `Peak/Supporting/HealthKitService.swift` adds `HKSeriesType.workoutRoute()` to the read set and streams a workout's locations. Behind the existing `healthSyncEnabled` opt-in; a quiet no-op when off, denied, or the workout has no route. An `HKObserverQuery` plus HealthKit background delivery (immediate frequency) refreshes the Log-tab unlogged-workout card; `disableBackgroundDelivery` runs when sync is turned off.
- Spot guess: `Peak/Supporting/SpotProximity.swift` — nearest pinned break within 2.5 km of a **mid-route** valid GPS sample (parking-lot starts and invalid accuracy are skipped). Nil rather than a distant fabrication.
- Surfaces: `Peak/Views/Components/WaveStatsEditor.swift` (all values editable; wave count uses explicit +/- buttons for 44pt targets rather than a `Stepper`), the session-detail hero and route map, `Peak/Views/More/HealthImportView.swift` preview, `Peak/Views/Log/UnloggedWorkoutCard.swift` (one-tap import + optional local notification with a Log action that imports), `Peak/Supporting/WaveStatsCalculator.swift` + `WaveRecordsCard` for personal records, plus the widget snapshot and share card.
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
- Extension target: `PeakWidgets/` — `SurfPlanWidget`, `StreakWidget` and `LastSessionWidget` (small/medium/extra-large plus accessory families), `StartSessionControl` (Control Center, iOS 18+), and `SessionLiveActivity`. Widget configuration types are `nonisolated` (`SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor`).
- **The App-Group boundary is the whole design.** The widget never opens the SwiftData store. The app derives a small `PeakWidgetSnapshot` (`Peak/WidgetSnapshot.swift`) and `WidgetSnapshotWriter` publishes it to the App Group container `group.com.designprism.peak`; the extension only ever reads that value. `spotGlances` on the snapshot lets Last Session pin a frequent spot without SwiftData. Consequences: no store migration, no risk to the library, and no schema version cost for anything the widget shows.
- Snapshot refresh points: launch, session save/delete (via `updatedAt` stamp), backup restore, and each foreground return. `WidgetSnapshotWriter` skips the App Group write and `WidgetCenter.reloadAllTimelines()` when the rendered payload is unchanged (`hasSameWidgetPayload`, ignoring `generatedAt`). Timeline reloads are also skipped under UI test. Spotlight serializes index rebuilds, waits for in-flight writes, and coalesces intermediate snapshots.
- **In-progress session state also lives in App-Group `UserDefaults`, not SwiftData** (`Peak/ActiveSession.swift`). It survives relaunch, the extension can read it, and "session in progress" costs no schema version. `ActiveSessionState` is compiled into both targets, so everything in it is explicitly `nonisolated` — the two targets do not share a default actor isolation setting. The real `SurfSession` is created only when the surfer ends the session and saves the prefilled editor.
- Live Activity: `Peak/SessionActivityController.swift` + `Peak/SessionActivityIntents.swift`. The elapsed timer is drawn with `Text(timerInterval:)`, so Peak sends no push updates and holds no push token. ActivityKit is disabled under UI tests so the suite never depends on Live Activity chrome.
- App Intents: `Peak/Supporting/AppIntentsEntities.swift` (`SurfSessionEntity`, `SpotEntity`, `GearEntity` — `IndexedEntity` on iOS 18, donated via `SpotlightIndexer` to named index `PeakLogbook`), `OpenSessionIntent` / `OpenSpotIntent` / `OpenGearIntent`, `SearchPeakIntent` (`ShowInAppSearchResultsIntent`), `AppIntents+Peak.swift` (Log / Start / End / Last Session / Sessions This Month, with Siri phrases; Last Session returns a snippet), `SessionIntentQueries.swift`, `QuickLogIntents.swift`. On-screen `NSUserActivity` carries `appEntityIdentifier`.
- Ending a session opens `SessionEditorView(mode: .new)` with a prefilled draft: start time, duration rounded to the nearest 5 minutes, and the spot and selected setup, if still present and not archived.
- **Deployment gate:** the App Group is registered; archives still use manual signing. See `RELEASE_PLAYBOOK.md`.

**Spots, Buddies & Quiver**
- Spots and Buddies are reached from the More tab on iPhone; iOS 18 also lists them in the Library sidebar. Quiver is a top-level tab.
- Spot editor (optional pin location): `Peak/Views/Library/SpotEditorView.swift`
- Quiver (gear): `Peak/Views/Quiver/QuiverView.swift` and related gear views
- Spots map + "Use My Location": `Peak/Views/Spots/SpotsMapView.swift`, `Peak/Supporting/LocationService.swift`

**Export / Import**
- Settings UI: `Peak/Views/More/SettingsView.swift`
- Export/import logic: `Peak/Supporting/ExportFormat.swift`
- JSON export, CSV export, and JSON import (merge or replace)

**Privacy & Networking**
- Privacy policy: `PRIVACY.md`, in-app: `Peak/Resources/Privacy.md`
- Conditions calls use Open-Meteo or NOAA CO-OPS on explicit actions or the existing forecast opt-in. Voice asset installation is an explicit Apple system download; Files destinations may be user-selected cloud providers. No Peak backend or cloud inference is introduced.
- Widgets, App Intents, and the Live Activity render local data only.
- Language-model inference is on-device and adds no network call. Route analysis is on-device and persists no coordinates.
- HealthKit reads are behind the `healthSyncEnabled` opt-in. Background workout delivery is the same toggle plus the HealthKit background-delivery entitlement. Local Watch-surf notifications are a second opt-in, off by default. Spotlight donation is on-device (`PeakLogbook`).
- No in-app analytics SDK, accounts, or background sync
- Keep `Peak/PrivacyInfo.xcprivacy` accurate when anything privacy-relevant changes

**Testing**
- Unit tests: `PeakTests/*`; 3.6 discovers 639 cases with Xcode 27, 638 with Xcode 26.6. The additional iOS 27 probe pins cross-context ResultsObserver behavior. See `docs/PEAK_3_6.md` for current acceptance receipts; historical counts are not current evidence.
- UI layout/navigation tests: `PeakUITests/*`. Record the executed test count and simulator/device for each candidate; historical counts are not an acceptance result.
- Standard commands: `./scripts/build-sim.sh`, `./scripts/test.sh`
- **Run one `xcodebuild` at a time.** The simulator is a single shared resource; concurrent runs produce false failures. See `AGENTS.md`.
- Only the `Peak` folder is a file-system-synchronized group. New files in `PeakTests`, `PeakUITests`, or `PeakWidgets` need explicit `project.pbxproj` registration before the build can see them.

**3.6 implementation boundaries**
- `SessionDraftStore` persists an unfinished new session outside SwiftData with atomic index writes, protected recovery files, media identities and owned video copies. A debounced save and lifecycle flush retain changes; save/discard clears recovery. Recovery video copying runs off the main actor. Reset commits the database deletion before removing media, then clears draft/plan/timer state. Unsaved drafts are excluded from full backups and the UI says to save them first.
- `VoiceLogRecorder` uses iOS 26 `SpeechAnalyzer`/`SpeechTranscriber`, optional microphone permission and Apple speech assets, with no server fallback. Audio is limited to two minutes, ends on backgrounding and is deleted after use or on the next launch after an interruption. `VoiceLogParser` resolves only known names and explicit duration/rating; ambiguous or negated fields abstain. Review applies to the draft, never directly to the store.
- `QuiverAdvisor` compares rated single-board sessions at one spot with optional logged size/period filters. At least three samples per board are required; variability and separation gate any preference. Sources stay visible. It is observational evidence, not a causal board recommendation.
- `SurfPlanStore` retains a cached forecast window and setup in defaults, publishes a widget glance and refuses expired/future-invalid plans. Expiry is the end time or six hours after checking. Logging copies setup only. `StartSurfWithSetupIntent` validates current entities and preserves an already-active timer. The widget reads only App Group snapshots and active state; the app resolves saved IDs later.
- `LogbookQuery` implements bounded exact counts, board usage and record searches; unsupported constraints abstain instead of silently counting a subset. `SemanticLogbookSearch` is a separate iOS 27 `SpotlightSearchTool` path guarded by module availability and model eligibility. It returns live indexed source IDs only; all model prose/numbers are discarded. A timeout and cancellation bound retrieval. No model-derived totals reach UI. Spotlight donation is serialized and chunked, including notes and links.
- `RouteReplay` splits invalid/gapped GPS tracks, uses actual samples for scrubbing and caches replay arrays. Hiding a detected ride affects only the current preview; durable summary corrections go through the existing estimate editor. No new route or segment coordinates are persisted.
- `SurfMemoriesView` groups real saved records by month/spot. On supported iPhones, the Journaling Suggestions picker imports only selected suggestion photos into the review draft. It does not infer session facts or auto-import workouts.
- Full backups now use framed v2 metadata/media/checksum records. Video bytes stream in 64 KiB chunks; strict length/name/count/hash validation precedes a staged restore. Legacy JSON/base64 backups remain readable. A lightweight Files document picker exports the verified URL; the destination is read back before recording last-saved-backup freshness. Cancellation and failures remove owned temporary files and retain the original library. JSON/CSV remain metadata-only exports.
- Cross-context edits still retire the library context because ResultsObserver does not refresh model objects already held by another context (pinned by a real SDK probe). Store-free primary session/gear/spot selections survive the root replacement and resolve fresh objects. Ask Peak, Memories and comparison source records open through the canonical History selection. History media relationships are no longer prefetched for the entire logbook. This is correctness-preserving targeted work, not proof of whole-app physical-device performance.

**Watch validation target — not embedded**
- Prepared `PeakWatch`, `PeakWatchWidgets` and `PeakShared` source is retained on `feature/peak-3.6-watch-validation`, outside main. The shipping project has no Watch targets, dependency or embed phase. Recovery, paused elapsed time, serialized route writes, explicit Health save outcomes and retryable handoff are covered by pure tests/build checks.
- The owner explicitly kept the physical Watch release gate pending on November 6. Five real ocean sessions with reference counts, precision/recall, GPS gaps, battery and transfer/recovery evidence are still required. Do not embed/distribute the companion until those pass.
