# Peak - Surf Log

Peak is a fast, private surf-session logbook. Track when you surfed, where you paddled out, what gear you rode, who you surfed with, and the conditions, then look back anytime.

## Product scope
- Offline-first, on-device storage only
- No accounts or social features
- Quick session logging (date + spot required)
- Optional wind and wave height conditions
- Photo and video attachments per session
- History timeline with filters (spot, gear, buddy)
- Basic stats (totals, top spots, most-used gear)

## Design system
- Black and white palette with liquid-glass inspired surfaces and depth
- Contrast tokens are enforced by automated tests (4.5:1 body, 7:1 key text)
- Theming lives in `Peak/Supporting/Theme.swift` and related helpers

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
- Data stays on-device; no accounts, analytics, or network calls

## Acceptance criteria
- Users can log a session in under 60 seconds
- Sessions can be filtered by spot, gear, or buddy
- Stats view shows totals, top spots, and most-used gear
- App works fully offline and stores data locally
- Accessible with Dynamic Type and VoiceOver basics
