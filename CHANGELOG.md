# Changelog

All notable changes to Peak (iOS) are documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

Status at a glance:

- **App Store (live):** `2.0`
- **TestFlight (beta):** `2.4` — builds 4 and 5, `IN_BETA_TESTING` (internal Test Group A)

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
