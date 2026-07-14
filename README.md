# Peak - Surf Log

Peak is a fast, private surf-session logbook. Track when you surfed, where you paddled out, what gear you rode, who you surfed with, and the conditions, then look back anytime.

## Product scope
- Offline-first, on-device storage only
- No accounts or social features
- Quick session logging (date + spot required)
- Optional wind and wave height conditions
- Optional auto-fill of surf conditions via Open-Meteo (only when triggered)
- Quick-start session scaffolding in New Session (use last session setup, recent spots, and recent gear)
- Photo and video attachments per session
- History timeline with filters (spot, gear, buddy)
- Basic stats (totals, top spots, most-used gear)
- Spot library with optional pinned locations (a pin unlocks maps + conditions auto-fill; name-only spots are fine)
- JSON + CSV export, JSON import (merge or replace)

## Surf conditions auto-fill
- Requires a session start time, duration, and a surf break with a pinned location.
- Pulls marine + wind data from Open-Meteo, averages across the session window, and stores the source + fetch time.
- Never runs automatically; it only fires when the user taps **Auto-fill Conditions**.

## Architecture overview
- **UI**: SwiftUI tabs (`Log`, `History`, `Stats`, `Quiver`, `More`) with shared glass styling in `Peak/Supporting/Theme.swift`.
- **Data**: SwiftData models (`SurfSession`, `Spot`, `Gear`, `Buddy`, `SessionMedia`) with local-only storage.
- **Editing**: `SessionDraft` stages changes before saving to a `SurfSession`.
- **Media**: Photos stored inline; videos stored in `Application Support/SessionMedia` and referenced by filename.
- **Conditions**: `SurfConditionsService` calls Open-Meteo marine + weather endpoints when auto-fill is tapped.
- **Stats**: `StatsCalculator` + `UsageMetricsCalculator` compute totals, streaks, and top items.
- **Export/Import**: `PeakExportManager` handles JSON/CSV export and JSON restore.

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
- Minimum iOS: 17.0 (SwiftData)
- Data store: SwiftData (local only)
- UI: SwiftUI

## Getting started
1. Open `Peak.xcodeproj` in Xcode 17+
2. Select the `Peak` scheme
3. Run on any iOS 17+ simulator or device

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
- Next build number for a version: `./scripts/asc-sync.sh next-build 1.9 IOS`
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
- Data stays on-device; no accounts or analytics. Optional Open-Meteo requests are made only when you use Auto-fill Conditions.

## Acceptance criteria
- Users can log a session in under 60 seconds
- Sessions can be filtered by spot, gear, or buddy
- Stats view shows totals, top spots, and most-used gear
- App works fully offline and stores data locally
- Accessible with Dynamic Type and VoiceOver basics
- Auto-fill conditions only runs on tap and requires a duration + pinned spot

## UX Notes
- New-session logging now surfaces a `Quick Start` section with a one-tap "Use last session setup" action and recency-based spot/gear chips to reduce logging friction.
