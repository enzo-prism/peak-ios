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

    func testMonthlyUsageCountsUseReferenceDate() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0) ?? .current

        let reference = calendar.date(from: DateComponents(year: 2026, month: 4, day: 15))!
        let feb = calendar.date(from: DateComponents(year: 2026, month: 2, day: 5, hour: 6))!
        let mar = calendar.date(from: DateComponents(year: 2026, month: 3, day: 6, hour: 6))!

        let sessions = [
            SurfSession(date: feb, spot: nil),
            SurfSession(date: mar, spot: nil),
            SurfSession(date: mar.addingTimeInterval(3600), spot: nil)
        ]

        let counts = UsageMetricsCalculator.monthlyUsageCounts(
            sessions: sessions,
            monthsBack: 3,
            calendar: calendar,
            referenceDate: reference
        )

        let febStart = calendar.date(from: DateComponents(year: 2026, month: 2))!
        let marStart = calendar.date(from: DateComponents(year: 2026, month: 3))!
        let febCount = counts.first(where: { $0.month == febStart })?.count
        let marCount = counts.first(where: { $0.month == marStart })?.count

        XCTAssertEqual(febCount, 1)
        XCTAssertEqual(marCount, 2)
    }

    func testMetricsAverageIgnoresZeroRatings() {
        let sessions = [
            SurfSession(date: TestCalendar.makeDate(year: 2026, month: 2, day: 1), spot: nil, rating: 5),
            SurfSession(date: TestCalendar.makeDate(year: 2026, month: 2, day: 2), spot: nil, rating: 0),
            SurfSession(date: TestCalendar.makeDate(year: 2026, month: 2, day: 3), spot: nil, rating: 2)
        ]

        let summary = UsageMetricsCalculator.metrics(for: sessions, calendar: TestCalendar.gmt)

        XCTAssertEqual(summary.averageRating, 3.5)
    }

    func testSpotAndBuddySnapshotsCaptureCounts() {
        let spotA = TestFixture.spot(name: "Trestles")
        let spotB = TestFixture.spot(name: "Ocean Beach")
        let buddyA = TestFixture.buddy(name: "Kai")
        let buddyB = TestFixture.buddy(name: "Nora")

        let session1 = TestFixture.session(
            date: TestCalendar.makeDate(year: 2026, month: 2, day: 1),
            spot: spotA,
            buddies: [buddyA],
            rating: 4
        )
        let session2 = TestFixture.session(
            date: TestCalendar.makeDate(year: 2026, month: 2, day: 3),
            spot: spotB,
            buddies: [buddyA, buddyB],
            rating: 5
        )

        let spotSnapshots = UsageMetricsCalculator.spotSnapshots(sessions: [session1, session2])
        let buddySnapshots = UsageMetricsCalculator.buddySnapshots(sessions: [session1, session2])

        XCTAssertEqual(spotSnapshots[spotA.key]?.count, 1)
        XCTAssertEqual(spotSnapshots[spotB.key]?.count, 1)
        XCTAssertEqual(buddySnapshots[buddyA.key]?.count, 2)
        XCTAssertEqual(buddySnapshots[buddyB.key]?.count, 1)
        XCTAssertEqual(buddySnapshots[buddyA.key]?.lastUsed, session2.date)
    }
}
