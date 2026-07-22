# Changelog

All notable changes to Peak (iOS) are documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

Status at a glance:

- **App Store (live):** `2.4`
- **App Store (pending review):** `2.6` — Stats 2.0, Apple Health, full backup, History search, spots map, HIG polish
- **TestFlight / ship binary:** `2.6` build **2** (privacy policy + CI host-store hardening; product features same as build 1)

## [Unreleased] — Audit fixes: conditions, import/restore, accessibility, glass

A four-dimension audit (design/Liquid Glass, accessibility, engineering/SwiftData,
correctness) against the current Apple HIG and iOS 26 SDK docs, then fixed and
regression-tested (+15 tests). No schema changes; the established look is preserved.

### Fixed

- **Wind & swell directions were averaged wrong across due north.** The
  session-window mean for wind/swell/wind-wave *direction* used a linear average,
  so samples straddling 0°/360° (e.g. 350° and 10°) averaged to ~180° — the
  opposite bearing — and were stored as authoritative Open-Meteo data. Now uses a
  circular (vector) mean; scalar readings (height/period/speed/temperature/sea
  level) are unchanged. (`Peak/Supporting/SurfConditionsService.swift`)
- **Merge import/restore could duplicate the entire library.** Session identity
  matched on exact `Date` equality, but a stored `createdAt` keeps sub-millisecond
  precision while the serialized id is millisecond-truncated, so a session never
  matched its own export. Now matched at millisecond precision.
  (`Peak/Supporting/ModelContext+Helpers.swift`, `Peak/Models/SurfSession.swift`)
- **Merge restore duplicated media on already-present sessions.** Manifest media
  was appended unconditionally; existing sessions now have their media replaced
  (stored video files deleted first) instead of doubled on each restore.
  (`Peak/Supporting/BackupManager.swift`)
- **Merge could wipe local edits.** Importing an older export no longer blanks a
  spot's pin/location or gear details filled in locally — optional fields are
  overwritten only when the import actually carries a value.
  (`Peak/Supporting/ExportFormat.swift`)
- **Imported ratings weren't clamped** (a corrupt value could push average rating
  above 5); the **"Spot mix → Other"** bucket now pluralizes ("1 spot"); and top
  spot/gear/buddy ordering is deterministic when both count and name tie.
  (`Peak/Models/SurfSession.swift`, `Peak/Supporting/ExportFormat.swift`,
  `Peak/Supporting/StatsCalculator.swift`)
- **Weekly streak reset to 0 at the start of each new week** and couldn't cross
  the New Year; it now counts the unbroken run up to the most recent surfed week
  across all history. (`Peak/Supporting/StatsCalculator.swift`)
- **CSV export was open to spreadsheet formula injection** (a leading `=`, `+`,
  `-`, or `@`) and mis-split rows on a lone carriage return; both are handled now,
  and legitimate negative numbers (e.g. west longitudes) are preserved.
  (`Peak/Supporting/ExportFormat.swift`)

### Changed

- **Accessibility.** Labeled the add buttons in Quiver/Spots/Buddies; stat and
  metric cards read as one VoiceOver element with their real (non-uppercased)
  titles; session-row count chips read as "2 gear items" rather than a bare
  number; section and chart headings expose the `.isHeader` trait for the rotor;
  the duration slider is labeled; Auto-fill Conditions announces its result;
  selection chips meet the 44×44pt target; and press feedback honors Reduce Motion.
  Contrast tests extended to the `destructive` and `surfGreen` tokens.
- **Liquid Glass / iOS 26.** Scrolling History rows drop the interactive-glass
  shimmer (Apple reserves the interactive material for controls, not scrolling
  content); `.searchable` fields minimize on iOS 26; gear/spot/buddy detail and
  the gear editor use readable content width on iPad; identical session rows share
  press feedback; and the History filter icon uses a symbol-replace transition.

## [Unreleased] — Best Window Today, repaired

Best Window Today shipped in 2.8 and was, for most real logbooks, dead. Not
degraded — dead: for a great many surfers the card did not render at all, and for
most of the rest it could only ever say it did not have enough history. Every
defect below was measured against a real store, not inferred.

### Fixed

- **The card was invisible for spots with no coordinates.** `favouriteSpots`
  required latitude and longitude, so a surfer whose home break was created by
  CSV/JSON import or typed by name — `ModelContext.upsertSpot(named:)` never sets
  a coordinate — had zero favourite spots and the card rendered an empty view
  with no explanation. Measured: 80 fully auto-filled sessions at a name-only
  spot produced nothing on screen. The card now appears for the most-logged spot
  whether or not the app can place it.
  (`Peak/Supporting/TodayWindowService.swift`)
