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
- **Networking is explicit-user-action-only.** The only endpoints are Open-Meteo and
  NOAA CO-OPS, and they are reached when the user taps Auto-fill Conditions or
  Check Conditions — or via the Best Window Today auto-refresh toggle, which is
  opt-in and off by default. Nothing fetches on launch by default.
- **On-device means on-device.** Language-model inference and GPS route analysis
  never leave the phone, and no route coordinates are persisted (only a workout
  UUID). Do not introduce a server-side model, ever.
- HealthKit reads stay behind the `healthSyncEnabled` opt-in and must be a quiet
  no-op when it is off or denied. Background workout delivery uses the HealthKit
  background-delivery entitlement and is still gated on that same toggle. Local
  Watch-surf notifications are a **second** opt-in (`notifyUnloggedSurfWorkouts`),
  off by default.
- Keep `PrivacyInfo.xcprivacy` accurate if anything privacy-related changes.

### Honesty about derived numbers
- Wave stats are **estimates**, labelled as such everywhere, and correctable in-app.
  A user's edit always outranks a derived value; re-import must never overwrite an
  `edited` or `manual` session.
- Best Window Today is gated on **confidence**, not on the predicted rating. Below
  the threshold, say so — never render a fabricated window.
- A statistic computed from too little data must say "not enough data yet" rather
  than show a number (the Board Report's floor is three rated sessions per bucket).
- No figure on screen may originate from a language model. See
  `ARCHITECTURE.md` → On-Device Insights for the three guarantees; if you add an
  insight surface, it must keep all three.

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
- Run tests: `./scripts/test.sh` (**must pass**) — one `xcodebuild` at a time, see below.
- For any UI change, run `./scripts/design-check.sh` (or explain why it’s not applicable).
- Use `./scripts/test-ui.sh` when you need the iPhone UI suite without the full two-device design check.
- **Report the test counts you observed**, and reconcile them against the baseline
  (546 unit / 54 UI on `main`). An unexplained drop is a stale runner or a
  concurrent run, not a pass.
- If you added tests, name one in your summary and confirm you saw it in the output.
- No new warnings or broken builds.
- If UI layout/snapshot tests fail, update only what’s necessary and keep the UI consistent.
- Add a `CHANGELOG.md` entry for the release you are working in.
- Provide a concise summary:
  - what changed
  - where it changed
  - how to manually verify

---

## Build / Test / Simulator Rules

> Everything in this section was learned the hard way and cost real hours. These
> are rules, not suggestions. The failure modes below all *look like product bugs*
> — that is exactly why they are expensive.

### 1. The simulator is a single shared resource — run exactly ONE `xcodebuild` at a time

Never start a build or test run while another one is in flight, whether it is
yours, another agent's, or a human's Xcode window. Check first; wait if something
is running.

Concurrent runs do **not** fail loudly. They produce false failures that read as
real bugs. Three distinct ones observed in a single day:
- a phantom pass reporting **"2 tests executed"** when the suite has hundreds;
- **"Test crashed with signal kill before establishing connection"** — a bootstrap
  crash, nothing to do with the code under test;
- CoreData **"Sandbox access to file-write-create denied"** — two runs fighting
  over the same container.

If you see any of those, do not debug the app. Establish that you are alone on the
simulator and re-run.

### 2. A suspiciously small test count means a stale runner, not a passing suite

If a UI run reports far fewer tests than expected **and no failures**, `xcodebuild`
reused an already-installed `PeakUITests-Runner.app` instead of the one it just
built. Nothing is wrong with your code and nothing was actually verified.

Fix: delete the runner from DerivedData (`.derivedData/` in the repo root) and
`xcrun simctl uninstall <udid> <runner bundle id>`, then re-run.

Corollary: **a test count you did not expect is a result you must explain.** Never
accept "it passed" from a run whose count dropped.

### 3. Neither `PeakTests` nor `PeakUITests` is a synchronized group

Only the iOS `Peak` folder is a `PBXFileSystemSynchronizedRootGroup`. A new file
dropped into `PeakTests/`, `PeakUITests/`, or `PeakWidgets/` is **invisible to the
build** until it has a `PBXFileReference`, a `PBXBuildFile`, and an entry in the
target's Sources phase. It does not error — the tests simply do not exist.

Two acceptable options:
- **Fold the new tests into an existing file** in that target (simplest, and
  usually right for a handful of cases).
- **Register the file with the `xcodeproj` ruby gem.** Do not hand-edit
  `project.pbxproj`: the project is `objectVersion = 77` and hand-editing reliably
  corrupts the synchronized root group, its exception sets, and the target's
  `fileSystemSynchronizedGroups` array — after which Xcode silently drops sources.
  `scripts/add-watch-tests.rb` on `feature/3.1-watchos` is a working, idempotent
  template.

**Then prove it ran.** Find the new test *by name* in the run output. A green run
is not evidence that your test executed.

### 4. UI-test scrolling: `isHittable` is not visibility, and swipes overshoot

- `isHittable` is true for an element whose frame merely **overlaps** the viewport.
  A field hanging off the bottom edge passes the check while a tap at its centre
  lands off-screen and silently fails to take focus. **Require the element's centre
  to be inside the scroll view** (with a small margin — a centre resting exactly on
  the edge is not reliably tappable).
- A swipe carries momentum: one can move this app's editor by **~670pt**, more than
  a phone viewport. A target can therefore travel from below the fold to above it
  between two checks. **A scroll loop must be able to reverse direction**, or it
  pins itself at the end of the content with the element existing but unreachable
  above, and burns its whole swipe budget.

The `scrollToVisible` / `isCentreVisible` helpers in each UI test class already do
both. Reuse them; do not write a fresh `while !isHittable { swipeUp() }` loop.

Related: a keyboard that silently stays up hides the bottom of the editor and makes
every later scroll spin against content it can never reach — which reads as a
broken control rather than a stuck keyboard. `dismissKeyboard` verifies dismissal
and falls back to the keyboard's own Done/Return key.

### 5. A fresh simulator raises an "Enable Dictation?" alert on first keyboard use

It is a **system** alert, so it steals taps from the app underneath: a stepper tap
lands on the alert instead of your control, and the test fails reporting a control
that "did nothing". A freshly created or erased simulator is exactly what CI gets.

`scripts/boot-sim.sh` pre-answers the first-run keyboard prompts so a fresh
simulator behaves like a warm one. **Keep that.** Do not remove it, and boot
through the script rather than `simctl boot` directly.

### Commands

Prefer **XcodeBuildMCP** tools when you need to build/test, boot/run simulators,
install/launch, stream logs, or capture screenshots/video — subject to rule 1.

If not using MCP tools, use repo scripts (do not invent custom `xcodebuild` commands):
- Boot simulator: `./scripts/boot-sim.sh`
- Build (sim): `./scripts/build-sim.sh`
- Fast unit tests only: `./scripts/test-unit.sh`
- Default test gate: `./scripts/test.sh`
- iPhone UI tests: `./scripts/test-ui.sh`
- iPhone + iPad UI/design check: `./scripts/design-check.sh`

Baseline on `main`: **546 unit tests, 54 UI tests.** If your run reports fewer,
re-read rules 1 and 2 before you believe it.

**Marketing screenshots.** `PeakMarketingCaptureTests` lives at the end of
`PeakUISmokeTests.swift` (folded in, per rule 3 above — a standalone file would
be invisible to the build). It is skipped unless the runner env carries
`PEAK_SHOT_DIR`, so it adds a *skipped* test to a normal run, not an executed
one. Regenerate a full App Store set with:

```bash
TEST_RUNNER_PEAK_SHOT_DIR=/tmp/peak-shots/iphone xcodebuild test \
  -project Peak.xcodeproj -scheme Peak -derivedDataPath .derivedData \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro Max' \
  -only-testing:PeakUITests/PeakMarketingCaptureTests \
  CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO
```

Note the `TEST_RUNNER_` prefix — a bare env var never reaches the test process.
iPhone 17 Pro Max yields 1320×2868 and iPad Pro 13-inch yields 2064×2752, which
are exactly the two sizes App Store Connect requires; `XCUIScreen` PNGs carry no
alpha, which Apple rejects. Upload with `asc screenshots upload --device-type
IPHONE_67` (the CLI aliases 6.9" onto the `APP_IPHONE_67` set) and
`IPAD_PRO_3GEN_129`.

**Known iPad breakage (2026-07-29):** 8 of the 54 UI tests fail on the iPad leg
of `design-check.sh` on current `main` (verified by stashing all local changes
and re-running — the failures are identical on a clean tree). Two clusters: a
"tab bar never appeared / Missing tab" group (PeakInsightsUITests ×4,
PeakEcosystemUITests ×2, PeakWindowCardUITests settings test) and
`testQuiverRowHitAreaFullWidth` (row hit area 688 pt vs expected ≥794 pt).
iPhone runs all 54 green. Do not attribute these to your diff; fixing them is
open work.

Project/scheme assumptions:
- App/UI scheme is `Peak`; `PeakUnit` is the fast unit-only scheme.
- Prefer `.xcworkspace` if present; otherwise use `Peak.xcodeproj`.
- DerivedData is `.derivedData/` in the repo root, not the Xcode default.

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

#### Schema rule (do not improvise around this)

Only the HEAD schema (currently `PeakSchemaV10`, `Schema.Version(1, 9, 0)`)
references the live `@Model` classes. Every earlier `PeakSchemaVn` is a **frozen
inline snapshot** of the shape it shipped with.

Therefore: **editing any live model field silently redefines the already-shipped
HEAD version** and can shunt a user's store into the recovery archive. Before
touching a field:

1. Freeze the outgoing HEAD as a new inline `Vn` snapshot — **in the same change
   as the real field delta.**
2. Add the new live-referencing HEAD carrying the delta, plus a `.lightweight`
   migration stage.
3. Point `PeakDataStore` at the new HEAD.
4. Update `ModelMigrationTests.testHeadSchemaShapeIsPinned` **deliberately** — it
   exists to make this decision explicit, so a diff to it is a signal, not noise.
5. Add both guards for the new version: a **shape-pin test** for the newly frozen
   snapshot (see `testFrozenV9SnapshotShapeIsPinned`) and an **on-disk round-trip
   migration test** that actually stages a store forward (see
   `testV9ToV10MigrationAddsWaveStatFieldsAsNil`).

**A no-op version bump is impossible.** SwiftData rejects two `VersionedSchema`s
that hash to the same shape ("duplicate version checksums"), so you cannot freeze
"in advance" as a tidy separate commit. Freeze and delta travel together, always.

New fields should be optional so the migration stays lightweight and old rows
migrate in as `nil`.

---

## Where to Put New Code (keep the repo organized)

- New SwiftUI screens: `Peak/Views/<Area>/...` (Log / History / Stats / More)
- Reusable UI components: `Peak/Views/Components/`
- Theme/styling helpers: `Peak/Supporting/Theme.swift` or `Peak/Supporting/GlassHelpers.swift`
- Calculators/formatters/helpers: `Peak/Supporting/`
- Models: `Peak/Models/`
- Unit tests: `PeakTests/`
- UI tests/snapshots: `PeakUITests/`
- Widget / Control Center / Live Activity UI: `PeakWidgets/`
- Anything shared with the widget extension must be `nonisolated` and free of
  SwiftData — the two targets do not share default actor isolation, and the
  extension must never open the store (see `Peak/ActiveSession.swift` for the pattern)

> **Only `Peak/` is a synchronized group.** A new file under `PeakTests/`,
> `PeakUITests/`, or `PeakWidgets/` is invisible to the build until it is
> registered in `project.pbxproj`. See rule 3 above.

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
- Tabs/shell: `Peak/ContentView.swift`, `Peak/Supporting/PeakNavigationCoordinator.swift`
- Models: `Peak/Models/*`
- Schema/helpers: `Peak/Supporting/ModelSchema.swift`, `Peak/Supporting/ModelContext+Helpers.swift`
- Log flow: `Peak/Views/Log/*` (`UnloggedWorkoutCard.swift` for Watch-surf import)
- History: `Peak/Views/History/*` (`SessionRouteMapView.swift` for HealthKit GPS overlay)
- Stats: `Peak/Views/Stats/*`, `Peak/Supporting/StatsCalculator.swift`
- More/Settings/Docs: `Peak/Views/More/*`
- Design system: `Peak/Supporting/Theme.swift`, `Peak/Supporting/GlassHelpers.swift`
- Components: `Peak/Views/Components/*`
- Conditions/tide: `Peak/Supporting/SurfConditionsService.swift`, `TideService.swift`
- Best Window Today: `Peak/Supporting/WindowScorer.swift`, `TodayWindowService.swift`, `Peak/Views/Today/*`
- Wave stats: `Peak/Supporting/WaveAnalyzer.swift`, `WaveStatsCalculator.swift`, `HealthKitService.swift`, `SpotProximity.swift`
- Insights: `Peak/Supporting/InsightsEngine.swift`, `FoundationModelsInsights.swift`
- Memory/goals: `Peak/Supporting/GearInsightsCalculator.swift`, `OnThisDayProvider.swift`, `YearInReviewCalculator.swift`, `MonthlyGoalCalculator.swift`
- First run/tips: `Peak/Views/Onboarding/WelcomeView.swift`, `Peak/Supporting/PeakTips.swift`
- Widget extension: `PeakWidgets/*` (widgets, Control Center control, Live Activity)
- App-Group shared state: `Peak/WidgetSnapshot.swift`, `Peak/Supporting/WidgetSnapshotWriter.swift`, `Peak/ActiveSession.swift`
- App Intents / Spotlight: `Peak/Supporting/AppIntentsEntities.swift`, `AppIntents+Peak.swift`, `SessionIntentQueries.swift`, `QuickLogIntents.swift`, `SpotlightIndexer.swift`
- Tests: `PeakTests/*`, `PeakUITests/*`
- CI: `.github/workflows/ci.yml`
- In-app docs: `Peak/Resources/Privacy.md`, `Peak/Resources/Support.md`
- Privacy manifest: `Peak/PrivacyInfo.xcprivacy`

### Targets and branches

- Shipping targets: `Peak`, `PeakWidgets`, `PeakTests`, `PeakUITests`.
- App Group `group.com.designprism.peak` is shared by `Peak` and `PeakWidgets`.
  It was registered in the Developer portal on 2026-07-29 — see `RELEASE_PLAYBOOK.md`.
- **`main`** is the development trunk. **`prod`** is a fast-forward-only git
  snapshot of the same SHA (App Store candidate ref). Pushing `prod` is not an
  App Store submit; store production remains App Store Connect. Never force-push
  either branch.
- The `3.1` watchOS companion (`PeakWatch`, `PeakWatchWidgets`, `PeakShared`) is
  **code-complete on `feature/3.1-watchos` and deliberately not merged**. It has
  never recorded a real surf. Do not merge it, ship it, or describe it as shipped;
  it lands only after real-device ocean testing validates the `WaveAnalyzer`
  constants against hand-counted sessions.

---

## Cursor Cloud specific instructions

Cursor Cloud agents for this repo currently boot a **Linux** VM. There is no
Xcode, no iOS Simulator, and no `xcodebuild`.

- Read, edit, commit, and push as usual.
- Do **not** treat a missing `./scripts/test.sh` run as a pass. The Definition of
  Done still requires `./scripts/test.sh` (and UI/design scripts when applicable)
  on a Mac host with Xcode, one `xcodebuild` at a time.
- Expected suite after the performance and library-UX passes: **546 unit / 54 UI**.
- Do not archive, notarize, or upload to App Store Connect from Cloud. Cut
  TestFlight / App Store builds on a Mac per `RELEASE_PLAYBOOK.md`.
- When asked to push to production, fast-forward `origin/prod` to the same SHA
  as `origin/main`. Do not force-push. Do not invent a deploy pipeline.
- `gh` in this environment is read-only. Use git + the pull-request tool to
  land branches; do not call `gh pr merge`.

---

## Out of Scope (unless explicitly requested)

- Social networks, feeds, follows, accounts, cloud sync/backends
  (exporting an image through the system share sheet — `SessionShareCard`,
  `RecapShareCard` — is *not* a social feature and is in scope)
- Any server-side model or remote inference
- New third-party SDKs
- Big architecture rewrites (MVVM overhaul, DI frameworks, etc.)
- Merging or shipping the `3.1` watchOS branch before real-device ocean testing
