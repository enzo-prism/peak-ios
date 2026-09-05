import XCTest

@testable import Peak

final class SurfSessionTests: XCTestCase {
    func testNormalizedDurationSnapsAndClamps() {
        XCTAssertEqual(SurfSession.maxDurationMinutes, 480)
        XCTAssertEqual(SurfSession.durationStepMinutes, 5)

        XCTAssertNil(SurfSession.normalizedDuration(nil))
        XCTAssertNil(SurfSession.normalizedDuration(0))
        // Snaps to the nearest 5-minute step, never below one step.
        XCTAssertEqual(SurfSession.normalizedDuration(1), 5)
        XCTAssertEqual(SurfSession.normalizedDuration(8), 10)
        XCTAssertEqual(SurfSession.normalizedDuration(22), 20)
        XCTAssertEqual(SurfSession.normalizedDuration(23), 25)
        XCTAssertEqual(SurfSession.normalizedDuration(90), 90)
        // Long sessions are no longer clamped to 3 hours...
        XCTAssertEqual(SurfSession.normalizedDuration(179), 180)
        XCTAssertEqual(SurfSession.normalizedDuration(200), 200)
        XCTAssertEqual(SurfSession.normalizedDuration(477), 475)
        // ...but still cap at 8 hours.
        XCTAssertEqual(SurfSession.normalizedDuration(480), 480)
        XCTAssertEqual(SurfSession.normalizedDuration(481), 480)
        XCTAssertEqual(SurfSession.normalizedDuration(10_000), 480)
    }

    func testRatingClampsBetweenZeroAndFive() {
        let high = SurfSession(date: TestCalendar.makeDate(year: 2026, month: 2, day: 1), spot: nil, rating: 10)
        let low = SurfSession(date: TestCalendar.makeDate(year: 2026, month: 2, day: 1), spot: nil, rating: -2)

        XCTAssertEqual(high.rating, 5)
        XCTAssertEqual(low.rating, 0)
    }

    func testHasSurfConditionsReflectsValues() {
        let base = SurfSession(date: TestCalendar.makeDate(year: 2026, month: 2, day: 1), spot: nil)
        XCTAssertFalse(base.hasSurfConditions)

        base.windSpeedKph = 12
        XCTAssertTrue(base.hasSurfConditions)

        let sourceOnly = SurfSession(date: TestCalendar.makeDate(year: 2026, month: 2, day: 2), spot: nil)
        sourceOnly.conditionsSource = "Open-Meteo"
        XCTAssertTrue(sourceOnly.hasSurfConditions)
    }

    // MARK: - HealthKit pure logic (HKHealthStore not required)

    private func epoch(_ seconds: TimeInterval) -> Date {
        Date(timeIntervalSince1970: seconds)
    }

    func testSessionKeyIsStableAndMillisecondPrecise() {
        let base = epoch(1_700_000_000)
        // Deterministic, millisecond-scaled, prefixed.
        XCTAssertEqual(HealthKitLogic.sessionKey(forSessionCreatedAt: base), "peak-1700000000000")
        XCTAssertEqual(
            HealthKitLogic.sessionKey(forSessionCreatedAt: base),
            HealthKitLogic.sessionKey(forSessionCreatedAt: epoch(1_700_000_000))
        )
        // 1ms apart -> different keys.
        XCTAssertNotEqual(
            HealthKitLogic.sessionKey(forSessionCreatedAt: base),
            HealthKitLogic.sessionKey(forSessionCreatedAt: base.addingTimeInterval(0.001))
        )
        // Sub-millisecond jitter rounds to the same key.
        XCTAssertEqual(
            HealthKitLogic.sessionKey(forSessionCreatedAt: base),
            HealthKitLogic.sessionKey(forSessionCreatedAt: base.addingTimeInterval(0.0004))
        )
        XCTAssertEqual(HealthKitLogic.sessionKeyMetadataKey, "com.designprism.peak.sessionKey")
    }

    func testHealthWorkoutUUIDKeysAreStableAndDistinct() {
        let first = UUID(uuidString: "AAAAAAAA-AAAA-AAAA-AAAA-AAAAAAAAAAAA")!
        let second = UUID(uuidString: "BBBBBBBB-BBBB-BBBB-BBBB-BBBBBBBBBBBB")!
        XCTAssertEqual(HealthKitLogic.sessionKey(forSessionID: first),
                       "peak-session-aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa")
        XCTAssertEqual(HealthKitLogic.sessionKey(forSessionID: first),
                       HealthKitLogic.sessionKey(forSessionID: first))
        XCTAssertNotEqual(HealthKitLogic.sessionKey(forSessionID: first),
                          HealthKitLogic.sessionKey(forSessionID: second))
        XCTAssertNotEqual(HealthKitLogic.sessionKey(forSessionID: first),
                          HealthKitLogic.sessionKey(forSessionCreatedAt: epoch(1_700_000_000)))
    }

