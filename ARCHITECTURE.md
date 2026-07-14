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
- Schema + migrations: `Peak/Supporting/ModelSchema.swift` (see `PeakMigrationPlan`); the live container targets the HEAD versioned schema in `Peak/Supporting/PeakDataStore.swift`
- Storage is local only; UI tests seed in-memory data via `Peak/Supporting/PreviewData.swift`
- **Schema invariant:** every past `PeakSchemaVn` is a *frozen* inline snapshot of the model shape it shipped with; only the HEAD schema (`PeakSchemaV8`) references the live model classes. Editing a live `@Model` field therefore silently redefines the shipped HEAD version — so before changing any field, freeze the current HEAD as the next `Vn` snapshot and add a new live-referencing HEAD carrying the delta plus a `.lightweight` stage. Two guards enforce this in `ModelMigrationTests`: `testHeadSchemaShapeIsPinned` fails the moment HEAD's field set drifts, and `testV7ToV8MigrationBackfillsMediaDefaults` exercises a real on-disk staged migration. Note: SwiftData rejects two identical-shape schemas in one plan ("duplicate version checksums"), so a no-op version bump is invalid — freeze only alongside a genuine shape change.
- **CloudKit note:** the models are intentionally *not* CloudKit-ready — `Spot`/`Gear`/`Buddy` use `@Attribute(.unique) key`, and several attributes are non-optional without defaults. Adding sync later would be a schema-wide breaking migration (drop uniques, make everything optional/defaulted, dedupe in code), not an additive change. This is a deliberate offline-first trade-off.

**Session Logging Flow**
- Log screen: `Peak/Views/Log/LogView.swift`
- Editor: `Peak/Views/Log/SessionEditorView.swift`
- Session editor writes to `SessionDraft`, then commits to `SurfSession`
- First paint is one focused card (date/time prefilled to now + spot); everything else lives in collapsed disclosure groups (progressive disclosure)
- Required input: a spot (a spot itself only requires a name — location/pin are optional and can be added later)
- Optional inputs: duration, rating, notes, gear, buddies, media, wind/wave (menu pickers)

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

**Spots, Buddies & Quiver**
- Spots and Buddies are reached from the More tab; Quiver is a top-level tab
- Spot editor (optional pin location): `Peak/Views/Library/SpotEditorView.swift`
- Quiver (gear): `Peak/Views/Quiver/QuiverView.swift` and related gear views
- Spots map + "Use My Location": `Peak/Views/Spots/SpotsMapView.swift`, `Peak/Supporting/LocationService.swift`

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
