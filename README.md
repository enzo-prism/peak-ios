# Peak - Surf Log

Peak is a fast, private surf-session logbook. Track when you surfed, where you paddled out, what gear you rode, who you surfed with, and the conditions, then look back anytime.

## Product scope
- Offline-first, on-device storage only
- No accounts or social features
- Quick session logging (date + spot required)
- Optional wind and wave height conditions
- Optional auto-fill of surf conditions via Open-Meteo (only when triggered)
- Photo and video attachments per session
- History timeline with filters (spot, gear, buddy)
- Basic stats (totals, top spots, most-used gear)
- Spot library with pinned locations (required for auto-fill, capped at 10)
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
- Black and white palette with liquid-glass inspired surfaces and depth
- Contrast tokens are enforced by automated tests (4.5:1 body, 7:1 key text)
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
- Run unit + UI tests: `./scripts/test.sh`

Optional overrides:
- `SCHEME=Peak ./scripts/test.sh`
- `DESTINATION_NAME="iPhone 16 Pro" ./scripts/build-sim.sh`

## Testing
- Unit tests (contrast):  
  `xcodebuild -project Peak.xcodeproj -scheme Peak -destination 'platform=iOS Simulator,name=iPhone 16,OS=18.5' -only-testing:PeakTests test`
- UI layout tests:  
  `xcodebuild -project Peak.xcodeproj -scheme Peak -destination 'platform=iOS Simulator,name=iPhone 16,OS=18.5' -only-testing:PeakUITests test`
- UI tests seed in-memory data when `UITESTS=1` is set (handled by the test target)

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