- **The editor's Wind and Wave pickers counted for nothing.** `SurfSession`
  stores `windCondition` / `waveHeight` as enums entirely separate from the
  numeric `windSpeedKph` / `waveHeightMeters`, and only the numeric pair ever
  reached the scorer. A surfer who filled in both pickers on every session had a
  logbook the model discarded wholesale — `CleanSession.init?` rejects anything
  with fewer than two observed features. Measured on 30 rated picker-only
  sessions against the reference forecast day: **max confidence 0.0000 before,
  0.1927 after**, and the predicted rating went from flat on the 2.5 neutral
  prior (spread 0.00) to a 2.36-star spread across the day. That is a usable
  model where there was none; it is still below the 0.25 recommendation gate, so
  such a logbook now gets the conditions readout rather than a fabricated window.
  Each picker band supplies a representative number **only where the numeric
  field is nil** — never overwriting a real reading.
  (`Peak/Supporting/ManualConditionEstimate.swift`)
- **"Best window today" could be tomorrow.** The card scored a rolling 24 hours
  from now and printed a bare time range, so at 6 pm it rendered tomorrow's dawn
  as "5:00 AM - 10:00 AM" under the heading "Best window today". Scoring is now
  restricted to the remainder of the local calendar day; when too little of today
  is left to be worth planning, it plans tomorrow and says so, in both the
  heading ("Best window tomorrow") and the label ("Tomorrow 5:00 - 10:00 AM").
- **Switching spots mid-fetch showed the wrong break's answer.** The in-flight
  task wrote its result unconditionally, so a slow fetch landed under whichever
  spot was selected when it finished — cited session and all. Results now carry
  the spot they were computed for and are rejected if it no longer matches; the
  task is cancelled on switch, and the concurrency guard no longer depends on
  view state that the switch itself resets.
- **The card could confidently recommend the middle of the night.** Once the
  evening fallback started planning tomorrow, tomorrow's 00:00-04:00 became
  ordinary candidates — and a glassy, windless 3 am with a nice tide scores
  *extremely* well, because the scorer has no concept of darkness. A card whose
  entire job is to be trustworthy was one dawn-planning session away from telling
  a surfer to paddle out at 2 am. Windows are now restricted to daylight, taken
  from `daily=sunrise,sunset` on the Open-Meteo forecast request the wind
  readings already use — no second service and no extra round trip. Not a
  hardcoded clock range: "the middle of the night" means something different in
  Bali in March and in Scotland in December. Not a hard sunrise/sunset cut
  either, because surfers legitimately surf outside it — the margin is **sunrise
  − 45 min to sunset + 30 min**, deliberately asymmetric because dawn light is
  arriving (an early start is a plan) while dusk light is leaving (a late start
  is how you get caught out). Both constants and the full reasoning live in one
  place, `TodayWindowService.preSunriseMargin`. If sunrise and sunset are
  unavailable for any reason — an older response shape, a wind request that
  failed while marine succeeded, a polar day the provider cannot compute — the
  day is scored unfiltered exactly as before, because showing nothing is worse
  than showing an unfiltered day.
  (`Peak/Supporting/TodayWindowService.swift`,
  `Peak/Supporting/SurfConditionsService.swift`)
- **At dusk the card now answers with tomorrow instead of with nothing.** A
  consequence of the above: at 9 pm there is technically time left in the day and
  none of it is surfable, which used to leave the card blaming the surfer's
  logbook for the sun having set. The forecast request already reaches into the
  following day, so the answer rolls forward and the heading and label both say
  "tomorrow".
- **Every request that reached outside today was failing at the provider.**
  Open-Meteo rejects `past_days` and `forecast_days` outright when a request also
  carries an explicit range — "Parameter 'forecast_days' is mutually exclusive
  with 'start_date' and 'end_date'", HTTP 400, no data — and Peak's
  `start_hour`/`end_hour` count as one. Peak sent both together. That meant
  auto-filling conditions for any session **not logged the same day** failed, the
  new "Fill in past conditions" action would have failed on every single session,
  and the Best Window fetch — a span from now that always crosses midnight —
  failed every single time. The hours already bound the range on their own, and
  on their own they serve the provider's full archive and forecast horizon, so
  the day counts are gone. (`Peak/Supporting/SurfConditionsService.swift`)
- **A stale fetch could strand the card on its loading spinner.** The favourite
  spots are derived from the logbook, so deleting the last session at the
  selected break re-picks the selection *without* going through the spot-switch
  path that cancels in flight work. The task then returned early without handing
  back its slot, leaving `state` on `.loading` and the only button disabled —
  permanently, for the rest of the session. The same shape in the backfill
  abandoned the run between a write and its save. Both now release the slot on
  every path except cancellation, which is the one case where it belongs to
  somebody else.
- **The empty-state copy was actively misleading.** "Log a few more rated
  sessions and Peak will learn what works here" was false: plain sessions
  contributed nothing at all, so following it changed nothing. The copy now names
  what is actually missing — conditions, or rating spread — and points at the
  control that supplies it.

### Added

- **Automatic coordinates from the bundled break catalog.** A saved spot with no
  coordinate is matched by exact normalised name against the 257 breaks in
  `SurfBreaks.json` and repaired permanently, which also makes session auto-fill
  start working for it. Only on an unambiguous single match — a near miss, a
  substring, or two catalog breaks sharing a name all decline, because writing a
  coordinate decides which patch of ocean gets reported on. A spot that already
  carries *either* half of a coordinate is never touched: `restore` copies
  latitude and longitude across independently, so a truncated import can leave
  one set, and overwriting a real latitude because its longitude went missing
  would silently move a break the surfer supplied.
  (`Peak/Supporting/SpotCoordinateResolver.swift`)
