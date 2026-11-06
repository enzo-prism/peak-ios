# Workspace guidance, November 6, 2026

AGENTS.md is managed; do not edit it. Its historical status and test-count statements are superseded by current source and verification evidence in README.md, ARCHITECTURE.md, RELEASE_PLAYBOOK.md and docs/.

- Live ASC readback November 6: 3.5 public. 3.6 (2) is the current candidate; read its release receipt for verified TestFlight state. Git prod is not public-store state.
- The 3.4 build 1 reliability follow-up uses schema V12 (1.11.0); freeze released schema snapshots and test every migration stage. Submitted 3.3 uses V11.
- The iPhone 3.6 gate discovers 644 unit cases with Xcode 27 (643 with Xcode 26.6) and 75 UI cases per device. The separate Watch validation branch adds 30 pure cases and remains outside main until the ocean gate. Historical 546/54 counts are not the current gate. Preserve actual candidate result bundles, verify executed test counts and distinguish simulator from device/ocean coverage.
- Production iPad navigation is enabled by default in UI tests; legacy flow tests opt into UITESTS_CLASSIC_NAVIGATION=1. Always run production-navigation coverage for sidebar/split changes.
- Only the Peak app source group is synchronized. Register new PeakTests, PeakUITests and PeakWidgets files in the project.
- Keep one xcodebuild active at a time; coordinate with other agents before running it.
- See docs/SURFER_VALIDATION.md for the prepared pilot and uncompleted physical-device inputs. Apple analytics reporting adds no in-app telemetry SDK.
