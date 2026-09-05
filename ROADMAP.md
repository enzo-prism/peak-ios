# Peak roadmap

## Current priority, September 4, 2026

3.2 is public; 3.3 is waiting for review with manual release. Prioritize a tested reliability follow-up: reconcile release fixes into main, preserve session identity and relationships across migrations and restore, cover production iPad navigation, and verify Spotlight/recovery behavior. The submitted 3.3 binary is separate from subsequent source changes.

Run the [5–10-surfer pilot and device acceptance protocol](docs/SURFER_VALIDATION.md) before committing to another large feature train. Favor observed repeat-log friction and useful board insights. Keep the Watch companion behind five real surf recordings and held-out analyzer checks. Apple analytics reporting is configured; it does not measure actual surf opportunities or log completion.

The historical plan below records the original implementation sequence, not current release status. Version numbers 2.7–3.2 are historical; select any future release number from live ASC state. Source and test evidence in RELEASE_PLAYBOOK.md supersede the old counts and branch pointers below.

## Historical feature plan

Implementation plan for the five-pillar improvement program: (1) ecosystem unlock (widgets + App Intents + Live Activity), (2) wave stats via HealthKit route mining → watchOS app, (3) "Best Window Today" + tide, (4) quiver analytics, (5) memory layer + first-run + on-device AI insights.

Grounded in: repo state at `5e750a0` (2.6 (1), main), the 2026-07-20 three-agent research pass (codebase audit, surf-market teardown, Apple-API verification vs WWDC25/26), and AGENTS.md product principles (privacy-first, offline-first, no backends, no social, gear is the hero feature).

**Standing rules for every release below**

- Version trains: always strictly newer than every existing ASC train. TestFlight flow per RELEASE_PLAYBOOK + `.asc/` (archive → export → `asc builds upload` → poll VALID → `asc builds update --latest --uses-non-exempt-encryption=false`).
- Schema changes: never edit live models without a new versioned schema. Freeze the outgoing HEAD schema as an inline snapshot **in the same change** as a real field delta (SwiftData rejects duplicate shape checksums — a no-op version bump is impossible). Update `ModelMigrationTests.testHeadSchemaShapeIsPinned` expectations deliberately, and add a migration test per new stage.
- New **unit-test** files must be added to the pbxproj by hand (PeakTests is not a synchronized group); only the Peak app group auto-includes; PeakUITests and PeakWidgets files also need explicit project registration.
- Off-main work needs `@concurrent` (project sets `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor`; `nonisolated` sync funcs still run on main).
- `.accessibilityIdentifier` goes on the ScrollView (outside), never on a GlassContainer inside scroll content (id-clobbering bug).
- New capabilities/bundle IDs: pre-register via `asc bundle-ids …` **before** archiving (`-allowProvisioningUpdates` cannot register portal resources with the API key).
- New iOS 18/26/27 API is availability-gated in the existing `#if compiler` + `if #available` pattern; deployment target stays iOS 17 unless noted.
- Networking stays explicit-user-action-only unless a release note below says otherwise (privacy stance).

---

## Phase 0 — Pre-flight hygiene (no release, ~1 day)

1. **Perf branches**: rebase `perf/history-query-memoization` (+8), `perf/image-decode-reduce-motion` (+3), `perf/quick-wins` (+2) onto main; land what still applies (2.5 already shipped some of this — expect partial overlap), close the rest. Close/delete stale branches: `feature/streamlined-log-session`, `feature/detail-redesign`, `wt/*`, `codex/*` remotes.
2. **Repo weight**: add `artifacts/`, `.asc/artifacts/`, `marketing/` to `.gitignore`; `git rm -r --cached artifacts/`. (History rewrite with `git filter-repo` to reclaim the ~199 MB pack is a separate, destructive decision — do not run without an explicit go.)
3. **Fixes**: correct `SettingsView` support email (`support@prism.app` — verify intended address, likely design-prism.com domain); update README/RELEASE_PLAYBOOK version drift; tag `v2.5-build1`, `v2.6-build1`.
4. **Baseline**: all unit + UI tests green on Xcode 26.6 before any 2.7 work starts.