- **An actionable state for spots that still cannot be placed.** Explains the
  problem, names the spot, and opens the spot editor. Never an empty view.
- **Today's conditions when confidence is too low to recommend.** A card that
  cannot honestly call a window now shows what the forecast actually says —
  size, period, wind, tide — explicitly labelled "Forecast conditions, not a
  recommendation". Useful on day one instead of a permanent apology.
- **"Fill in past conditions".** An explicit, user-initiated action that fetches
  and stores conditions for existing sessions at a located spot inside
  Open-Meteo's ~92-day archive. This is what actually bootstraps
  personalisation. Sequential with per-session progress, gives up after three
  consecutive failures rather than hammering a dead network, and reports honestly
  how many it managed. It never touches a session that already has conditions,
  and never overwrites the coarse Wind/Wave pickers — those are the surfer's own
  words. (`Peak/Supporting/ConditionsBackfill.swift`)

### Notes

- **The confidence model was not touched.** No threshold was lowered and no
  tuning constant changed. The gate exists so the app never fabricates advice,
  and it still rejects a logbook with no conditions in it and a logbook where
  every session got the same rating — both are pinned by new tests. What changed
  is the *inputs* (many more sessions now qualify as data) and the *UX* (the card
  is useful, and honest about which day it is talking about).
- **Why picker-derived readings carry no extra penalty.** They are coarser than a
  measured reading — a `.breezy` session is somewhere in 5-15 km/h against a
  wind-speed scale of 8 km/h — but the scorer already discounts exactly this
  sparsity twice: the overlap-ratio reliability term (0.215^0.6 = 0.41) and the
  imputed distance floor for the eight unobserved features (kernel 0.14 against
  1.0). Net, such a session enters at roughly 6% of the pull of a fully
  auto-filled one, which is already a heavier penalty than the quantisation error
  justifies. A third discount would be double counting. The estimates are the
  exact inverse of `SurfConditionsMapping`, the app's own definition of each
  band, and a test pins the round trip.
- **Still no passive networking.** Both network actions are taps. The
  `autoRefresh` opt-in still ships off.
- No schema change: every field involved already existed.

## [Unreleased] — 3.2 "On-device AI insights"

Peak can now write about your surfing, on your phone, without your logbook going
anywhere. Apple's on-device model supplies phrasing and nothing else: every
number, spot name and date on screen is computed by Peak's own calculators and
interpolated into the sentence. On a phone that cannot run the model — an older
iPhone, iOS 17 or 18, or Apple Intelligence simply switched off — the feature is
invisible and the same facts render as plain stats. No network call was added.

### Added

- **Monthly recap card on Stats.** Sessions, hours and average rating for the
  current month, plus aggregate highlights: most-surfed break, the board that
  earned its keep and in what conditions, and how the month compares with the one
  before. Renders on every supported device.
  (`Peak/Views/Stats/MonthlyRecapCard.swift`)
- **A narrative paragraph in Year in Review.** Always present, built from the
  same aggregates the metric grid below it shows.
  (`Peak/Views/More/YearInReviewView.swift`)
- **`InsightsEngine`** — reduces `StatsCalculator`, `GearInsightsCalculator` and
  `YearInReviewCalculator` output to a small, bounded facts value, builds the
  prompt, screens what comes back, and renders the plain form. A surfer with ten
  thousand sessions produces exactly the same prompt size as one with ten; raw
  session rows never reach the model. (`Peak/Supporting/InsightsEngine.swift`)
- **`InsightsModel` / `FoundationModelsInsightsGenerator`** — the only code that
  touches `SystemLanguageModel`, behind `#if canImport(FoundationModels)` and
  `if #available(iOS 26, *)`. Guided generation into a `@Generable` type whose
  every field is prose. Responses are streamed rather than awaited whole so a
  reply that hits its token ceiling still yields its finished prefix instead of
  throwing it away. (`Peak/Supporting/FoundationModelsInsights.swift`)

### Notes

- **How hallucinated figures are prevented.** Three independent measures, any one
  of which would have to fail silently for a wrong number to reach the screen.
  The prompt contains no numerals at all — facts are handed over as qualitative
  descriptors ("busier than last month", "excellent"), so there is no figure in
  context to copy. The `@Generable` schema has no numeric field. And
  `InsightsSanitizer` discards any generated text containing a digit, a number
  word, a star or percent sign, or a capitalised word absent from an allow-list
  built from the facts; a rejected field is dropped rather than repaired, and a
  rejected headline drops the whole draft back to plain figures. The only digits
  permitted anywhere are those inside names the surfer typed themselves, such as
  a board called `6'2" Fish`.
- **Availability.** Every unavailability reason — ineligible device, Apple
  Intelligence off, model still downloading, iOS below 26 — is silent. Peak never
  tells a surfer about a feature their phone cannot run.
