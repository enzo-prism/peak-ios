# Peak surfer validation kit

Prepared 2026-09-04. Release acceptance is owner-led; external recruitment is optional future product research, not a release requirement. This is an execution kit; recruitment, device upgrades, and ocean testing have not been performed.

## Current release and device evidence

ASC app `6757644027`: 3.2 is `READY_FOR_SALE`; 3.3 is `WAITING_FOR_REVIEW`, release type `MANUAL`. A new reliability build is a separate candidate and does not change the pending binary.

Read-only `xcrun devicectl list devices` found Enzo's iPhone 17 Pro **available (paired)** and iPhone 15 Pro **unavailable**. No iPad or Apple Watch appeared. Availability does not establish installed Peak version, a populated library, usable signing, or Health permission. No device was installed to, launched, or modified during discovery.

## Optional future research with 5–10 surfers

Choose a mix of 2–3 frequent surfers, 2–3 occasional surfers, at least two people with multiple boards, and 2–3 Apple Watch workout users; categories may overlap. Include a novice logbook user and, if possible, an iPad user. Identify volunteers directly; do not scrape contacts or health records. Use participant codes S01–S10 in research notes and keep contact details separately.

Draft message, ready for Enzo to personalize and send:

> Hey [name], I'm improving Peak, my private surf log app. Would you be up for trying it over your next two or three surfs? I'd love to watch you log one session, then hear what felt useful or annoying after you've used it a few times. It takes about 15 minutes to get started. No need to share your exact spots or health data. If you're interested, I'll send the install details and we can pick a time.

Do not send an unverified TestFlight link. Select a tested build, verify group/build access and external beta-review status, then prepare invitations for the agreed participants. This kit does not enroll or message anyone.

## Session protocol

Allow 15–20 minutes for first use and a short follow-up after the next 2–3 surf opportunities, typically within 14 days. Extend the window for flat conditions; a week without surfing is not a retention failure.

1. Explain the purpose and ask consent before observing or recording. Participant may use approximate spots and omit Health/media. Let them complete onboarding without coaching.
2. Say: "Log your last surf however you normally remember it." Time from opening Log to saving. Observe missing information, backtracking, and prompts for help. Verify the saved session appears in History.
3. Say: "Add another session at the same spot with the same board." Time it separately; observe whether recent setup, spot, and gear reuse are discoverable.
4. Ask them to find the first session, correct one detail, and confirm their board history. Ask what they believe the Board Report means. Sparse data should remain an honest empty state.
5. Offer Health import only to participants already using surfing workouts and comfortable opting in. Check missing permission/no route, a real import, re-import, and preservation of a manual correction. Record outcomes, never raw heart rate or GPS traces by default.
6. Have them use Peak after their next 2–3 actual surf opportunities. Ask once at the agreed follow-up: sessions surfed, sessions logged, what caused a skipped log, and what they returned to see.
7. End with: "What would you miss if Peak disappeared?" and "What was the most frustrating moment?" Separate observed behavior from suggestions.

## Decision rules

These are proposed pilot criteria, not statistical claims. Record denominators and actual surf opportunities; do not infer cohort retention from App Store downloads.

| Measure | Pilot target / interpretation |
|---|---|
| First log | At least 80% finish unassisted; median within 60 seconds, optional enrichment timed separately |
| Repeat log | At least 80% finish unassisted; median within 30 seconds |
| Data trust | Zero unexplained missing sessions, wrong-session opens, lost associations, or overwritten manual values |
| Reuse | At least 60% of participants with two later surf opportunities log both without reminders |
| Board value | At least three multi-board surfers can explain a useful comparison or why there is insufficient data |
| Health | All attempted imports preserve editable/manual values; failures state what was unavailable without invented stats |

Data-trust failures block a release and take priority over timing. If repeat-log friction recurs across at least three participants, fix the observed step before expanding features. Treat small-sample percentages as directional; report numerator/denominator and quotes.

## Recording template

Copy one block per participant. Store locally; share anonymized summaries.

```text
Participant code:
Date / app version (build) / device / iOS:
Surf frequency / board count / Watch-workout experience:
Observation consent / recording consent (separate):
First log: seconds / assisted? / saved and found? / friction:
Repeat log: seconds / assisted? / setup reused? / friction:
Edit/detail: correct session? / change persisted after relaunch?:
Board insight: interpretation / insufficient-data behavior:
Health attempt: opt-in? / permission state / route available? / result:
Later actual surf opportunities: __ ; sessions logged: __
Reason for each skipped log:
Observed behavior:
Exact anonymized quote:
Suggested feature (not yet prioritized):
Bug: steps / expected / actual / severity / evidence filename:
Follow-up conclusion / next action:
```