    func testLegacyHealthWorkoutRequiresSingleOwnerAndExactInterval() throws {
        let start = epoch(1_700_000_000)
        let match = try XCTUnwrap(HealthKitLogic.legacyWorkoutMatch(
            createdAt: start, date: start, durationMinutes: 60, matchingSessionCount: 1
        ))
        XCTAssertEqual(match.key, "peak-1700000000000")
        XCTAssertTrue(match.matches(start: start, end: start.addingTimeInterval(3600)))
        XCTAssertFalse(match.matches(start: start.addingTimeInterval(1), end: start.addingTimeInterval(3600)))
        XCTAssertFalse(match.matches(start: start, end: start.addingTimeInterval(3601)))
        for ownerCount in [0, 2, 3] {
            XCTAssertNil(HealthKitLogic.legacyWorkoutMatch(
                createdAt: start, date: start, durationMinutes: 60, matchingSessionCount: ownerCount
            ))
        }
        let durations: [Int?] = [nil, 0, -1]
        for duration in durations {
            XCTAssertNil(HealthKitLogic.legacyWorkoutMatch(
                createdAt: start, date: start, durationMinutes: duration, matchingSessionCount: 1
            ))
        }
    }

    func testHealthReplacementCreatesBeforeDeletingCapturedOldWorkouts() async throws {
        let old = UUID()
        let replacement = UUID()
        var events: [String] = []
        try await HealthKitLogic.replacePreservingOld(
            capture: { events.append("capture"); return [old, replacement] },
            create: { events.append("create"); return replacement },
            identifier: { $0 },
            delete: { values in
                events.append("delete")
                XCTAssertEqual(values, [old])
            }
        )
        XCTAssertEqual(events, ["capture", "create", "delete"])
    }

    func testHealthReplacementFailurePreservesOldWorkouts() async {
        enum ExpectedFailure: Error { case create }
        var deleted = false
        do {
            try await HealthKitLogic.replacePreservingOld(
                capture: { [UUID()] },
                create: { throw ExpectedFailure.create },
                identifier: { $0 },
                delete: { _ in deleted = true }
            )
            XCTFail("Expected create failure")
        } catch {}
        XCTAssertFalse(deleted)
    }

    func testHealthCaptureFailureNeverCreatesReplacement() async {
        enum ExpectedFailure: Error { case capture }
        var created = false
        do {
            try await HealthKitLogic.replacePreservingOld(
                capture: { () throws -> [UUID] in throw ExpectedFailure.capture },
                create: { created = true; return UUID() },
                identifier: { $0 },
                delete: { _ in XCTFail("Must not delete after failed capture") }
            )
            XCTFail("Expected capture failure")
        } catch {}
        XCTAssertFalse(created)
    }

    @MainActor
    func testHealthQueueFinishesOlderSaveBeforeDeleteEvenWhenSaveFails() async throws {
        enum ExpectedFailure: Error { case save }
        let queue = HealthWorkoutQueue()
        var events: [String] = []
        let save = queue.enqueue(key: "session") {
            events.append("save-start")
            await Task.yield()
            events.append("save-end")
            throw ExpectedFailure.save
        }
        let deletion = queue.enqueue(key: "session") { events.append("delete") }
        try await deletion.value
        _ = try? await save.value
        XCTAssertEqual(events, ["save-start", "save-end", "delete"])
    }

    func testImportedHealthWorkoutsAreNeverWrittenBackAsPeakWorkouts() {
        XCTAssertTrue(HealthKitLogic.shouldWriteWorkout(linkedWorkoutID: nil))
        XCTAssertTrue(HealthKitLogic.shouldWriteWorkout(linkedWorkoutID: ""))
        XCTAssertFalse(HealthKitLogic.shouldWriteWorkout(linkedWorkoutID: UUID().uuidString))
    }