- **Off the main actor.** `FoundationModelsInsightsGenerator.draft` is
  `@concurrent`, not merely `nonisolated`: under `SWIFT_DEFAULT_ACTOR_ISOLATION =
  MainActor` a nonisolated async function inherits its caller's actor, and
  inference takes seconds. Figures render synchronously; prose arrives later and
  only ever replaces prose.
- Deployment target stays **iOS 17.0**, and the project still builds for it.

### Testing

- +48 unit tests (`PeakTests/InsightsEngineTests.swift`) over aggregation, prompt
  building, output screening, truncation repair, the unavailable-model path and
  the plain-stats fallback rendering. CI never runs a model: every test drives the
  pipeline through the injected `InsightsGenerating` seam.
- +4 UI tests covering the no-model rendering on a simulator (which has no Apple
  Intelligence) and, via a stubbed generator, the AI layout and its privacy line.

## [Unreleased] — 2.8 "Tide + Best Window Today"

Peak answers the surfer's daily question — *when today?* — from their own
logbook rather than from someone else's forecast model. Tide joins the
conditions Peak records, and a card on the Log tab scores the next 24 hours at
your favourite spots against every session you've rated there. Still no account,
no backend, and no network call you didn't ask for.

### Added

- **Tide in the conditions snapshot.** Auto-fill now records sea level relative
  to mean sea level plus a rising / high / falling / low trend, derived from the
  hourly curve either side of your session. It shows in the auto-fill summary and
  in the detail Surf report, and round-trips through export/import.
  (`Peak/Supporting/SurfConditionsService.swift`, `SurfConditionsFormatter.swift`,
  `Peak/Models/TideTrend.swift`)
- **Optional US tide precision.** For spots NOAA gauges, `TideService` fetches
  station-accurate high/low predictions from CO-OPS (free, no key, no account).
  The nearest station is resolved once and cached on the spot. Spots outside US
  coverage silently keep the Open-Meteo curve — that is not an error and is never
  shown as one. (`Peak/Supporting/TideService.swift`)
- **Best Window Today.** A card at the top of the Log tab for your most-logged
  located spots: *"Best window today: 6–9 am — 1.2 m @ 12 s, wind from NE,
  falling tide. Similar to your 5★ session on Mar 12"*, with the cited session
  tappable through to its detail. `WindowScorer` ranks each forecast hour by
  similarity to your own rated sessions at that spot — rating-weighted kernel
  regression with leave-one-out self-calibration, missing readings imputed at
  expected distance rather than skipped. (`Peak/Supporting/WindowScorer.swift`,
  `TodayWindowService.swift`, `Peak/Views/Today/BestWindowTodayCard.swift`)
- **Settings → Best Window Today**: "Refresh automatically when I open Peak",
  **off by default**.

### Changed

- Schema **V9** (1.8.0): `SurfSession.seaLevelHeightM`, `SurfSession.tideTrend`,
  `Spot.tideStationId`. Lightweight additive migration; V8 is frozen as an inline
  snapshot in the same change.
- The marine request now asks for `sea_level_height_msl` and covers three extra
  hours either side of the session, so the tide curve has enough shape to read a
  turning point. Every other reading still averages over the session window only.
- `String+Normalization`, `TideTrend` and `WindowScorer` are `nonisolated` so the
  networking and scoring paths genuinely leave the main actor.

### Notes

- **What the tide numbers mean.** Open-Meteo's sea level is model-derived and
  MSL-referenced. It is trustworthy for direction and rough state — rising,
  falling, roughly when it turns — and not for chart-datum heights or exact turn
  times, so the copy never claims either. Only the NOAA layer quotes a datum
  (MLLW), because only it has one.
- **Confidence, not the predicted rating, gates the card.** With zero or one
  rated session at a spot confidence is exactly zero by construction, and a
  logbook where every session got the same rating carries no signal however large
  it is. Below the threshold the card says "log a few more rated sessions here
  and Peak will learn what works" — it never shows a fabricated window.
- **No offshore/onshore claims.** Deciding that needs the coastline orientation
  of the break, which Peak does not model and will not guess at; wind is
  described by strength and bearing ("wind from NE") instead.
- **No passive networking.** The card is idle until you tap "Check conditions"
  unless you opt in. Ranking runs off the main actor (`@concurrent`), since it
  costs well over a frame on a deep logbook.

## [Unreleased] — 3.0 "Wave Stats"

Every Apple Watch surf workout already stores its GPS route in HealthKit. Peak
now mines that route on-device to estimate how many waves you caught, how fast
the fastest one was, how long the longest ride lasted, and how far you paddled —
and then invites you to correct every one of those numbers. No watch app
required, no account, nothing leaves the phone.

### Added