## Populated-device upgrade and restore gate

Run on an agreed test device and a recoverable copy of data. Do not replace the owner's only logbook as a test.

- [ ] Record device/iOS, installed 3.2 build, candidate build and source SHA. Confirm candidate signing and install path before starting.
- [ ] In 3.2, export a full media-inclusive backup to a second location and validate it on a separate test installation. Record counts for sessions, spots, boards/gear, buddies, photos, and videos; record representative relationship sets, ratings, notes and Health links. JSON alone is not a media backup.
- [ ] Include shared gear/buddies across multiple sessions, empty optional fields, media, and an old-date session. Exercise duplicate creation timestamps using synthetic fixtures, not edits to personal data.
- [ ] Upgrade 3.2 → submitted 3.3 separately from 3.3 → new reliability candidate. Both paths matter; install over existing data without deleting the app.
- [ ] Reopen twice; compare counts and representative values, shared associations, media playback and stats. Verify edits and new sessions persist.
- [ ] On a separate scratch installation, restore legacy JSON and `.peakbackup` in merge mode twice; confirm documented deduplication and preservation of distinct sessions. Test replace only after a verified recoverable backup.
- [ ] Verify UUID-bearing exports/backups survive round trips; ambiguous legacy timestamp references must never open the wrong session.
- [ ] Confirm Last Session widget, Siri/Spotlight, and new deep links open the correct detail. Delete a synthetic session, rename synthetic gear/spot, and confirm stale search entries disappear after index refresh.
- [ ] Run production iPad sidebar/split navigation on a physical iPad in portrait, landscape and multitasking. Test History/Search, Quiver, Spots, back navigation, edits, deletion and external detail links. Confirm Dynamic Type and VoiceOver labeling.
- [ ] Confirm recovery diagnostics accurately distinguish complete preservation from file-move failure; do destructive fault injection only against scratch stores.

Record each check as PASS / FAIL / BLOCKED with build, OS, evidence, and owner. No blank or unrun check counts as passing.

## HealthKit and ocean gates

Health checks need an opted-in iPhone and an existing surfing workout. Verify denied access, no route, real route import, manual corrections preserved after re-import, route display, opt-out behavior, and duplicate prevention. OS permission prompts and real background delivery require device evidence.

Keep `feature/3.1-watchos` separate until it records at least five real surf sessions. Include a short session, longer session, gaps/poor GPS, pause/resume, and phone left behind. For each record Watch/OS/build, duration, battery before/after, manual wave count, analyzer count, obvious false positives, save/sync outcome, Water Lock behavior, and interruptions. Compare counts alongside the track-quality notes; agree acceptable error before tuning, then validate changed constants on held-out sessions. Synthetic-route unit tests do not establish ocean accuracy.

## Exact remaining inputs

| Gate | Required input |
|---|---|
| Real upgrade | Confirm the available iPhone 17 Pro may be used, its installed Peak version, and a backed-up test library; provide a second/scratch installation for restore verification |
| Physical iPad | Connect/pair an iPad and identify OS plus a safe test library |
| Health | Volunteer/device owner consent and a real existing surfing workout; confirm Apple Watch access if new workouts are needed |
| Optional research | Names/contact destinations for 5–10 willing surfers, an approved tested install build/link, and permission for the exact invitations |
| Ocean | Paired physical Watch, test-build installation, and five actual surf opportunities with manual notes |
| Store publication | Apple approval plus the final release decision after the candidate-specific gates; current 3.3 remains manual |

## Apple analytics, without an in-app SDK

Created an `ONGOING` request using `asc analytics request --app 6757644027 --access-type ONGOING --reuse-existing`. Persisted readback confirmed request `2877a158-bf47-458f-9c6d-92ea7bdb4928`, `accessType=ONGOING`, `stoppedDueToInactivity=false`. This enables Apple's reporting request; no app telemetry SDK, account, or Health upload was added.

Read available reports on demand with:

```bash
asc analytics requests --app 6757644027 --request-id 2877a158-bf47-458f-9c6d-92ea7bdb4928
asc analytics view --request-id 2877a158-bf47-458f-9c6d-92ea7bdb4928
```

The initial full report retrieval timed out. A bounded retry (`ASC_TIMEOUT=90s`, `--limit 1`) returned an AirPlay Discovery Sessions report definition without instances; usable acquisition/usage data is not established. Report availability, privacy thresholds and opt-in coverage can limit small samples. Use Apple reports for acquisition/usage context and the consented pilot for actual logging success and surf-opportunity denominators. No recurring task has been scheduled.
