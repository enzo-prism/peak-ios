# Workspace guidance, September 4, 2026

AGENTS.md is managed; do not edit it. Its historical status and test-count statements are superseded by current source and verification evidence in README.md, ARCHITECTURE.md, RELEASE_PLAYBOOK.md and docs/.

- Live ASC readback: 3.2 public; 3.3 waiting for review with manual release. Git prod is not public-store state.
- The 3.4 build 1 reliability follow-up uses schema V12 (1.11.0); freeze released schema snapshots and test every migration stage. Submitted 3.3 uses V11.
- Historical 546/54 counts are not the current gate. Preserve actual candidate result bundles, verify executed test counts and distinguish simulator from device/ocean coverage.
- Production iPad navigation is enabled by default in UI tests; legacy flow tests opt into UITESTS_CLASSIC_NAVIGATION=1. Always run production-navigation coverage for sidebar/split changes.
- Only the Peak app source group is synchronized. Register new PeakTests, PeakUITests and PeakWidgets files in the project.
- Keep one xcodebuild active at a time; coordinate with other agents before running it.
- See docs/SURFER_VALIDATION.md for the prepared pilot and uncompleted physical-device inputs. Apple analytics reporting adds no in-app telemetry SDK.
