# Changelog

All notable changes to Peak (iOS) are documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

Status at a glance:

- **App Store (live):** `2.0`
- **TestFlight (beta):** `2.6` — build 1, uploaded 2026-07-13 (Apple-grounded UX/design + platform polish, below); `2.5` build 1 previously in beta

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

## [2.6] — 2026-07-13 — TestFlight (build 1, beta)

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

## [2.4] — 2026-06-29 — TestFlight (builds 4 & 5, beta)

## [2.4] — 2026-06-29 — TestFlight (builds 4 & 5, beta)

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