    @MainActor
    func testEditorMediaFailedSaveKeepsOriginalAndDraftVideoAndCleansNewCopy() throws {
        enum ExpectedFailure: Error { case save }
        let source = FileManager.default.temporaryDirectory.appendingPathComponent("draft-\(UUID()).mov")
        let oldSource = FileManager.default.temporaryDirectory.appendingPathComponent("old-\(UUID()).mov")
        try Data("draft".utf8).write(to: source)
        try Data("original".utf8).write(to: oldSource)
        let original = try SessionMediaStore.storeVideo(from: oldSource, thumbnailData: nil)
        defer {
            SessionMediaStore.deleteTemporaryFiles([source, oldSource])
            SessionMediaStore.deleteVideoFile(named: original.fileName)
        }
        let changes = SessionMediaSaveTransaction()
        changes.removedVideoNames = [original.fileName]
        let staged = try changes.stageVideo(from: source, thumbnailData: nil)
        var rolledBack = false
        XCTAssertThrowsError(try changes.persist(save: { throw ExpectedFailure.save },
                                                rollbackModel: { rolledBack = true }))
        XCTAssertTrue(rolledBack)
        XCTAssertEqual(try Data(contentsOf: source), Data("draft".utf8))
        XCTAssertEqual(try Data(contentsOf: SessionMediaStore.videoURL(for: original.fileName)), Data("original".utf8))
        XCTAssertFalse(FileManager.default.fileExists(atPath: SessionMediaStore.videoURL(for: staged.fileName).path))
        // Retry uses the same still-usable draft source.
        let retry = SessionMediaSaveTransaction()
        let retried = try retry.stageVideo(from: source, thumbnailData: nil)
        defer { SessionMediaStore.deleteVideoFile(named: retried.fileName) }
        try retry.persist(save: {}, rollbackModel: { XCTFail("Successful retry must not roll back") })
        XCTAssertEqual(try Data(contentsOf: SessionMediaStore.videoURL(for: retried.fileName)), Data("draft".utf8))
    }

    @MainActor
    func testEditorMediaDeletesOriginalOnlyAfterSuccessfulModelSave() throws {
        let source = FileManager.default.temporaryDirectory.appendingPathComponent("draft-\(UUID()).mov")
        let oldSource = FileManager.default.temporaryDirectory.appendingPathComponent("old-\(UUID()).mov")
        try Data("draft".utf8).write(to: source)
        try Data("original".utf8).write(to: oldSource)
        let original = try SessionMediaStore.storeVideo(from: oldSource, thumbnailData: nil)
        let changes = SessionMediaSaveTransaction()
        changes.removedVideoNames = [original.fileName]
        let staged = try changes.stageVideo(from: source, thumbnailData: nil)
        defer {
            SessionMediaStore.deleteTemporaryFiles([source, oldSource])
            SessionMediaStore.deleteVideoFile(named: original.fileName)
            SessionMediaStore.deleteVideoFile(named: staged.fileName)
        }
        try changes.persist(save: {
            XCTAssertTrue(FileManager.default.fileExists(atPath: SessionMediaStore.videoURL(for: original.fileName).path))
            XCTAssertTrue(FileManager.default.fileExists(atPath: source.path))
        }, rollbackModel: { XCTFail("Successful save must not roll back") })
        XCTAssertFalse(FileManager.default.fileExists(atPath: SessionMediaStore.videoURL(for: original.fileName).path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: source.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: SessionMediaStore.videoURL(for: staged.fileName).path))
    }

    func testOverlapMatcherTreatsSharedBoundaryAsNonOverlapping() {
        let a = DateInterval(start: epoch(0), duration: 100)
        let touching = DateInterval(start: epoch(100), duration: 100)   // shares boundary at 100
        let overlapping = DateInterval(start: epoch(50), duration: 100)
        let disjoint = DateInterval(start: epoch(300), duration: 100)

        XCTAssertTrue(HealthKitLogic.overlaps(a, overlapping))
        XCTAssertFalse(HealthKitLogic.overlaps(a, touching))
        XCTAssertFalse(HealthKitLogic.overlaps(a, disjoint))

        XCTAssertTrue(HealthKitLogic.overlapsAny(overlapping, of: [touching, a]))
        XCTAssertFalse(HealthKitLogic.overlapsAny(disjoint, of: [a, touching]))
    }

