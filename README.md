# Peak - Surf Log

Peak is a fast, private surf-session logbook. Track when you surfed, where you paddled out, what gear you rode, and who you surfed with, then look back anytime.

## Product scope
- Offline-first, on-device storage only
- No accounts or social features
- Quick session logging (date + spot required)
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

## Testing
- Unit tests (contrast):  
  `xcodebuild -project Peak.xcodeproj -scheme Peak -destination 'platform=iOS Simulator,name=iPhone 16,OS=18.5' -only-testing:PeakTests test`
- UI layout tests:  
  `xcodebuild -project Peak.xcodeproj -scheme Peak -destination 'platform=iOS Simulator,name=iPhone 16,OS=18.5' -only-testing:PeakUITests test`
- UI tests seed in-memory data when `UITESTS=1` is set (handled by the test target)

## Acceptance criteria
- Users can log a session in under 60 seconds
- Sessions can be filtered by spot, gear, or buddy
- Stats view shows totals, top spots, and most-used gear
- App works fully offline and stores data locally
- Accessible with Dynamic Type and VoiceOver basics
