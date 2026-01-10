import XCTest

@testable import Peak

final class GearUsageCalculatorTests: XCTestCase {
    func testGearUsageSummaryAndTopSpots() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0) ?? .current

        let referenceDate = calendar.date(from: DateComponents(year: 2026, month: 3, day: 15, hour: 12))!
        let janDate = calendar.date(from: DateComponents(year: 2026, month: 1, day: 10, hour: 8))!
        let febDate1 = calendar.date(from: DateComponents(year: 2026, month: 2, day: 5, hour: 8))!
        let febDate2 = calendar.date(from: DateComponents(year: 2026, month: 2, day: 20, hour: 8))!

        let gear = Gear(name: "6'2\" Fish", kind: .board)
        let spotA = Spot(name: "Trestles")
        let spotB = Spot(name: "Ocean Beach")

        let session1 = SurfSession(date: janDate, spot: spotA, gear: [gear], rating: 5)
        let session2 = SurfSession(date: febDate1, spot: spotA, gear: [gear], rating: 3)
        let session3 = SurfSession(date: febDate2, spot: spotB, gear: [gear], rating: 0)

        let summary = GearUsageCalculator.summary(
            for: gear,
            sessions: [session1, session2, session3],
            calendar: calendar,
            referenceDate: referenceDate
        )

        XCTAssertEqual(summary.totalUses, 3)
        XCTAssertEqual(summary.firstUsed, janDate)
        XCTAssertEqual(summary.lastUsed, febDate2)
        XCTAssertEqual(summary.averageRating, 4.0)
        XCTAssertEqual(summary.topSpots.first?.name, "Trestles")
        XCTAssertEqual(summary.topSpots.first?.count, 2)
        XCTAssertEqual(summary.topSpots.count, 2)

        let january = calendar.date(from: DateComponents(year: 2026, month: 1))!
        let february = calendar.date(from: DateComponents(year: 2026, month: 2))!
        let janCount = summary.monthlyCounts.first(where: { $0.month == january })?.count
        let febCount = summary.monthlyCounts.first(where: { $0.month == february })?.count

        XCTAssertEqual(janCount, 1)
        XCTAssertEqual(febCount, 2)
    }

    func testGearPolicyRequiresArchiveWhenUsed() {
        let gear = Gear(name: "Step-Up", kind: .board)
        let session = SurfSession(date: Date(), spot: nil, gear: [gear], rating: 4)

        let policy = GearUsageCalculator.policy(for: gear, sessions: [session])

        XCTAssertFalse(policy.canDelete)
        XCTAssertTrue(policy.canArchive)
    }

    func testGearPolicyAllowsDeleteWhenUnused() {
        let gear = Gear(name: "Spare Leash", kind: .leash)
        let policy = GearUsageCalculator.policy(for: gear, sessions: [])

        XCTAssertTrue(policy.canDelete)
        XCTAssertFalse(policy.canArchive)
    }
}