    func testUnloggedWorkoutsExcludesPeakAuthoredAndOverlapping() {
        let peakAuthored = HealthKitLogic.WorkoutSummary(
            id: UUID(), start: epoch(0), end: epoch(3600), sourceName: "Peak", isFromPeak: true
        )
        let overlapping = HealthKitLogic.WorkoutSummary(
            id: UUID(), start: epoch(0), end: epoch(3600), sourceName: "Apple Watch", isFromPeak: false
        )
        let importable = HealthKitLogic.WorkoutSummary(
            id: UUID(), start: epoch(10_000), end: epoch(13_600), sourceName: "Apple Watch", isFromPeak: false
        )
        let sessionWindows = [DateInterval(start: epoch(0), duration: 3600)]

        let result = HealthKitLogic.unloggedWorkouts(
            from: [peakAuthored, overlapping, importable],
            sessionWindows: sessionWindows
        )

        XCTAssertEqual(result.map(\.id), [importable.id])
    }

    func testDraftValuesMapDateAndSnapDurationToFiveMinuteRule() {
        let start = epoch(1_700_000_000)

        let ninety = HealthKitLogic.draftValues(workoutStart: start, workoutEnd: start.addingTimeInterval(90 * 60))
        XCTAssertEqual(ninety.date, start)
        XCTAssertEqual(ninety.durationMinutes, 90)

        // 92 min rounds down to 90, 93 min rounds up to 95 (nearest 5).
        XCTAssertEqual(
            HealthKitLogic.draftValues(workoutStart: start, workoutEnd: start.addingTimeInterval(92 * 60)).durationMinutes,
            90
        )
        XCTAssertEqual(
            HealthKitLogic.draftValues(workoutStart: start, workoutEnd: start.addingTimeInterval(93 * 60)).durationMinutes,
            95
        )
        // Zero-length workout maps to no duration (never fabricated).
        XCTAssertNil(HealthKitLogic.draftValues(workoutStart: start, workoutEnd: start).durationMinutes)
    }

    func testWorkoutSummaryDerivesIntervalAndDuration() {
        let summary = HealthKitLogic.WorkoutSummary(
            id: UUID(), start: epoch(0), end: epoch(90 * 60), sourceName: "Apple Watch", isFromPeak: false
        )
        XCTAssertEqual(summary.durationMinutes, 90)
        XCTAssertEqual(summary.interval, DateInterval(start: epoch(0), end: epoch(90 * 60)))
    }

    // MARK: - Wave stats (3.0)

    /// Derived stats land on a session that has none, and stamp `.auto` so the
    /// UI knows to caveat them.
    func testApplyDerivedWaveStatsWritesAutoSource() {
        let session = TestFixture.session()
        let stats = WaveStats(
            waveCount: 9,
            topSpeedKph: 26.4,
            longestRideSeconds: 17.5,
            longestRideMeters: 82,
            paddleDistanceMeters: 1_320,
            totalDistanceMeters: 1_800,
            waves: []
        )

        XCTAssertTrue(session.applyDerivedWaveStats(stats, workoutID: "workout-1"))
        XCTAssertEqual(session.waveCount, 9)
        XCTAssertEqual(session.topSpeedKph ?? 0, 26.4, accuracy: 0.0001)
        XCTAssertEqual(session.longestRideSeconds ?? 0, 17.5, accuracy: 0.0001)
        XCTAssertEqual(session.longestRideMeters ?? 0, 82, accuracy: 0.0001)
        XCTAssertEqual(session.paddleDistanceMeters ?? 0, 1_320, accuracy: 0.0001)
        XCTAssertEqual(session.waveStats, .auto)
        XCTAssertEqual(session.linkedWorkoutID, "workout-1")
        XCTAssertTrue(session.hasWaveStats)
    }

    /// A skunked session is a real result: zero waves is stored, but the derived
    /// zeros for speed and ride length are stored as nil so the UI can omit those
    /// rows instead of printing an authoritative "0 km/h".
    func testApplyDerivedWaveStatsStoresZeroWavesButNilsEmptyMeasurements() {
        let session = TestFixture.session()
        session.applyDerivedWaveStats(.zero, workoutID: nil)

        XCTAssertEqual(session.waveCount, 0)
        XCTAssertNil(session.topSpeedKph)
        XCTAssertNil(session.longestRideSeconds)
        XCTAssertNil(session.longestRideMeters)
        XCTAssertNil(session.paddleDistanceMeters)
        XCTAssertTrue(session.hasWaveStats, "a zero-wave session still has wave stats")
    }

