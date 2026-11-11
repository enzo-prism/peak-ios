# Peak iOS release playbook

## Verified App Store state, November 11, 2026

- App `peak.surf`, bundle `com.designprism.peak`, ASC app `6757644027`, team `L49MKXGVM4`.
- **3.5 is public** (`READY_FOR_DISTRIBUTION` in ASC). Earlier candidate/pending statements in historical receipts do not describe current store state.
- **3.6 build 2** was waiting for review at the initial November 11 readback. **3.7 build 1** is the implementation candidate; preserve the old review until its tested replacement is ready, then replace it under the owner’s explicit authorization. Read back final lifecycle state and record it independently in `docs/releases/`.
- **Watch remains pending** by the owner's explicit choice. Standalone validation source stays on `feature/peak-3.6-watch-validation`, outside main; the iPhone archive must have no embedded Watch app.
- Git branches, simulator results and uploaded artifacts do not independently establish public availability. The owner explicitly authorized main, TestFlight and submission of the latest version to App Review on November 11. Public release remains manual.

## Source and build identity

Use an isolated branch/worktree for a candidate and preserve unrelated local edits. Reconcile release fixes into `main` through a reviewed PR with passing checks. Do not force-push or silently repoint `prod`. A release record must name the exact source SHA, version/build, ASC build ID, archive/export artifacts, verification evidence and submission/publication dates.

Create an immutable source tag only when its SHA-to-build mapping is established. Never infer an old build's source from today's branch pointer. Check the branch's marketing/build values across app and widget targets before an archive. Choose a new store version/build after re-reading ASC, rather than reusing historical numbers from this document.

The prepared Watch companion remains gated on physical Watch/ocean testing and excluded from the iPhone archive. Do not describe it as shipping or include it in store screenshots until a separately validated candidate embeds it. `feature/streamlined-log-session` is a historical divergent design branch and must not be used as a release source.

## Read-only status

Discover current flags with `--help` before using a command. On this Mac, `asc` is the release CLI.

```bash
asc versions list --app 6757644027 --platform IOS
asc status --app 6757644027
./scripts/asc-sync.sh latest-build
./scripts/gh-tooling.sh status
```

`asc validate` is useful while staging a candidate. An already-submitted `WAITING_FOR_REVIEW` version can fail submit-readiness validation because of its lifecycle state; that alone is not an App Review rejection.

## Candidate acceptance before upload

1. Record the source SHA and run one `xcodebuild` at a time. Use `./scripts/test-unit.sh` and relevant UI suites, including production iPad navigation when touched. Keep the actual result bundle/log and test count; historical counts do not prove current coverage.
2. Run the populated-device upgrade, backup/restore and Health checks in [SURFER_VALIDATION.md](docs/SURFER_VALIDATION.md). Distinguish synthetic migration fixtures, simulator UI coverage and physical device evidence. For 3.7, the paired iPhone has Developer Mode disabled; the owner explicitly chose Simulator validation and recording the physical-device limitation. No device backup was obtained or device install performed.
3. Reconcile README, architecture, changelog and release notes with the candidate's actual schema, user-facing behavior and test evidence. Never describe unrun device/ocean checks as passed.
4. Verify distribution signing/profiles and App Group access for **both** app and widget extension. The App Group `group.com.designprism.peak` was registered July 29. Past archives used manual signing; re-read current profile validity and build settings before selecting export options. Do not assume the tracked automatic-signing plist matches installed manual profiles.
5. Verify privacy/export-compliance answers against the actual binary. Current networking uses standard HTTPS; no telemetry SDK is added by Apple's analytics reporting request.
6. Review and merge the focused PR, then cut the archive from the exact accepted commit. If archiving a PR commit before merge, retain that SHA explicitly in the release record.

## Archive, TestFlight, review and publication

Discover each applicable command before running it:

```bash
asc builds next-build-number --help
asc xcode archive --help
asc xcode export --help
asc builds upload --help
asc builds wait --help
asc testflight --help
asc release --help
asc validate --help
```

Keep archives and export options under gitignored `.asc/artifacts/`, named with version and build. Archive → export with verified signing → upload the exact IPA → wait for that exact build's processing result → verify encryption compliance. Prefer explicit build IDs over `--latest`, which can select another concurrent upload.

TestFlight distribution, external invitations, review submission, cancellation and public release are separate actions. Prepare the exact build and recipient/version details before executing an authorized action. Verify persisted build/group/submission state afterward. Read current review lifecycle state before any review action; historical pending-version references are not authorization to change it.

For a new App Store candidate: prepare metadata and user-facing What's New, attach the verified build, validate, then submit through the current CLI flow. After approval, confirm release type and candidate acceptance before manual publication; finish with ASC and storefront readback.

## Reviewer notes template

- Offline-first surf log; no sign-in or demo credentials.
- Main path: Log → Log a finished surf → enter spot → Save → History and Stats.
- Spot name is sufficient; location/pins are optional.
- Apple Health is opt-in. Test unavailable/denied/no-route states without needing a Watch workout.
- Conditions are fetched when requested, or through the explicit opt-in automatic refresh setting.
- Photos use the system picker. Language-model features require supported hardware/OS and fall back to computed facts.
- Explain any new navigation or migration behavior specific to the candidate; do not paste old version notes unchanged.

## Release record template

```text
Version/build:
Source SHA / immutable tag / PR:
ASC version ID / build ID:
Archive path / IPA path / signing profile evidence:
Unit/UI results and count / result bundle:
Device upgrade / restore / Health / iPad results:
Known limitations:
Metadata and privacy checked:
Upload / processing / beta review / distribution receipts:
App Review submission / approval:
Release type / publication authorization / storefront readback:
```

## Apple analytics

An ONGOING analytics report request was created and read back September 4: `2877a158-bf47-458f-9c6d-92ea7bdb4928`, `stoppedDueToInactivity=false`. Retrieve on demand using `asc analytics requests` and `asc analytics view`; use `--reuse-existing` if re-establishing the request. This is Apple reporting, not an in-app analytics SDK. Full report retrieval initially timed out. A bounded retry with `ASC_TIMEOUT=90s` and `--limit 1` succeeded and returned an AirPlay Discovery Sessions report definition, with no instances shown. Usable usage/acquisition data has not been established. No recurring polling task was created.
