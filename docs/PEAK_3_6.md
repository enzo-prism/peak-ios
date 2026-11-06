# Peak 3.6 implementation and acceptance

Candidate: **3.6 (1)**, prepared November 6, 2026 from the 3.5 main baseline `0b3da2fcedb67be8ae1f9c404ce04bbf2f4f7438`. App Store Connect reports 3.5 as public. This document describes source behavior; the release receipt records upload and distribution independently.

The owner authorized implementation, main and TestFlight, and explicitly kept the Watch release gate pending. Watch hardening is retained on `feature/peak-3.6-watch-validation` outside main, following the repository's no-merge gate. The original imported checkout's unrelated edits are preserved. There is no schema migration in 3.6: V12 and the existing session UUIDs and media associations remain authoritative. Minimum iOS stays 17; no backend, account, analytics SDK, cloud inference or automatic library scanning was added.

## Ten improvements

| Area | Implemented behavior | Verification boundary |
| --- | --- | --- |
| Post-surf logging | Debounced, recoverable new-session drafts including media; optional iOS 26 on-device speech; review known spot/setup and explicit duration/rating before applying | Parser, recovery identity/video and typed-review UI tested. Wind/noise recognition and physical microphone interruptions still need hardware acceptance. |
| Quiver | Comparable single-board cohorts by spot, size and period, source records, minimum sample and uncertainty gates | Deterministic cohort/tie/separation tests and comparison UI. Observational ratings do not prove causality. |
| Watch | Separate validation-branch target with interrupted-workout recovery, paused timing, serialized route writes, honest Health save outcomes and retryable handoff | Pure shared tests and generic watchOS Simulator build. **Not embedded or distributed. Five reference ocean sessions and battery/GPS/transfer acceptance pending.** |
| Surf plan | Save a Best Window setup, inspect freshness, open source surf, compare boards and log setup only; explicitly confirmed NOAA station high/low predictions | Expiry and no-forecast-copy tests. NOAA MLLW stays separate from model MSL. Nearby station suitability requires the surfer's judgment. |
| Ask Peak | Exact bounded questions for counts, board usage and matching sessions; optional iOS 27 SpotlightSearchTool related-memory retrieval, rendering live IDs only | Exact grammar/unsupported criteria tests and UI. Model output cannot supply displayed facts; actual retrieval relevance needs supported-device evaluation. |
| System actions | Start Surf with Setup intent, preserved running clock, selected gear at end review, small/medium saved-plan widget with cached time/expiry | Entity validation and app/widget expiry tests. Siri/locked-phone/cross-process system invocation still needs device acceptance. |
| Replay | Select estimated rides, scrub actual time/speed samples, separate bad fixes/gaps, hide a preview detection and edit durable summary estimates | Synthetic route gap/sample tests. No route coordinates persisted. Detector accuracy remains unvalidated in the ocean. |
| Memories | Month/spot browsing of real sessions, photos and notes; selected Journaling Suggestions photos into the draft on supported iPhones | Browse/detail UI and media import lifecycle. Real suggestion availability/usefulness needs device checks. No automatic workout import or inferred facts. |
| Recoverability | Streaming framed v2 full backup, checksums and strict completeness checks, inspect before merge/replace, cancellation, Files destination readback and visible saved-backup date | Corruption/truncation/missing video, 64 MiB video round trip, cancellation and real simulator Files-save UI. Legacy backups still read. Physical-device/provider memory budget remains to measure. |
| Responsive edits | Preserve store-free primary selections through context retirement; source records route to History; avoid History-wide media prefetch; chunk private indexing; cache replay samples | Edit/detail UI and a 10,000-session calculator/query benchmark. ResultsObserver probe demonstrated stale held models, so correctness-preserving context replacement stays. Whole-app launch/scroll memory and latency require physical traces. |

## Apple API choices