    /// The rule the whole feature rests on: once a human has vouched for the
    /// numbers, a re-import must not touch them.
    func testApplyDerivedWaveStatsRefusesToOverwriteEditedOrManualStats() {
        for source in [WaveStatsSource.edited, .manual] {
            let session = TestFixture.session()
            session.waveCount = 4
            session.waveStats = source

            let stats = WaveStats(
                waveCount: 11, topSpeedKph: 30, longestRideSeconds: 20,
                longestRideMeters: 100, paddleDistanceMeters: 900,
                totalDistanceMeters: 1_400, waves: []
            )
            XCTAssertFalse(
                session.applyDerivedWaveStats(stats, workoutID: "workout-2"),
                "\(source.rawValue) stats were overwritten"
            )
            XCTAssertEqual(session.waveCount, 4)
            XCTAssertEqual(session.waveStats, source)
        }
    }

    /// `force` exists for a deliberate user-initiated re-derive.
    func testApplyDerivedWaveStatsCanBeForcedOverEditedStats() {
        let session = TestFixture.session()
        session.waveCount = 4
        session.waveStats = .edited

        let stats = WaveStats(
            waveCount: 11, topSpeedKph: 30, longestRideSeconds: 20,
            longestRideMeters: 100, paddleDistanceMeters: 900,
            totalDistanceMeters: 1_400, waves: []
        )
        XCTAssertTrue(session.applyDerivedWaveStats(stats, workoutID: nil, force: true))
        XCTAssertEqual(session.waveCount, 11)
        XCTAssertEqual(session.waveStats, .auto)
    }

    /// Correcting a derived number makes it `edited`; typing one in from scratch
    /// with no workout behind it makes it `manual`.
    func testMarkWaveStatsEditedChoosesEditedOrManualByProvenance() {
        let derived = TestFixture.session()
        derived.waveStats = .auto
        derived.linkedWorkoutID = "workout-3"
        derived.markWaveStatsEdited()
        XCTAssertEqual(derived.waveStats, .edited)

        let fromScratch = TestFixture.session()
        fromScratch.markWaveStatsEdited()
        XCTAssertEqual(fromScratch.waveStats, .manual)

        // A session linked to a workout but with no derived stats yet still reads
        // as a correction of the route, not a from-scratch entry.
        let linkedButEmpty = TestFixture.session()
        linkedButEmpty.linkedWorkoutID = "workout-4"
        linkedButEmpty.markWaveStatsEdited()
        XCTAssertEqual(linkedButEmpty.waveStats, .edited)

        // Editing stays sticky.
        derived.markWaveStatsEdited()
        XCTAssertEqual(derived.waveStats, .edited)
        fromScratch.markWaveStatsEdited()
        XCTAssertEqual(fromScratch.waveStats, .manual)
    }

    func testClearWaveStatsRemovesEverything() {
        let session = TestFixture.session()
        session.applyDerivedWaveStats(
            WaveStats(
                waveCount: 6, topSpeedKph: 22, longestRideSeconds: 12,
                longestRideMeters: 60, paddleDistanceMeters: 800,
                totalDistanceMeters: 1_000, waves: []
            ),
            workoutID: "workout-5"
        )
        session.clearWaveStats()

        XCTAssertFalse(session.hasWaveStats)
        XCTAssertNil(session.waveStatsSource)
        XCTAssertNil(session.waveStats)
        XCTAssertNil(session.linkedWorkoutID)
    }

    /// A raw value from a future build must read as nil, not crash or corrupt.
    func testUnknownWaveStatsSourceReadsAsNil() {
        let session = TestFixture.session()
        session.waveStatsSource = "quantum-telemetry"
        XCTAssertNil(session.waveStats)
    }

    /// Wave stats are independent of the 2.8 conditions block; neither may leak
    /// into the other's "do I have anything to show" check.
    func testWaveStatsAndSurfConditionsAreIndependent() {
        let session = TestFixture.session()
        session.waveCount = 3
        XCTAssertTrue(session.hasWaveStats)
        XCTAssertFalse(session.hasSurfConditions)

        let other = TestFixture.session()
        other.seaLevelHeightM = 0.4
        XCTAssertTrue(other.hasSurfConditions)
        XCTAssertFalse(other.hasWaveStats)
    }

    // MARK: - Spot proximity + import (Watch surf → Peak session)

