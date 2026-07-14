# Changelog

All notable changes to Peak (iOS) are documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

Status at a glance:

- **App Store (live):** `2.0`
- **TestFlight (beta):** `2.6` — build 1, uploaded 2026-07-13 (Apple-grounded UX/design + platform polish, below); `2.5` build 1 previously in beta

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