- **`WaveAnalyzer`.** A stateless, deterministic analyzer that turns a gappy,
  noisy wrist-GPS track into wave count, top speed, ride lengths and paddle
  distance. Accuracy-gated fixes, a least-squares speed fit de-biased for the
  fixes' own noise floor, rolling-median spike rejection, hysteresis thresholds
  with a sustained-evidence rule, distance integrated from speed rather than
  summed from positions, and a distance-weighted heading-consistency test. It
  is CoreLocation-free, so its whole suite runs on synthetic routes with no
  device, no entitlement and no ocean. All 22 tuning constants live in one
  struct for re-fitting against real recordings.
  (`Peak/Supporting/WaveAnalyzer.swift`)
- **HealthKit route access.** `HKSeriesType.workoutRoute()` joins the read set
  and `HealthKitService` streams a workout's `CLLocation`s, mapped to the
  analyzer's `RouteSample` at that boundary. Still behind the existing
  `healthSyncEnabled` opt-in, and still a quiet no-op when it is off, denied, or
  the workout simply has no route. (`Peak/Supporting/HealthKitService.swift`)
- **Wave stats on every session, all of it editable.** A "Wave stats" group in
  the editor's Details section: a stepper for wave count and fields for top
  speed, ride duration, ride distance and paddle distance, in your locale's
  units. Touching any of them marks the session as yours, after which no import
  will ever overwrite it. Works with no workout at all, for the majority of
  surfers who do not wear a watch. (`Peak/Views/Components/WaveStatsEditor.swift`)
- **Wave-stat tags in the session hero**, beside duration, with the provenance
  line right there next to them. (`Peak/Views/History/SessionDetailView.swift`)
- **Import preview.** Health import shows what Peak would derive from each
  workout's route before you commit to importing it.
  (`Peak/Views/More/HealthImportView.swift`)
- **Wave records on Stats.** Most waves in a session, fastest wave, longest
  ride, plus a waves-per-session trend — each resolved independently and the
  whole card suppressed when no session carries wave stats.
  (`Peak/Supporting/WaveStatsCalculator.swift`,
  `Peak/Views/Stats/WaveRecordsCard.swift`)
- Wave count joins the widget's last-session snapshot and the session share card.

### Changed

- Schema **V10** (1.9.0): `SurfSession.waveCount`, `topSpeedKph`,
  `longestRideSeconds`, `longestRideMeters`, `paddleDistanceMeters`,
  `waveStatsSource`, `linkedWorkoutID`. Lightweight additive migration; V9 is
  frozen as an inline snapshot in the same change, since SwiftData rejects two
  versioned schemas that hash to the same shape.

### Notes

- **These are estimates and the app says so, everywhere.** Measured against
  synthetic routes, wave count is exact about 85% of the time and within one
  about 98.5% of the time when the watch reports a usable Doppler speed at 3 m
  position noise; with no device speed at all that falls to roughly 44% exact.
  That spread is precisely why every figure is presented as a correctable
  estimate rather than a fact. The single largest source of one-star reviews for
  competing surf apps is a confidently wrong wave count, and Peak's answer is to
  never be confident and always be one tap from correct.
- **A human's number outranks a GPS trace.** Once you edit or hand-enter a wave
  stat the session is marked `edited` or `manual`, and re-importing the workout
  will not touch it.
- **Zero is data; absent is not.** A skunked session stores zero waves and says
  so. A session that was never tracked stores nothing and shows nothing — no
  empty rows, no "0 waves" for a session that had no route.