---

## Release 2.7 — Ecosystem Unlock (widgets · App Intents · Live Activity)

*Everything here shares one widget extension and one App Group. Highest value-per-hour on the board; most code exists.*

### 0. MANUAL STEP (Enzo, ~10 min, blocks everything)
Register App Group `group.com.designprism.peak` in the Developer portal (Identifiers → App Groups) or Xcode GUI, team `L49MKXGVM4`, and associate it with `com.designprism.peak` (portal id `4C2TR3BVLB`) and the widget bundle id. The asc API can enable the APP_GROUPS capability but **cannot create the group** — this is the only human-gated task in the release.

### 1. Land the widget branch
- Rebase `feature/2.5-widgets` (2 commits: `PeakWidgets/` extension — streak + last-session widgets, `WidgetSnapshotWriter`, deep links, `onOpenURL`) onto main. Reconcile with 2.6's polish (branch predates it).
- Keep the **snapshot-via-App-Group** architecture (writer serializes `PeakWidgetSnapshot` to the shared container). Do **not** relocate the main SwiftData store into the App Group — no store migration, no data-invisibility risk.
- Widget target `DEVELOPMENT_TEAM = L49MKXGVM4` (a stale script once hardcoded SQ949Q468V → "No Account for Team").
- Snapshot refresh points: session save/delete, backup restore, app-foreground. `WidgetCenter.reloadAllTimelines()` after each write.

### 2. App Intents, done properly (new: `Peak/Supporting/AppIntentsEntities.swift` + `AppIntents+Peak.swift`)
WWDC26 deprecated SiriKit; App Intents entities are now the only path into LLM-Siri and the Spotlight semantic index. Build:
- `SurfSessionEntity`, `SpotEntity` (`AppEntity` + `EntityQuery`, display representations from spot/date/rating; stable IDs = model `createdAt`-derived keys).
- Intents: keep `LogSessionIntent` (opens sheet); add `StartSessionIntent` (starts the live session, §3), `LastSessionIntent` ("When did I last surf?" → dialog + snippet), `SessionsThisMonthIntent`.
- `PeakAppShortcuts` phrases for all four; Action-button assignable automatically.
- **Control Center control** (iOS 18+, in the widget extension): `ControlWidgetButton` → `StartSessionIntent`.
- iOS 26 availability-gated: interactive snippet for `LastSessionIntent` results.

### 3. Live Activity — "Session in progress"
Peak currently only logs after the fact; this adds the minimal in-progress concept the Live Activity (and later the watch app) needs.
- State: a small `ActiveSessionState` (spot key, start date) persisted in **App-Group UserDefaults** (not SwiftData — survives relaunch, readable by the extension, no schema change).
- Entry points: "Start Session" button on `LogView` hero, `StartSessionIntent` (Action button / Control Center / Siri).
- `PeakSessionActivityAttributes` in the widget extension: elapsed timer (`Text(timerInterval:)` — no push updates needed), spot name, Liquid-Glass-styled Lock Screen card + Dynamic Island compact/expanded.
- End session (from activity button via intent, or in-app) → opens `SessionEditorView(mode:.new)` with `SessionDraft` prefilled: start time, computed duration (rounded to 5-min steps, clamped 5–480), spot preselected → user adds rating/notes and saves as normal.
- Free win: on watchOS 11+ the Live Activity auto-appears in the Watch **Smart Stack** — wrist presence with zero watchOS code, and the designated hand-off surface for the 3.1 watch app.

