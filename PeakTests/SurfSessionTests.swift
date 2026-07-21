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
}