- **Nothing runs on the main thread.** Route analysis walks tens of thousands of
  fixes, so it is `@concurrent`; the project's `SWIFT_DEFAULT_ACTOR_ISOLATION =
  MainActor` would otherwise pin it to the UI.
- **No coordinates are persisted.** Only the workout UUID is stored; the route
  is re-read from HealthKit on demand.
- **Still to do:** the analyzer's constants are physically reasoned, not
  ocean-validated. Real-device verification against hand-counted sessions is a
  3.1 gate, and the session map replay was deliberately deferred with it.

## [Unreleased] — 2.9 "Quiver Analytics · Memory Layer · First-Run"

Peak starts using the data it already has: what each board actually does for
you, what you were surfing a year ago today, and where your month stands. Plus
the thing cold start was missing — an explanation of what Peak is. No schema
change, no network, no accounts.

### Added

- **Board Report.** Per-board rating averages bucketed by wave height and by
  swell period (short under 10 s / mid 10–13 s / long 13 s+), with a
  plain-language headline: "6'2" Fish averages 4.2★ in short-period waist-high".
  A bucket with fewer than three rated sessions shows "not enough data yet"
  instead of a number — one good session is not a pattern. Surfaces as a card on
  Stats (boards only) and a full breakdown in gear detail.
  (`Peak/Supporting/GearInsightsCalculator.swift`,
  `Peak/Views/Stats/GearInsightsCard.swift`,
  `Peak/Views/Components/BoardReportCard.swift`)
- **On this day.** A card on the Log tab resurfacing a session from a previous
  year within ±3 days of today — photo, spot, rating — that taps through to the
  session. The window walks backwards a year at a time, so New Year's week and
  Feb 29 behave. (`Peak/Supporting/OnThisDayProvider.swift`,
  `Peak/Views/Log/OnThisDayCard.swift`)
- **Year in Review.** On-demand from More (and from a Log-tab card during
  December): sessions, surf days, hours in water, top spot, best month, longest
  week streak, wave-height distribution, and a highlights grid. Exports as a
  branded image via `RecapShareCard`, using the same off-main decode +
  `ImageRenderer` pipeline as the session share card. Renders sensibly on a
  one-session library. (`Peak/Supporting/YearInReviewCalculator.swift`,
  `Peak/Views/More/YearInReviewView.swift`, `Peak/Views/More/RecapShareCard.swift`)
- **Flexible monthly goals.** A monthly target in sessions *or* hours with a
  progress ring on Stats, above the consistency heatmap. Goals get top billing
  and streaks stay secondary on purpose: surfing is condition-gated, and a rigid
  streak turns a flat week into a failure you couldn't have prevented. Set the
  metric and target in Settings; zero hides the ring. Stored in `@AppStorage`.
  (`Peak/Supporting/MonthlyGoalCalculator.swift`,
  `Peak/Views/Stats/MonthlyGoalCard.swift`)
- **First-run welcome.** Three screens behind `@AppStorage("hasSeenWelcome")` —
  what Peak is, the privacy promise (on-device, no account, no tracking), and a
  "Log your first session" CTA that opens the editor. Skipped under UI-test, ad
  capture, and screenshot modes so existing baselines are untouched.
  (`Peak/Views/Onboarding/WelcomeView.swift`)
- **TipKit tips** (deferred from 2.6): one on the Log CTA until you've logged
  something, one on Auto-fill Conditions that appears after your first manual
  save. Hard-disabled under every automation mode.
  (`Peak/Supporting/PeakTips.swift`)

### Changed

- Settings gained a **Monthly Goal** section (metric picker + target stepper).
- More gained a **Year in Review** entry.
- The Log tab now also queries the full session history (the recents list stays
  limited to three) so the memory layer can reach back years.

### Notes

- No SwiftData schema change: everything here is derived from existing session
  fields or stored in `@AppStorage`.
- The board report's period bands (10 s / 13 s) are deliberately coarser than the
  Best-Conditions card's (8 s / 11 s): board choice and session quality don't
  split at the same thresholds.

## [Unreleased] — 2.7 "Ecosystem Unlock"

Peak leaves the app icon: Home and Lock Screen widgets, real App Intents
entities for Siri/Spotlight/Shortcuts, a Control Center button, and a Live
Activity that counts a session while you're in the water. Everything renders
local data only — no accounts, no backend, no network.

### Added

- **Widgets (Home + Lock Screen).** *Surf Streak* (week streak, sessions this
  month, days since last surf) and *Last Session* (spot, rating, how long ago),
  in small/medium plus the accessory families. Both deep-link into a new session.
  The widget never opens the SwiftData store: the app derives a small
  `PeakWidgetSnapshot` and publishes it to a shared App Group container, so
  there's no store migration and no risk to your library.
  (`PeakWidgets/`, `Peak/WidgetSnapshot.swift`, `Peak/Supporting/WidgetSnapshotWriter.swift`)
- **Session in progress + Live Activity.** Start a session from the Log hero,
  Siri, the Action button, or Control Center; the elapsed timer appears on the
  Lock Screen and in the Dynamic Island (and, on a paired Apple Watch, the Smart
  Stack). Ending it opens the log prefilled with your start time, a duration
  rounded to the nearest 5 minutes, and the spot — you just add rating and notes.
  The timer is drawn with `Text(timerInterval:)`, so Peak sends no push updates
  and holds no push token.
  (`Peak/ActiveSession.swift`, `Peak/SessionActivityController.swift`, `PeakWidgets/SessionLiveActivity.swift`)
- **App Intents, properly.** `SurfSessionEntity` and `SpotEntity` with stable
  identifiers and display representations put your logbook into the Spotlight
  semantic index and make it addressable from Shortcuts. Five intents ship with
  natural Siri phrases: Log Session, Start Session, End Session, Last Session
  ("when did I last surf?"), and Sessions This Month.
  (`Peak/Supporting/AppIntentsEntities.swift`, `AppIntents+Peak.swift`, `SessionIntentQueries.swift`)
- **Control Center button** (iOS 18+) that starts a session without launching
  Peak. (`PeakWidgets/StartSessionControl.swift`)

### Changed

- The Log hero gained a **Start Session** control beside Log Session, and shows a
  running timer with an End Session button while a session is in progress.
- `SessionEditorView(mode:.new)` accepts an optional prefilled draft.
- The widget snapshot is refreshed on launch, on every session save/delete or
  backup restore, and each time Peak returns to the foreground.

### Fixed

- The widget extension was signed with the wrong development team (a stale
  `SQ949Q468V`, which fails as "No Account for Team") and carried a stale
  marketing version. Both now track the app target.
- "Sessions this month" counted the first instant of the following month, because
  `DateInterval.contains` is inclusive of its end.

### Notes

- The in-progress session lives in App-Group `UserDefaults`, **not** SwiftData —
  2.7 ships no schema change.
- ActivityKit is disabled under UI tests so the automated suite never depends on
  Live Activity chrome.
- **Manual step before release:** the App Group `group.com.designprism.peak` must
  be registered in the Developer portal and associated with both bundle IDs. The
  App Store Connect API can enable the capability but cannot create the group.

## [2.6] — 2026-07-15 — App Store submission (build 2)

### Docs / compliance (build 2)
- Privacy policy (repo + in-app) documents Apple Health, optional location, Open-Meteo auto-fill, and local-only storage so App Review matches the binary.
- Unit-test host opens an ephemeral store; catalog search no longer touches `@Model Spot` (CI stability).

## [2.6] — 2026-07-13 — TestFlight (build 1, product features)

An Apple-best-practices polish pass driven by a full audit against the current
Human Interface Guidelines and iOS 26 SDK docs: a friendlier first run, correct
input controls, deeper accessibility, iPad-aware layout, an App Store compliance
fix, and a SwiftData safety hardening.

### Added

- **iPad / regular-width layout.** New `readableContentWidth()` caps content at a
  comfortable ~720pt measure and centers it on iPad, landscape, and Split View,
  instead of stretching cards edge-to-edge. It's a no-op at iPhone-portrait widths.
  Applied to Log, Stats, Quiver, Session detail, and the Spot editor.
  (`Peak/Views/Components/ReadableContentWidth.swift`)
- **Haptic on the primary action.** Logging a session now gives a light impact,
  matching the save/delete feedback already elsewhere. (`LogView.swift`)

### Changed

- **First run no longer hits a wall.** Saving a surf break used to require a name,
  a location string, *and* a dropped map pin — so the very first log forced a full
  map detour. Now only a name is required; location and pin are optional
  progressive enhancements (the data model already allowed it), and the existing
  "My Location" shortcut fills them in one tap. (`SpotEditorView.swift`)
- **Wind & Wave height are pickers, not sliders.** They're small named sets, not
  continuous ranges — menu pickers (HIG: pickers for a fixed set) now read the
  labels directly instead of dragging a slider to the right notch. (`SessionEditorView.swift`)
- **Adaptive logo badge.** The Log hero badge now uses the ink mark on a light
  tile in light mode (was a fixed near-black tile on white paper). (`LogView.swift`)

### Accessibility

- The media **remove** button now has a 44pt hit target (HIG minimum).
- A fixed 10pt detail caption is now a semantic `.caption2` that scales with
  Dynamic Type. (`SessionDetailView.swift`)
- **Reduce Motion** now strips the Session-detail disclosure animation, matching
  the editor.

### Fixed

- **Privacy manifest completeness (App Store upload).** `PrivacyInfo.xcprivacy`
  now declares the required-reason APIs the app actually uses — UserDefaults
  (`CA92.1`), file timestamps (`C617.1`), and disk space (`E174.1`). Previously an
  empty array, which risks the ITMS-91053 rejection on upload.

### Internal

- **SwiftData schema hardening.** The HEAD schema (`PeakSchemaV8`) references the
  live model classes, so a future field edit could silently redefine the shipped
  1.7.0 schema and shunt a user's store into the recovery archive. A new guard
  test (`testHeadSchemaShapeIsPinned`) pins HEAD's field set, so any accidental
  live-model edit now fails CI with instructions to freeze + migrate first. (A
  literal no-op freeze isn't possible — SwiftData rejects two identical-shape
  schemas in one plan — so the pin is the correct enforcement.)
  (`ModelMigrationTests.swift`)
- **CI** pinned to macOS 15 + Xcode 26 (reproducible; exercises the shipping iOS 26
  Liquid Glass code paths). (`.github/workflows/ci.yml`)

## [2.5] — 2026-07-02 — TestFlight (build 1, beta)

The largest Peak release to date: a Stats overhaul, full media-inclusive backups,
Apple Health integration, History search, a spots map, and a broad performance pass.

### Added

- **Stats 2.0.** The Stats tab now surfaces data it already collected but never
  showed: total time in water, average session length, surf days this year, and
  current **and** longest week streaks; a GitHub-style consistency heatmap; a
  horizontally-scrollable monthly-sessions chart with tap-to-inspect; a spot-mix
  donut; and conditions insights (wave-height-vs-rating scatter + a "your best
  sessions" summary). Top spots / gear / buddies rows are now tappable into their
  detail screens. (`Peak/Views/Stats/**`, `StatsCalculator.swift`)
- **Apple Health integration (iPhone-only, opt-in).** Logged sessions save to
  Health as `surfingSports` workouts; Apple Watch surf workouts you record
  surface heart rate and active calories on the session detail; an "Import from
  Health" screen offers to log unlogged Watch surfs. Settings → Apple Health.
  (`HealthKitService.swift`, `HealthImportView.swift`)
- **Full Backup (includes photos & videos).** A new `.peakbackup` archive backs
  up everything — sessions, spots, gear, buddies, **and all media** — and restores
  with a merge/replace choice. JSON/CSV exports (metadata only) are unchanged.
  (`BackupManager.swift`)
- **Session share card.** Share a branded summary of any session (spot, date,
  rating, conditions, first photo) from the session detail toolbar.
- **History search & richer filters.** Search across spot, notes, gear, and
  buddies (diacritic-insensitive, debounced), plus multi-select spot/gear/buddy
  filters, a minimum-rating filter, and date ranges, with a removable active-filter
  chips row. (`HistoryFilters.swift`)
- **Spots map.** A map of every pinned break with per-spot session-count badges,
  reachable from Spots. Adding a spot now offers **Use My Location** with reverse
  geocoding. (`SpotsMapView.swift`, `LocationService.swift`)

### Changed

- **Navigation.** Spots and Buddies are now direct rows in More (the redundant
  Library hub and duplicated Quiver entry were removed).
- **Higher limits.** The saved-spots cap went from 10 to 200, and session duration
  now goes up to 8 hours in 5-minute steps (was 3 hours / 15-minute steps).

### Fixed / Performance

- **Adding photos no longer freezes the editor.** Photo compression and thumbnail
  generation now run off the main thread (`@concurrent`), so multi-photo picks
  stay smooth. (`SessionMediaStore.swift`, `SessionEditorView.swift`)
- **Faster, lighter data access.** The session editor's query now prefetches
  relationships, and the Open-Meteo conditions parser reuses cached formatters.
- **Crash-proof launch.** A corrupt or unreadable data store no longer bricks the
  app on launch: it's archived aside and a fresh store is created, with a one-time
  notice. (`PeakDataStore.swift`)

### Deferred to a later build

- **Home/Lock Screen widgets** (streak + last session) are code-complete but
  require registering the app's App Group identifier via the Developer portal /
  Xcode (not creatable through the headless App Store Connect API). Held on the
  `feature/2.5-widgets` branch until that one-time registration is done.

## [2.4] — 2026-06-29 — App Store (builds 4 & 5)

Two UI refinements re-authored onto the 2.0 adaptive (light/dark, HIG) design
trunk. Build 4 shipped the session-detail header redesign; build 5 adds the Log
Session spot-picker fix on top.

### Added

- **Session detail — media-forward hero header.** Photos and videos now lead the
  session summary: a horizontally-scrolling media strip sits at the top of the
  hero card (above the wave-height block). Tap any thumbnail to open the
  full-screen viewer. Reuses the existing off-main-thread decode/crop pipeline
  (`SessionMediaThumbnailView`), so scrolling stays smooth.
  New `heroMediaStrip` in `SessionDetailView.swift`; accessibility ids
  `session.detail.heroMedia.photo` / `.video`, kept distinct from the body grid.

### Changed

- **Cleaner session summary.** The star rating moved to a top-right "eyebrow"
  beside the date (`heroRatingTag` → `heroRatingStars`, de-chromed to bare
  stars). The redundant "N media" and rating chips were removed from the stat
  row; the responsive duration / time / gear / buddy chips (`ViewThatFits`) are
  unchanged, and their `session.detail.heroTag.*` identifiers are preserved.

### Fixed

- **Log Session — recent-spot chips overflow (build 5).** The recent surf-break
  suggestion chips no longer spill past the SPOT section card to the screen edge.
  Root cause: the chip row's horizontal `ScrollView` was wrapped in a
  `GlassContainer` (iOS 26 `GlassEffectContainer`) whose merged glass rendering
  escaped the scroll clip. Fix: removed the redundant container (each
  `SelectableChip` already carries its own `glassCapsule`) and added `.clipped()`
  so the row is bounded to the card's content edge. Chips remain fully tappable.
  (`SessionEditorView.swift`.)

### Release / versioning

- `MARKETING_VERSION` 2.3 → 2.4; `CURRENT_PROJECT_VERSION` 1 → 4 (build 4) → 5
  (build 5), Debug + Release.
- Verified by `testSessionDetailHeroLabelsStayReadable`,
  `testMediaViewerPhotoLayout` / `testMediaViewerVideoLayout`,
  `testSessionEditorLayoutFits`, and `testCreateSessionAppearsInHistory`.
- Both changes were prototyped on the stale `feature/streamlined-log-session`
  branch (pre-2.0 design) and re-implemented on `main` so the 2.0 trunk is not
  regressed. See `RELEASE_PLAYBOOK.md` for the branch-strategy warning.

## [2.0] — 2026-06-11 — App Store

### Added

- Adaptive light/dark design system (ocean/foam, ink/paper palettes) with Liquid
  Glass surfaces on iOS 26 and iOS 17–18 fallbacks.
- Human Interface Guidelines alignment across all surfaces; SF system fonts with
  Dynamic Type.
- Glanceable wave-height hero block in session detail (`heroWaveHeight`).
- Quick-Start logging: one-tap reuse of the last session, plus recency-based
  spot / gear / buddy chips with a `ViewThatFits` responsive layout.

### Fixed

- Contrast and accessibility across both color schemes; session-editor bottom
  sections reachable while the keyboard is up.

---

Releases before 2.0 predate this changelog; see the git history and
`RELEASE_PLAYBOOK.md`.