- [SpeechAnalyzer](https://developer.apple.com/documentation/speech/speechanalyzer) and SpeechTranscriber are optional and on-device. The first recording can install Apple speech assets after disclosure; no server fallback. Audio is removed after use or next launch after an interruption.
- [Journaling Suggestions](https://developer.apple.com/documentation/journalingsuggestions) is a selected-content iPhone picker, not photo-library discovery. The distribution profile must explicitly include `com.apple.developer.journal.allow = [suggestions]`.
- [SpotlightSearchTool](https://developer.apple.com/videos/play/wwdc2026/246/) is separately availability-gated. Semantic retrieval finds examples; exhaustive counts always use exact code. Model prose is discarded rather than trusted. The tool uses [focused guidance](https://developer.apple.com/documentation/corespotlight/spotlightsearchtool/guide) with 20 results and 4,000 output characters for the smaller on-device context.
- [ResultsObserver](https://developer.apple.com/documentation/swiftdata/resultsobserver) was prototyped and rejected as a replacement for context retirement: it notifies but does not refresh the existing library's held models. `ModernStoreObservationTests` pins the observed SDK behavior.
- Existing MapKit, Charts, WidgetKit and App Intents support the workflows without another weather service or a backend. Optional new system schema, landscape Live Activity and AppIntentsTesting work is not claimed as delivered. Cross-process device acceptance remains explicit.
- The system URL-based Files exporter is used after the SwiftUI Transferable exporter crashed on iOS 27.0 with a nil FileWrapper preferred filename. The replacement saves the already-verified URL, then verifies the returned destination before recording success.

## Test evidence

The 3.5 baseline had 615 unit and 67 UI cases. The combined development branch passed 669 unit cases, including 30 Watch-only cases. Those 30 remain on the separate Watch validation branch. The iPhone gate adds filter-restoration, legacy-backup metadata, autosave undo, compound-duration and conflicting-date regressions after the split, bringing it to 644 cases. The 3.6 source discovers 644 unit cases on Xcode 27, 643 on Xcode 26.6 (the SDK 27 ResultsObserver probe is unavailable there), and 73 UI cases per device. Record actual pass/skip/failure counts, SDK/device and source SHA in the release receipt. Failed intermediate runs are diagnostic evidence, never passing release gates.

Named regression coverage includes `testDraftRecoveryPreservesCorrectionsAndMediaAndClearWinsOverLateSave`, `testQuiverAdvisorAbstainsOnTieAndSuggestsSeparatedCohort`, `testReplayNeverConnectsAcrossBadFixesOrTimeGaps`, `testFramedBackupChecksumsAndTruncationFailBeforeReplace`, `testLargeVideoStreamsThroughVerifiedBackupAndRestore`, `testResetSaveFailureKeepsLibraryAndVideoThenSuccessfulRetryDeletesBoth`, and the UI case `testVerifiedBackupSavesToFilesAndVerifiesDestination`.

The media-free 10,000-session exact-query/comparison/entity benchmark measured approximately 92 ms average and 93 MB peak in the simulator. It is not a whole-app or physical-device performance result. A 64 MiB video fixture establishes streaming correctness, not a maximum supported library or device memory budget.

Run one Xcode build at a time:

```bash
DESTINATION_NAME='iPhone 18 Pro' ./scripts/test.sh
IPHONE_DESTINATION_NAME='iPhone 18 Pro' IPAD_DESTINATION_NAME='iPad Pro 13-inch (M5)' ./scripts/design-check.sh
# On feature/peak-3.6-watch-validation only:
./scripts/build-watch-sim.sh
```

## Manual acceptance

1. Back up a populated device before replacing its installed app. Upgrade, inspect old relationships/media, export, inspect, merge twice and restore a copy using [SURFER_VALIDATION.md](SURFER_VALIDATION.md). Never erase the owner's logbook to test.
2. Create an unfinished session with photo/video, background and relaunch, resume and save or discard. Record a transcript, deny permission, interrupt, cancel and verify no unintended field or session was saved.
3. Compare boards with sparse and adequate data; inspect sources. Ask supported and unsupported questions. On eligible hardware evaluate related-memory relevance, deletion and adversarial notes; no generated numeric answers should appear.
4. Save/expire a plan, remove a referenced entity and invoke the widget/shortcut with a running timer. Check cold/warm/locked-phone behavior without claiming constant forecast updates.
5. Choose and dismiss real Journaling Suggestions; import selected photos and confirm nothing saves until the session is saved.
6. Inspect a real gappy Health route and verify manually edited wave totals survive re-import. Measure physical-device launch, scroll, edit/save and backup memory at 1,000/10,000 sessions with representative media.
7. Keep Watch distribution pending until five documented ocean sessions establish precision/recall, count error, battery, route gaps and recoverable transfer behavior.

TestFlight is the channel for these remaining physical-device checks. Uploading a build is not App Review submission or public release, and does not establish any of these unrun results.