    func testSpotProximityPicksNearestWithinCap() {
        let sample = RouteSample(
            timestamp: Date(),
            latitude: 33.3820,
            longitude: -117.5880,
            horizontalAccuracyMeters: 5
        )
        let near = TestFixture.spot(name: "Trestles", latitude: 33.3850, longitude: -117.5880)
        let farther = TestFixture.spot(name: "San Onofre", latitude: 33.3950, longitude: -117.5880)

        let picked = SpotProximity.nearest(to: sample, in: [farther, near])
        XCTAssertEqual(picked?.name, "Trestles")
    }

    func testSpotProximityReturnsNilWhenTooFar() {
        let sample = RouteSample(
            timestamp: Date(),
            latitude: 33.3820,
            longitude: -117.5880,
            horizontalAccuracyMeters: 5
        )
        let far = TestFixture.spot(name: "Pipeline", latitude: 21.6650, longitude: -158.0530)

        XCTAssertNil(SpotProximity.nearest(to: sample, in: [far]))
    }

    func testSpotProximityIgnoresUnpinnedSpots() {
        let sample = RouteSample(
            timestamp: Date(),
            latitude: 33.3820,
            longitude: -117.5880,
            horizontalAccuracyMeters: 5
        )
        let unpinned = TestFixture.spot(name: "Trestles")
        XCTAssertNil(SpotProximity.nearest(to: sample, in: [unpinned]))

        let pinned = TestFixture.spot(name: "Lower Trestles", latitude: 33.3825, longitude: -117.5885)
        let picked = SpotProximity.nearest(to: sample, in: [unpinned, pinned])
        XCTAssertEqual(picked?.name, "Lower Trestles")
    }

    func testImportedSessionLinksWorkoutAndAppliesStats() {
        let workoutID = UUID()
        let workout = HealthKitLogic.WorkoutSummary(
            id: workoutID,
            start: epoch(1_700_000_000),
            end: epoch(1_700_000_000 + 90 * 60),
            sourceName: "Apple Watch",
            isFromPeak: false
        )
        let stats = WaveStats(
            waveCount: 7,
            topSpeedKph: 24,
            longestRideSeconds: 14,
            longestRideMeters: 70,
            paddleDistanceMeters: 900,
            totalDistanceMeters: 1_200,
            waves: []
        )
        let spot = TestFixture.spot(name: "Trestles", latitude: 33.382, longitude: -117.588)
        let session = HealthKitLogic.importedSession(workout: workout, stats: stats, spot: spot)

        XCTAssertEqual(session.linkedWorkoutID, workoutID.uuidString)
        XCTAssertEqual(session.spot?.name, "Trestles")
        XCTAssertEqual(session.waveCount, 7)
        XCTAssertEqual(session.topSpeedKph ?? 0, 24, accuracy: 0.0001)
        XCTAssertEqual(session.longestRideSeconds ?? 0, 14, accuracy: 0.0001)
        XCTAssertEqual(session.waveStats, .auto)
        XCTAssertEqual(session.durationMinutes, 90)
        XCTAssertEqual(session.date, epoch(1_700_000_000))
        XCTAssertEqual(session.notes, "Imported from Apple Health")
        XCTAssertTrue(session.hasWaveStats)
    }

    func testGuessSampleSkipsInvalidAccuracyAndPrefersMidRoute() {
        func sample(lat: Double, lon: Double, accuracy: Double) -> RouteSample {
            RouteSample(
                timestamp: Date(),
                latitude: lat,
                longitude: lon,
                horizontalAccuracyMeters: accuracy
            )
        }
        let parking = sample(lat: 33.3900, lon: -117.5880, accuracy: 8)
        let invalid = sample(lat: 33.3820, lon: -117.5880, accuracy: -1)
        let inWater = sample(lat: 33.3825, lon: -117.5885, accuracy: 5)
        let later = sample(lat: 33.3830, lon: -117.5890, accuracy: 6)

        XCTAssertNil(SpotProximity.guessSample(from: [invalid]))
        let guessed = SpotProximity.guessSample(from: [parking, invalid, inWater, later])
        XCTAssertEqual(guessed?.latitude, inWater.latitude)
        XCTAssertEqual(guessed?.longitude, inWater.longitude)

        let trestles = TestFixture.spot(name: "Trestles", latitude: 33.3825, longitude: -117.5885)
        let lot = TestFixture.spot(name: "The lot", latitude: 33.3900, longitude: -117.5880)
        let picked = SpotProximity.nearest(to: [parking, invalid, inWater, later], in: [lot, trestles])
        XCTAssertEqual(picked?.name, "Trestles")
    }
}
