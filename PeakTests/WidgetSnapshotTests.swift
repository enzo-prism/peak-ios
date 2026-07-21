import XCTest

@testable import Peak

/// The widget renders `PeakWidgetSnapshot` and nothing else, so the derivation
/// is the whole contract. The streak in particular must never disagree with the
/// number the Stats tab shows for the same sessions.
final class WidgetSnapshotTests: XCTestCase {
    private let now = TestCalendar.makeDate(year: 2026, month: 2, day: 18, hour: 12)

    func testSnapshotCapturesLastSessionSpotDateAndRating() {
        let spot = TestFixture.spot(name: "Ocean Beach")
        let sessions = [
            TestFixture.session(date: TestCalendar.makeDate(year: 2026, month: 2, day: 10), spot: TestFixture.spot(name: "Trestles"), rating: 3),
            TestFixture.session(date: TestCalendar.makeDate(year: 2026, month: 2, day: 16), spot: spot, rating: 5)
        ]

        let snapshot = WidgetSnapshotWriter.makeSnapshot(from: sessions, now: now, calendar: TestCalendar.gmt)

        XCTAssertEqual(snapshot.lastSessionSpot, "Ocean Beach")
        XCTAssertEqual(snapshot.lastSessionSpotKey, spot.key)
        XCTAssertEqual(snapshot.lastSessionRating, 5)
        XCTAssertEqual(snapshot.lastSessionDate, TestCalendar.makeDate(year: 2026, month: 2, day: 16))
        XCTAssertEqual(snapshot.totalSessions, 2)
    }

    /// The most recent session wins even when the array arrives out of order —
    /// the writer must not depend on its input already being sorted.
    func testSnapshotPicksLatestSessionRegardlessOfInputOrder() {
        let latest = TestFixture.spot(name: "Pipeline")
        let sessions = [
            TestFixture.session(date: TestCalendar.makeDate(year: 2026, month: 2, day: 17), spot: latest, rating: 4),
            TestFixture.session(date: TestCalendar.makeDate(year: 2026, month: 2, day: 1), spot: TestFixture.spot(name: "Trestles"), rating: 2),
            TestFixture.session(date: TestCalendar.makeDate(year: 2026, month: 2, day: 9), spot: TestFixture.spot(name: "Malibu"), rating: 1)
        ]

        let snapshot = WidgetSnapshotWriter.makeSnapshot(from: sessions, now: now, calendar: TestCalendar.gmt)

        XCTAssertEqual(snapshot.lastSessionSpot, "Pipeline")
        XCTAssertEqual(snapshot.daysSinceLastSession, 1)
    }

    func testSessionsThisMonthExcludesOtherMonthsAndFutureSessions() {
        let sessions = [
            TestFixture.session(date: TestCalendar.makeDate(year: 2026, month: 1, day: 28)),
            TestFixture.session(date: TestCalendar.makeDate(year: 2026, month: 2, day: 2)),
            TestFixture.session(date: TestCalendar.makeDate(year: 2026, month: 2, day: 14)),
            // After `now` — logged ahead of time, not yet surfed this month.
            TestFixture.session(date: TestCalendar.makeDate(year: 2026, month: 2, day: 25))
        ]

        let snapshot = WidgetSnapshotWriter.makeSnapshot(from: sessions, now: now, calendar: TestCalendar.gmt)

        XCTAssertEqual(snapshot.sessionsThisMonth, 2)
        XCTAssertEqual(snapshot.totalSessions, 4)
    }

    /// Parity guard: the widget's streak is `StatsCalculator`'s streak. If the
    /// two ever diverge the Home Screen would quietly contradict the app.
    func testStreakMatchesStatsCalculatorForConsecutiveWeeks() {
        let calendar = TestCalendar.gmt
        let sessions = [
            TestFixture.session(date: TestCalendar.makeDate(year: 2026, month: 2, day: 17)),
            TestFixture.session(date: TestCalendar.makeDate(year: 2026, month: 2, day: 10)),
            TestFixture.session(date: TestCalendar.makeDate(year: 2026, month: 2, day: 3))
        ]

        let snapshot = WidgetSnapshotWriter.makeSnapshot(from: sessions, now: now, calendar: calendar)
        let expected = StatsCalculator.surfDaysThisYear(sessions: sessions, referenceDate: now, calendar: calendar)

        XCTAssertEqual(snapshot.currentStreakWeeks, expected.currentWeekStreak)
        XCTAssertEqual(snapshot.currentStreakWeeks, 3)
    }

    func testStreakMatchesStatsCalculatorWhenStreakIsBroken() {
        let calendar = TestCalendar.gmt
        // This week and last week, then a two-week gap before an older session.
        let sessions = [
            TestFixture.session(date: TestCalendar.makeDate(year: 2026, month: 2, day: 17)),
            TestFixture.session(date: TestCalendar.makeDate(year: 2026, month: 2, day: 11)),
            TestFixture.session(date: TestCalendar.makeDate(year: 2026, month: 1, day: 20))
        ]

        let snapshot = WidgetSnapshotWriter.makeSnapshot(from: sessions, now: now, calendar: calendar)
        let expected = StatsCalculator.surfDaysThisYear(sessions: sessions, referenceDate: now, calendar: calendar)

        XCTAssertEqual(snapshot.currentStreakWeeks, expected.currentWeekStreak)
        XCTAssertEqual(snapshot.currentStreakWeeks, 2)
    }

    func testStreakMatchesStatsCalculatorWithNoSessions() {
        let calendar = TestCalendar.gmt
        let snapshot = WidgetSnapshotWriter.makeSnapshot(from: [], now: now, calendar: calendar)
        let expected = StatsCalculator.surfDaysThisYear(sessions: [], referenceDate: now, calendar: calendar)

        XCTAssertEqual(snapshot.currentStreakWeeks, expected.currentWeekStreak)
        XCTAssertEqual(snapshot.currentStreakWeeks, 0)
        XCTAssertNil(snapshot.lastSessionSpot)
        XCTAssertNil(snapshot.lastSessionSpotKey)
        XCTAssertNil(snapshot.daysSinceLastSession)
        XCTAssertEqual(snapshot.totalSessions, 0)
    }

    /// The snapshot crosses a process boundary as JSON; a field added later
    /// (`lastSessionSpotKey`) must not break snapshots written by an older build.
    func testSnapshotDecodesWhenOptionalFieldsAreAbsent() throws {
        let legacy = """
        {"currentStreakWeeks":2,"totalSessions":7,"sessionsThisMonth":3,"generatedAt":0}
        """
        let data = try XCTUnwrap(legacy.data(using: .utf8))

        let snapshot = try JSONDecoder().decode(PeakWidgetSnapshot.self, from: data)

        XCTAssertEqual(snapshot.currentStreakWeeks, 2)
        XCTAssertEqual(snapshot.totalSessions, 7)
        XCTAssertNil(snapshot.lastSessionSpotKey)
        XCTAssertNil(snapshot.lastSessionSpot)
    }

    func testSnapshotRoundTripsThroughJSON() throws {
        let original = PeakWidgetSnapshot(
            currentStreakWeeks: 4,
            totalSessions: 31,
            sessionsThisMonth: 5,
            lastSessionSpot: "Trestles",
            lastSessionSpotKey: "trestles",
            lastSessionDate: now,
            lastSessionRating: 4,
            daysSinceLastSession: 0,
            generatedAt: now
        )

        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(PeakWidgetSnapshot.self, from: data)

        XCTAssertEqual(decoded, original)
    }
}
