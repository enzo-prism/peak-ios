# Peak — AGENTS.md

Peak is an iOS surf-session journal (SwiftUI + SwiftData, **iOS 17+**).
This file is the operating manual for Codex CLI / AI agents working in this repo.

If instructions conflict, follow (in order):
1) This file
2) README.md acceptance criteria
3) Existing code patterns in this repo

---

## Product North Star

Peak should feel **fast and satisfying** to log sessions and manage your quiver.

Optimize for:
- **Fast logging** (seconds, minimal typing)
- **Excellent gear tracking** (boards/wetsuits/fins/leashes/other + usage over time)
- **Great spot/break tracking** (recents-first selection, meaningful spot stats)
- **Clear trends** (surf frequency + “what I used / where I surfed” insights)
- **Private by default** (local-only)

No social/sharing, accounts, or backend for now.

---

## Non-Negotiables

### Privacy & data
- **Local-only storage** (SwiftData). No backend. No accounts. No social. No analytics SDKs.
- Do **not** add network calls or permissions unless explicitly requested.
- Keep `PrivacyInfo.xcprivacy` accurate if anything privacy-related changes.

### Platform
- Minimum iOS version stays **17.0** unless explicitly requested.
- Do not change bundle ID / signing settings.
- Do not change supported destinations (iPhone/iPad/Mac/Vision) unless explicitly requested.

### Design system
- Keep Peak’s established surf look & feel.
- Use and extend the existing design system:
  - `Peak/Supporting/Theme.swift`
  - `Peak/Supporting/GlassHelpers.swift`
  - `Peak/Views/Components/*`
- Do not introduce a new styling system, random colors, or a new font stack.

### Code churn
- Keep diffs small and targeted.
- Avoid sweeping refactors (file moves/renames/architecture rewrites) unless required.

---

## How to Work in This Repo

### Before coding
- Read the relevant existing files and match existing patterns.
- Provide a short plan (3–7 bullets) + list the files you expect to touch.
- Confirm you are not changing privacy/platform constraints.

### Definition of done (required)
- Run tests: `./scripts/test.sh` (**must pass**).
- For any UI change, run `./scripts/design-check.sh` (or explain why it’s not applicable).
- No new warnings or broken builds.
- If UI layout/snapshot tests fail, update only what’s necessary and keep the UI consistent.
- Provide a concise summary:
  - what changed
  - where it changed
  - how to manually verify

---

## Build / Test / Simulator Rules

Prefer **XcodeBuildMCP** tools when you need to:
- build/test
- boot/run simulators
- install/launch
- stream logs
- capture screenshots/video

If not using MCP tools, use repo scripts (do not invent custom `xcodebuild` commands):
- Boot simulator: `./scripts/boot-sim.sh`
- Build (sim): `./scripts/build-sim.sh`
- Test (unit + UI): `./scripts/test.sh`

Project/scheme assumptions:
- Scheme is likely `Peak`.
- Prefer `.xcworkspace` if present; otherwise use `Peak.xcodeproj`.

---

## Product Priorities (use this to choose between approaches)

1) **Logging speed**
   - Defaults and recents-first selection
   - Progressive disclosure for optional fields
   - No extra taps for “power features”

2) **Gear tracking (hero feature)**
   - Boards/wetsuits/fins/leashes/other
   - “Times used”, “Last used”, and “Usage over time” should be easy to access
   - Deletion must be safe: if gear/spot/buddy is referenced by sessions, block deletion or handle explicitly (no silent meaning loss)

3) **Spots/breaks**
   - Fast selection (recents-first)
   - Spot detail should show meaningful stats and session history

4) **Trends**
   - Surf frequency over time (year-to-date + monthly)
   - Top spot / top gear / top buddy
   - Trends must update correctly after edits/deletes

5) **Gamification (only if requested)**
   - XP/levels must never slow logging
   - Prefer recomputable metrics from session history (avoid drift)
   - Must stay consistent under session edit/delete

---

## Architecture & Data Guidance

### SwiftUI
- Prefer small composable views and reuse existing components.
- Keep navigation consistent with existing tabs and flows.

### SwiftData
- Models are the source of truth; schema/versioning exists—extend carefully.
- Prefer additive changes. Avoid destructive migrations unless explicitly requested.
- **Derived metrics should be computed from sessions** unless there’s a strong reason to cache.
  If caching derived values (e.g., XP/levels), it must remain correct under session edit/delete.

---

## Where to Put New Code (keep the repo organized)

- New SwiftUI screens: `Peak/Views/<Area>/...` (Log / History / Stats / More)
- Reusable UI components: `Peak/Views/Components/`
- Theme/styling helpers: `Peak/Supporting/Theme.swift` or `Peak/Supporting/GlassHelpers.swift`
- Calculators/formatters/helpers: `Peak/Supporting/`
- Models: `Peak/Models/`
- Unit tests: `PeakTests/`
- UI tests/snapshots: `PeakUITests/`

---

## Docs & Reference Material

- `AdditionalDocumentation/` is reference material only (not runtime code).
- Prefer using it for implementation guidance (SwiftUI, SwiftData, Liquid Glass), but do not treat it as a dependency.

### Design sources of truth (in order)
1) `AdditionalDocumentation/` Apple docs (platform rules)
2) `Peak/Supporting/Theme.swift` + `Peak/Supporting/GlassHelpers.swift` + `Peak/Views/Components/*` (Peak implementation)
3) Existing screens (consistency)

### UI work protocol (required for UI changes)
- Identify which Apple doc(s) apply (Liquid Glass, SwiftUI toolbars, styled text editing, charts, etc.)
- Summarize 3–5 rules you’re applying (write them in your plan or PR summary)
- Implement using Theme/components (avoid one-off styling)
- Validate: tests + screenshots across devices

### Do not ship docs
- `AdditionalDocumentation/` is not runtime code and must not be included in the app bundle.

---

## Accessibility & Quality

- Maintain existing contrast/accessibility requirements (tests must pass).
- New UI must support Dynamic Type and have reasonable VoiceOver labels.
- Keep CI passing.

---

## Repo Map (quick reference)

- App entry: `Peak/PeakApp.swift`
- Tabs/shell: `Peak/ContentView.swift`
- Models: `Peak/Models/*`
- Schema/helpers: `Peak/Supporting/ModelSchema.swift`, `Peak/Supporting/ModelContext+Helpers.swift`
- Log flow: `Peak/Views/Log/*`
- History: `Peak/Views/History/*`
- Stats: `Peak/Views/Stats/*`, `Peak/Supporting/StatsCalculator.swift`
- More/Settings/Docs: `Peak/Views/More/*`
- Design system: `Peak/Supporting/Theme.swift`, `Peak/Supporting/GlassHelpers.swift`
- Components: `Peak/Views/Components/*`
- Tests: `PeakTests/*`, `PeakUITests/*`
- CI: `.github/workflows/ci.yml`
- In-app docs: `Peak/Resources/Privacy.md`, `Peak/Resources/Support.md`
- Privacy manifest: `Peak/PrivacyInfo.xcprivacy`

---

## Out of Scope (unless explicitly requested)

- Social/sharing, accounts, cloud sync/backends
- New third-party SDKs
- Big architecture rewrites (MVVM overhaul, DI frameworks, etc.)