### 4. Tests & ship
- Unit: snapshot derivation (streak math vs `StatsCalculator` parity), draft-prefill from `ActiveSessionState`, intent query logic. (pbxproj add!)
- UI: start → end → editor-prefilled flow (gate ActivityKit behind `TestingDefaults` so simulator UI tests don't depend on Live Activity chrome); widget deep-link `onOpenURL` → new-session sheet.
- Ship 2.7 (1). App Review note: widgets/Live Activity render only local data.

**Acceptance**: both widgets installable and updating; Action button + Control Center start a session; Siri answers "when did I last surf" on iOS 26; session timer visible on Lock Screen, Dynamic Island, and paired-Watch Smart Stack; all existing tests green.

**Effort**: ~3–5 days after the App Group exists.

---

## Release 2.8 — Tide + "Best Window Today"

*Answers the surfer's daily question — "when today?" — privately, from the user's own history. Not a forecast app; Surfline/Windguru own 16-day charts.*

### 1. Schema V9 (real delta → freeze V8 alongside it)
Add to `SurfSession`: `seaLevelHeightM: Double?`, `tideTrend: String?` (raw enum: rising/falling/high/low). Lightweight additive migration V8→V9; update the shape-pin guard test; new migration test.

### 2. Tide in the conditions snapshot (`SurfConditionsService.swift`)
- Add `sea_level_height_msl` to the existing marine call; compute trend from the hourly series around the session window. Show in editor auto-fill summary + detail Surf report (`SurfConditionsFormatter`).
- Caveat handled in copy: Open-Meteo sea level is model-derived, MSL-referenced — good for "rising/falling, roughly when's high", not chart-datum precision.
- **US spots, optional precision**: new `TideService` → NOAA CO-OPS (`api.tidesandcurrents.noaa.gov`, free, no key). Nearest-station lookup once per spot (cache station id on the Spot via V9 field `tideStationId: String?` — include in the same V9 delta). Non-US spots silently use the Open-Meteo curve.

### 3. "Best Window Today" card (new `Peak/Views/Today/` + `Supporting/WindowScorer.swift`)
- Card at top of Log tab for the user's favorite spots (top-N by session count with coords). **Explicit refresh** ("Check conditions") to preserve the no-passive-networking stance; a Settings toggle "Refresh automatically when I open Peak" opts into on-appear fetch.
- Fetch next-24 h hourly marine + wind + sea level; `WindowScorer` (stateless enum, fully unit-tested) scores each hour by **similarity to the user's own top-rated sessions at that spot** — nearest-neighbor over stored per-session conditions (swell height/period/direction, wind speed/direction, tide trend). No coastline-orientation guessing; the user's history *is* the spot model.
- Output: "Best window today: 6–9 am — 1.2 m @ 12 s, light wind, dropping tide. Similar to your 5★ session on Mar 12" (tap → that session). Honest empty state below ~3 rated sessions at a spot ("log a few more sessions here and Peak will learn what works").
- Quiver hook (lands fully in 2.9): "conditions favor your fish."

### 4. Tests & ship
Unit: WindowScorer fixtures (clear winner, no-data, flat-spell, tie), tide-trend derivation, NOAA response parsing + station caching, V9 migration. UI: mocked conditions scenario renders the card (extend `UITESTS_SURF_CONDITIONS_SCENARIO`). Ship 2.8 (1).

**Acceptance**: auto-fill stores tide; detail shows it; Today card produces a defensible window for a spot with ≥3 rated sessions; zero network calls without explicit action or opt-in.

**Effort**: ~4–6 days.

---

## Release 2.9 — Quiver Analytics · Memory Layer · First-Run

### 1. Board Report (gear is the AGENTS.md hero feature; all data already captured)
- `StatsCalculator` additions: per-gear aggregates — sessions, avg rating overall and bucketed by wave-height band and swell-period band (short <10 s / mid / long ≥13 s); minimum n≥3 per bucket before showing a number (noise guard, show "not enough data yet" otherwise).
- Surfaces: `GearInsightsCard` in Stats; a per-board report in Quiver gear detail ("Your fish averages 4.2★ in short-period waist-high; your step-up 4.5★ on 12 s+ swell"); Best-Window card gains "favors your <board>" line when a bucket match exists.

### 2. Memory layer
- `OnThisDayProvider` (stateless enum): sessions from prior years within a ±3-day window → card on Log tab (photo thumbnail, spot, rating; tap → detail). Pure query, no schema change.
- **Year in Review**: on-demand view (More + a December Log-tab card): sessions, hours, top spot, best month, longest streak, wave-height distribution, media highlights grid; exports via a new `RecapShareCard` (reuse `SessionShareCard` rendering pipeline).
- **Flexible goals over hard streaks** (habit research: condition-gated sports punish rigid streaks): monthly goal in sessions *or* hours (`@AppStorage`), progress ring on Stats next to the heatmap; streaks stay but goals get top billing.

### 3. First-run (the audit's biggest UX hole: cold start drops into an empty Log tab)
- 3-screen welcome behind `@AppStorage("hasSeenWelcome")`: what Peak is → privacy promise (on-device, no accounts, no tracking) → "Log your first session" CTA into the editor. Liquid-Glass styled, Reduce-Motion aware.
- TipKit tip on the Log CTA (deferred from 2.6) + one on Auto-fill Conditions after the first manual save.
- `TestingDefaults.isUITest` (and ad/screenshot modes) skip the welcome so all existing UI-test baselines are untouched; add one new UI test that runs the welcome explicitly.

### 4. Tests & ship
Unit: gear-bucket aggregates (incl. n<3 suppression), on-this-day windowing (year boundaries, leap day), goal progress. UI: welcome flow, Quiver report rendering. Ship 2.9 (1).

**Acceptance**: a user with 20+ logged sessions across 2+ boards sees a genuinely informative Board Report; first launch is guided; on-this-day resurfaces real memories; goals render sanely at 0 sessions.

**Effort**: ~5–7 days.

---

## Release 3.0 — Wave Stats (HealthKit route mining) — the killer feature, no watch app required

*Every Apple Watch surf workout (native Workout app, Dawn Patrol, anything) stores its GPS route in HealthKit. Peak already imports HR/calories from these workouts; this extends the import to derive wave count / top speed / longest ride / paddle distance — on-device, private, editable.*

### 1. Route access (`HealthKitService.swift`)
Add `HKSeriesType.workoutRoute()` to the read set; fetch `HKWorkoutRoute` + `CLLocation` stream for linked/importable workouts. All reads stay behind the existing `healthSyncEnabled` opt-in; quiet no-ops when unauthorized.

### 2. `WaveAnalyzer` (new stateless enum, `Peak/Supporting/`)
- Input `[CLLocation]` → smoothed speed series (accuracy-filtered: drop points with `horizontalAccuracy > ~20 m`; GPS only samples when the wrist clears the water — gaps are normal, bridge ≤5 s).
- Wave = sustained speed ≥ ~8 km/h for ≥3 s with consistent shoreward heading, preceded by paddle-speed segment; reject isolated single-point spikes (multipath). Tunable constants in one struct.
- Outputs: `waveCount`, `topSpeedKph`, `longestRideSeconds`, `longestRideMeters`, `paddleDistanceMeters`, `totalDistanceMeters`, per-wave segments (for the map).
- **Testing without an ocean**: fixture-driven — synthetic routes (clean, noisy, gappy) + at least 2 real recorded sessions exported to JSON (record with the native Workout app on Enzo's watch; ship a debug-only route→JSON exporter). CI never touches HealthKit.

### 3. Schema V10 + surfacing
- `SurfSession` adds: `waveCount: Int?`, `topSpeedKph`, `longestRideSeconds`, `longestRideMeters`, `paddleDistanceMeters` (Double?), `waveStatsSource: String?` (auto/edited/manual). Freeze V9, shape-pin update, migration test.
- Editor: "Wave stats" rows in Details — every value editable; source flips to `edited`. Manual entry allowed with no workout at all (`manual`).
- Detail: wave-stat tags in the hero next to duration; **microcopy everywhere: "estimates — tap to correct"** (competitors' #1 complaint is detection-accuracy rage; never present these as ground truth).
- Stats: PR row (most waves in a session, fastest wave, longest ride) + waves-per-session trend.
- `HealthImportView`: shows derived estimates as a preview before import.
- Widget/share card: wave count joins the last-session snapshot.

### 4. Stretch: session map replay — **shipped in 3.3 (unreleased on `main`)**
`SessionRouteMapView` in detail — MapKit polyline of the route with wave segments highlighted. Route is fetched live from HealthKit by workout UUID (`linkedWorkoutID`); coordinates are never persisted. iPhone-only; watchOS still waits on ocean testing.

**Acceptance**: importing a real surf workout yields wave stats within "plausibly right" of a manual count on the two recorded fixture sessions; every value correctable in ≤2 taps; sessions without workouts unaffected.

**Effort**: ~6–9 days + real-session fixture recording.

---

## Release 3.1 — watchOS app MVP

*Converts Peak from after-the-fact logbook to tracker. The 3.0 analyzer means the watch app gets wave stats "for free" — the watch just produces a normal HealthKit workout with a route.*

1. **Provisioning first** (the 2.5 lesson): create watch bundle id via `asc bundle-ids create` (`com.designprism.peak.watchkitapp`), enable HealthKit + App Group capabilities via asc, **before** any archive. Watch target team `L49MKXGVM4`.
2. **MVP scope** (deliberately no on-watch wave detection): `HKWorkoutSession` + `HKLiveWorkoutBuilder`, `.surfingSports` — start/pause/end on watch; auto Water Lock (comes free with water activity types); live elapsed/HR/distance; save to HealthKit on end. HealthKit syncs the workout + route to iPhone automatically → existing import + `WaveAnalyzer` produce the stats. Fully independent of the phone (phone stays on the beach).
3. **Mirrored session → Live Activity**: `startMirroringToCompanionDevice()` hands off into the 2.7 Live Activity (10 s launch window). Known ~5% silent data-channel failure → final-session-data fallback via WatchConnectivity `transferFile`; the HealthKit save is the source of truth either way.
4. **Post-session nudge (iPhone side shipped in 3.3):** when a new surf workout appears, the Log tab offers one-tap import (`UnloggedWorkoutCard`). An `HKObserverQuery` plus optional local notify (`notifyUnloggedSurfWorkouts`, off by default) keep the card fresh. Spot is guessed only from a nearby pinned break via `SpotProximity` (never fabricated). The watchOS companion that *creates* the workout is still gated on ocean testing.
5. **Ocean-testing protocol** (the real work): TestFlight to Enzo's watch; ≥5 real sessions; compare analyzer output vs manual wave counts; tune `WaveAnalyzer` constants; only then widen the TestFlight group.
6. watchOS 26 Smart Stack relevance (`RelevanceKit`, POI category *beach*) on the watch widget: "Log your surf" surfaces when standing on the sand.

**Acceptance**: full phone-free session → workout lands in Peak with wave stats and a one-tap log; Water Lock engages automatically; mirror failure never loses a session.

**Effort**: ~2 weeks + ocean-testing calendar time. New App Store screenshots (watch) at ship.

---

## Release 3.2 — On-device AI insights (Foundation Models) — parallel/opportunistic

1. Gate: `SystemLanguageModel.availability` — feature invisible on non-Apple-Intelligence devices (iPhone 15 Pro+/AI enabled) and below iOS 26. Everything it renders must also exist in plain-stats form (graceful absence, never a broken tab).
2. `InsightsEngine` (`Peak/Supporting/`): feeds **pre-aggregated** `StatsCalculator` output (never raw sessions — ~4k-token context covers input *and* output) into `@Generable` guided generation: `MonthlyRecap { headline, highlights: [String] (max 3), suggestion }`, `SeasonInsight`, year-in-review narrative for the 2.9 recap. Typed output, no JSON parsing; handle `finishReason == .length`.
3. Surfaces: monthly recap card on Stats ("July: 9 sessions, 11 h — your best month since March. Your fish outperformed everything in the short-period windswell."), narrative paragraph in Year in Review. Marketing line writes itself: *insights that never leave your phone*.
4. Tests: prompt-builder + aggregation fixtures in CI (model itself can't run in CI); manual eval checklist of ~10 seeded logbooks (empty, sparse, one-spot, multi-board) checked for hallucinated claims before ship.
5. iOS 27 (fall 2026) follow-ups, availability-gated: bigger on-device model, `LanguageModel` any-provider protocol, App Intents `RelevantEntities`/`SyncableEntity` adoption.

**Effort**: ~4–5 days + eval passes.

---

## Release 3.3 — Historical system-integration plan (August 20 snapshot)

Apple-platform completeness on top of the in-review 3.2 binary. **No schema change. Does not replace 3.2 in App Review.** `prod` fast-forwards to the same SHA as `main` as a git snapshot. App Store production remains App Store Connect (`3.2` in review).

Shipped on `main` / `prod`:

- iPad: sidebar-adaptable tabs, Search tab role, Library sidebar, split views on History / Quiver / Spots (regular width; off under UI tests).
- Spotlight / App Intents: `IndexedEntity` + Open intents + in-app search results; Last Session snippet; named index `PeakLogbook`.
- Widgets: Last Session opens that session; Start Session on medium / extraLarge; configurable spot from snapshot glances; extraLarge family.
- Health: unlogged-workout card, observer + optional notify, session route map. GPS never persisted.
- Performance: `#Predicate` library-detail fetches, Search History mount-on-select, widget skip, one-pass calculators, ImageIO thumbs.
- Library / Search UX: session-style heroes, progressive disclosure, Open in Maps, dedicated Search prompt (not a second History).

Does **not** include watchOS, CloudKit, or wiring `TideService` into auto-fill. Cut the store train on a Mac after `./scripts/test.sh` (expect 546 unit / 54 UI). Keep `MARKETING_VERSION` at 3.2 until that Mac cut; landing on `main` / `prod` is not a store submit.

---

## Explicitly out of scope (revisit after 3.1)

- **CloudKit/SwiftData sync**: requires stripping `.unique` keys + all-optional fields (major migration), dedup logic, append-only production schema, and video-as-loose-files rework. Medium user value for a mostly-single-device app. Reconsider when iPad usage warrants it.
- Social features, accounts, backends, third-party SDKs (AGENTS.md hard scope-outs).
- On-watch live wave detection (fast-follow after 3.1 ocean data exists).
- `git filter-repo` history rewrite (destructive; separate decision).

## Sequencing summary

| Release | Theme | Effort | Hard gate |
|---|---|---|---|
| Phase 0 | Hygiene | ~1 d | — |
| 2.7 | Widgets + App Intents + Live Activity | 3–5 d | **App Group registration (manual, Enzo)** |
| 2.8 | Tide + Best Window Today | 4–6 d | Schema V9 |
| 2.9 | Quiver analytics + memory + first-run | 5–7 d | — |
| 3.0 | Wave stats from HealthKit routes | 6–9 d | Real-session GPS fixtures; Schema V10 |
| 3.1 | watchOS app MVP | ~2 wk | Physical watch + ocean testing |
| 3.2 | Foundation Models insights | 4–5 d | Apple-Intelligence device |
| 3.3 | Spotlight, iPad, Health loop, widgets, route map, library UX | landed on `main` / `prod` | Mac `./scripts/test.sh` (546/54) before the next store train |

Each release ships independently to TestFlight; nothing later blocks anything earlier. 2.7 → 2.8 → 2.9 are pure iPhone software and could compress into a fast train; 3.0's analyzer is the deliberate de-risking step before committing to the watch target.
