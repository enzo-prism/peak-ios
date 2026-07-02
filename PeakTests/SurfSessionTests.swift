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
}
