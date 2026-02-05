import XCTest

@testable import Peak

final class StatsCalculatorTests: XCTestCase {
    func testSummaryCalculatesAverageAndTopItems() {
        let spotA = TestFixture.spot(name: "Trestles")
        let spotB = TestFixture.spot(name: "Ocean Beach")
        let gear = TestFixture.gear(name: "6'2\" Fish")
        let buddy = TestFixture.buddy(name: "Kai")

        let sessions = [
            TestFixture.session(date: TestCalendar.makeDate(year: 2026, month: 2, day: 1), spot: spotA, gear: [gear], buddies: [buddy], rating: 5),
            TestFixture.session(date: TestCalendar.makeDate(year: 2026, month: 2, day: 2), spot: spotA, gear: [], buddies: [], rating: 0),
            TestFixture.session(date: TestCalendar.makeDate(year: 2026, month: 2, day: 3), spot: spotB, gear: [], buddies: [], rating: 3)
        ]

        let summary = StatsCalculator.summarize(sessions: sessions, topLimit: 3)

        XCTAssertEqual(summary.totalSessions, 3)
        XCTAssertEqual(summary.averageRating, 4.0)
        XCTAssertEqual(summary.topSpots.first?.name, "Trestles")
    }

    func testTopItemsSortByNameOnTies() {
        let gearA = TestFixture.gear(name: "Alpha", kind: .board)
        let gearB = TestFixture.gear(name: "Beta", kind: .board)

        let sessions = [
            TestFixture.session(date: TestCalendar.makeDate(year: 2026, month: 2, day: 5), spot: nil, gear: [gearB]),
            TestFixture.session(date: TestCalendar.makeDate(year: 2026, month: 2, day: 6), spot: nil, gear: [gearA])
        ]

        let summary = StatsCalculator.summarize(sessions: sessions, topLimit: 2)

        XCTAssertEqual(summary.topGear.map(\.name), ["Alpha", "Beta"])
    }
}
