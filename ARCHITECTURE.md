# Peak Architecture

This document describes the runtime structure, data model, and key flows in Peak. It is intended for contributors and maintainers.

**Overview**
- UI is built in SwiftUI with a tab-based shell.
- Data is stored locally in SwiftData with migration support.
- No backend, accounts, or analytics. Networking is only used for optional surf-condition auto-fill.

**App Shell & Navigation**
- Entry point: `Peak/PeakApp.swift`
- Tabs and routes: `Peak/ContentView.swift`
- Tabs: Log, History, Stats, Quiver, More
- Styling: `Peak/Supporting/Theme.swift` and `Peak/Supporting/GlassHelpers.swift`

**Data Model & Storage**
- SwiftData models: `Peak/Models/SurfSession.swift`, `Peak/Models/Spot.swift`, `Peak/Models/Gear.swift`, `Peak/Models/Buddy.swift`, `Peak/Models/SessionMedia.swift`
- Draft/edit state: `Peak/Models/SessionDraft.swift`
- Schema + migrations: `Peak/Supporting/ModelSchema.swift` (see `PeakMigrationPlan`)
- Storage is local only; UI tests seed in-memory data via `Peak/Supporting/PreviewData.swift`

**Session Logging Flow**
- Log screen: `Peak/Views/Log/LogView.swift`
- Editor: `Peak/Views/Log/SessionEditorView.swift`
- Session editor writes to `SessionDraft`, then commits to `SurfSession`
- New-session mode now includes a `Quick Start` block that pre-fills from the most recent session and exposes recent spot/gear chips for one-tap setup.
- Required inputs: date/time and spot selection
- Optional inputs: duration, rating, notes, gear, buddies, media

**Surf Conditions Auto-Fill**
- Triggered by the user in `SessionEditorView`
- Requirements: duration + surf break with pinned latitude/longitude
- Service layer: `Peak/Supporting/SurfConditionsService.swift`
- Mapping and display helpers: `Peak/Supporting/SurfConditionsMapping.swift`, `Peak/Supporting/SurfConditionsFormatter.swift`
- Data stored on session: wind, wave, swell, water temperature, source, fetch time, and coordinates
- Fetched data is averaged across the session time window

**Media Handling**
- Photos are stored inline on `SessionMedia` (external storage attribute)
- Videos are stored as files in `Application Support/SessionMedia`
- Storage helpers: `Peak/Supporting/SessionMediaStore.swift`
- Display: `Peak/Views/History/SessionDetailView.swift`, `Peak/Views/Components/SessionMediaThumbnailView.swift`

**History & Detail Views**
- History list: `Peak/Views/History/HistoryView.swift`
- Session detail: `Peak/Views/History/SessionDetailView.swift`
- Filters for spot, gear, and buddy are applied in History

**Stats & Trends**
- Stats UI: `Peak/Views/Stats/StatsView.swift`
- Calculations: `Peak/Supporting/StatsCalculator.swift`, `Peak/Supporting/UsageMetricsCalculator.swift`

**Library & Quiver**
- Library hub: `Peak/Views/More/LibraryView.swift`
- Spot editor (pin locations): `Peak/Views/Library/SpotEditorView.swift`
- Quiver: `Peak/Views/Library/QuiverView.swift` and related gear views

**Export / Import**
- Settings UI: `Peak/Views/More/SettingsView.swift`
- Export/import logic: `Peak/Supporting/ExportFormat.swift`
- JSON export, CSV export, and JSON import (merge or replace)

**Privacy & Networking**
- Privacy policy: `PRIVACY.md`, in-app: `Peak/Resources/Privacy.md`
- Optional network calls are only made when auto-fill is triggered by the user
- No analytics, accounts, or background sync

**Testing**
- Unit tests: `PeakTests/*`
- UI layout tests: `PeakUITests/*`
- Standard commands: `./scripts/build-sim.sh`, `./scripts/test.sh`
