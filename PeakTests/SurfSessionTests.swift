import XCTest

@testable import Peak

final class SurfSessionTests: XCTestCase {
    func testNormalizedDurationSnapsAndClamps() {
        XCTAssertNil(SurfSession.normalizedDuration(nil))
        XCTAssertNil(SurfSession.normalizedDuration(0))
        XCTAssertEqual(SurfSession.normalizedDuration(1), 15)
        XCTAssertEqual(SurfSession.normalizedDuration(8), 15)
        XCTAssertEqual(SurfSession.normalizedDuration(22), 15)
        XCTAssertEqual(SurfSession.normalizedDuration(23), 30)
        XCTAssertEqual(SurfSession.normalizedDuration(179), 180)
        XCTAssertEqual(SurfSession.normalizedDuration(200), 180)
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
