import XCTest

@testable import Peak

final class UsageMetricsTests: XCTestCase {
    func testUsageMetricsSummaries() {
        let calendar = Calendar(identifier: .gregorian)
        let date1 = calendar.date(from: DateComponents(year: 2026, month: 2, day: 1, hour: 6))!
        let date2 = calendar.date(from: DateComponents(year: 2026, month: 3, day: 5, hour: 6))!

        let spot = Spot(name: "Trestles")
        let board = Gear(name: "6'2\" Fish", kind: .board)
        let buddy = Buddy(name: "Kai")

        let session1 = SurfSession(date: date1, spot: spot, gear: [board], buddies: [buddy], rating: 4)
        let session2 = SurfSession(date: date2, spot: spot, gear: [board], buddies: [buddy], rating: 2)

        let snapshots = UsageMetricsCalculator.gearSnapshots(sessions: [session1, session2])
        let snapshot = snapshots[board.key]

        XCTAssertEqual(snapshot?.count, 2)
        XCTAssertEqual(snapshot?.lastUsed, date2)
        XCTAssertEqual(snapshot?.averageRating, 3.0)
    }

    func testSurfDaysThisYearCountsUniqueDays() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0) ?? .current

        let referenceDate = calendar.date(from: DateComponents(year: 2026, month: 4, day: 20, hour: 12))!
        let day1 = calendar.date(from: DateComponents(year: 2026, month: 1, day: 5, hour: 8))!
        let day1Later = calendar.date(from: DateComponents(year: 2026, month: 1, day: 5, hour: 16))!
        let day2 = calendar.date(from: DateComponents(year: 2026, month: 2, day: 10, hour: 7))!
        let lastYear = calendar.date(from: DateComponents(year: 2025, month: 12, day: 31, hour: 7))!

        let sessions = [
            SurfSession(date: day1, spot: nil),
            SurfSession(date: day1Later, spot: nil),
            SurfSession(date: day2, spot: nil),
            SurfSession(date: lastYear, spot: nil)
        ]

        let summary = StatsCalculator.surfDaysThisYear(
            sessions: sessions,
            referenceDate: referenceDate,
            calendar: calendar
        )

        XCTAssertEqual(summary.totalDays, 2)

        let january = calendar.date(from: DateComponents(year: 2026, month: 1))!
        let february = calendar.date(from: DateComponents(year: 2026, month: 2))!
        let janCount = summary.monthlyCounts.first(where: { $0.month == january })?.count
        let febCount = summary.monthlyCounts.first(where: { $0.month == february })?.count

        XCTAssertEqual(janCount, 1)
        XCTAssertEqual(febCount, 1)
    }

    func testSurfDaysThisYearWeekStreak() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0) ?? .current
        calendar.firstWeekday = 2

        let referenceDate = calendar.date(from: DateComponents(year: 2026, month: 3, day: 18, hour: 12))!
        let currentWeekStart = calendar.dateInterval(of: .weekOfYear, for: referenceDate)!.start
        let previousWeekStart = calendar.date(byAdding: .weekOfYear, value: -1, to: currentWeekStart)!
        let twoWeeksAgoStart = calendar.date(byAdding: .weekOfYear, value: -2, to: currentWeekStart)!

        let sessions = [
            SurfSession(date: currentWeekStart, spot: nil),
            SurfSession(date: previousWeekStart, spot: nil),
            SurfSession(date: twoWeeksAgoStart, spot: nil)
        ]

        let summary = StatsCalculator.surfDaysThisYear(
            sessions: sessions,
            referenceDate: referenceDate,
            calendar: calendar
        )

        XCTAssertEqual(summary.currentWeekStreak, 3)
    }
}
