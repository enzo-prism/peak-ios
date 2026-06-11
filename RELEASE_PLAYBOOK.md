# Peak iOS Release Playbook

## Current state (as of June 11, 2026)
- App: `peak.surf` (`com.designprism.peak`)
- App ID: `6757644027`
- Public App Store version: `1.9` (approved; train closed for new builds)
- Next release train: `2.0`
- `2.0 (1)` uploaded to App Store Connect on June 11, 2026 (performance + HIG improvements)

## 30-second status check
Run:

```bash
./scripts/release-cli.sh 2.0 IOS
./scripts/asc-sync.sh status
./scripts/asc-sync.sh latest-build
./scripts/asc-sync.sh next-build 2.0 IOS
./scripts/gh-tooling.sh status
```

## If App Review rejects `1.9`
1. Pull rejection details and snapshot current state:
```bash
./scripts/asc-sync.sh snapshot
```
2. Create a focused fix branch and implement only review-blocking changes.
3. Validate locally:
```bash
./scripts/test.sh
```
4. Confirm the next build number (should be `4` unless a newer upload already exists):
```bash
./scripts/asc-sync.sh next-build 2.0 IOS
```
5. Archive/upload from Xcode or your upload path, then re-submit `1.9`.
6. Re-check status immediately after upload:
```bash
./scripts/asc-sync.sh latest-build
./scripts/asc-sync.sh status
```

## If App Review approves `1.9`
1. Record approval date and build number in release notes/changelog.
2. Start the next train (`2.0` or the next planned version) on a fresh branch with CI green before upload.
