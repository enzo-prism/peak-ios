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
}
