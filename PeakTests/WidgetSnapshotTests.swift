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

    // MARK: - Time adjustment between app runs

    /// The snapshot is only rewritten when the app runs; between writes the
    /// widget re-derives the day-relative values for each timeline entry so a
    /// week away from the app can't leave "Surfed today" on the Home Screen.
    func testAdjustedRecountsDaysSinceLastSession() {
        let sessions = [TestFixture.session(date: TestCalendar.makeDate(year: 2026, month: 2, day: 16), spot: TestFixture.spot())]
        let snapshot = WidgetSnapshotWriter.makeSnapshot(from: sessions, now: now, calendar: TestCalendar.gmt)
        XCTAssertEqual(snapshot.daysSinceLastSession, 2)

        let aWeekLater = TestCalendar.makeDate(year: 2026, month: 2, day: 25, hour: 9)
        XCTAssertEqual(snapshot.adjusted(for: aWeekLater, calendar: TestCalendar.gmt).daysSinceLastSession, 9)
        // Rendering "now" changes nothing.
        XCTAssertEqual(snapshot.adjusted(for: now, calendar: TestCalendar.gmt), snapshot)
    }

    func testAdjustedResetsSessionsThisMonthWhenTheMonthTurns() {
        let sessions = [
            TestFixture.session(date: TestCalendar.makeDate(year: 2026, month: 2, day: 10), spot: TestFixture.spot()),
            TestFixture.session(date: TestCalendar.makeDate(year: 2026, month: 2, day: 16), spot: TestFixture.spot())
        ]
        let snapshot = WidgetSnapshotWriter.makeSnapshot(from: sessions, now: now, calendar: TestCalendar.gmt)
        XCTAssertEqual(snapshot.sessionsThisMonth, 2)

        // Later in February: the count stands.
        let laterSameMonth = TestCalendar.makeDate(year: 2026, month: 2, day: 27)
        XCTAssertEqual(snapshot.adjusted(for: laterSameMonth, calendar: TestCalendar.gmt).sessionsThisMonth, 2)

        // March: no app run means no new sessions, so the new month starts at zero.
        let march = TestCalendar.makeDate(year: 2026, month: 3, day: 2)
        XCTAssertEqual(snapshot.adjusted(for: march, calendar: TestCalendar.gmt).sessionsThisMonth, 0)
    }

    /// The streak keeps `StatsCalculator`'s current-week grace: it survives
    /// while the last session sits in the render date's week or the week
    /// before, and breaks to zero after that — exactly what recomputing the
    /// streak over the unchanged library would produce.
    func testAdjustedBreaksTheStreakAfterTheGraceWeek() {
        let calendar = TestCalendar.gmt
        let sessions = [
            TestFixture.session(date: TestCalendar.makeDate(year: 2026, month: 2, day: 17)),
            TestFixture.session(date: TestCalendar.makeDate(year: 2026, month: 2, day: 10))
        ]
        let snapshot = WidgetSnapshotWriter.makeSnapshot(from: sessions, now: now, calendar: calendar)
        XCTAssertEqual(snapshot.currentStreakWeeks, 2)

        // Same week (Feb 18 is in the Feb 17 session's week): streak stands.
        XCTAssertEqual(snapshot.adjusted(for: now, calendar: calendar).currentStreakWeeks, 2)

        // The following week: current-week grace, streak still stands — and it
        // matches what StatsCalculator says for the same library at that date.
        let graceWeek = TestCalendar.makeDate(year: 2026, month: 2, day: 24)
        XCTAssertEqual(snapshot.adjusted(for: graceWeek, calendar: calendar).currentStreakWeeks, 2)
        XCTAssertEqual(
            StatsCalculator.surfDaysThisYear(sessions: sessions, referenceDate: graceWeek, calendar: calendar).currentWeekStreak,
            2
        )

        // Two weeks on: broken, in agreement with StatsCalculator.
        let afterGrace = TestCalendar.makeDate(year: 2026, month: 3, day: 3)
        XCTAssertEqual(snapshot.adjusted(for: afterGrace, calendar: calendar).currentStreakWeeks, 0)
        XCTAssertEqual(
            StatsCalculator.surfDaysThisYear(sessions: sessions, referenceDate: afterGrace, calendar: calendar).currentWeekStreak,
            0
        )
    }

    func testAdjustedLeavesAnEmptySnapshotAlone() {
        let empty = PeakWidgetSnapshot.empty
        let adjusted = empty.adjusted(for: now, calendar: TestCalendar.gmt)
        XCTAssertNil(adjusted.daysSinceLastSession)
        XCTAssertEqual(adjusted.currentStreakWeeks, 0)
        XCTAssertEqual(adjusted.sessionsThisMonth, 0)
    }

    // MARK: - Deep link

    /// The widgets and the app agree on one URL constant; this pins the shape
    /// so a widget tap can't start pointing somewhere the app ignores.
    func testWidgetDeepLinkIsRecognised() {
        XCTAssertTrue(PeakDeepLink.isNewSession(PeakDeepLink.newSession))
        XCTAssertTrue(PeakDeepLink.isNewSession(URL(string: "peak://new-session")!))
        XCTAssertTrue(PeakDeepLink.isNewSession(URL(string: "peak:///new-session")!))
    }

    func testUnrelatedURLsAreIgnored() {
        XCTAssertFalse(PeakDeepLink.isNewSession(URL(string: "peak://stats")!))
        XCTAssertFalse(PeakDeepLink.isNewSession(URL(string: "https://new-session")!))
        XCTAssertFalse(PeakDeepLink.isNewSession(URL(string: "peak://")!))
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

    // MARK: - Wave stats (3.0)

    /// The last session's wave count rides along in the snapshot when present.
    func testSnapshotCarriesLastSessionWaveCount() {
        let last = TestFixture.session(
            date: TestCalendar.makeDate(year: 2026, month: 2, day: 16),
            spot: TestFixture.spot(name: "Ocean Beach"),
            rating: 5
        )
        last.waveCount = 11
        let earlier = TestFixture.session(
            date: TestCalendar.makeDate(year: 2026, month: 2, day: 10),
            spot: TestFixture.spot(name: "Trestles")
        )
        earlier.waveCount = 3

        let snapshot = WidgetSnapshotWriter.makeSnapshot(from: [earlier, last], now: now, calendar: TestCalendar.gmt)
        XCTAssertEqual(snapshot.lastSessionWaveCount, 11)
    }

    /// Absent rather than zero: a widget must never claim "0 waves" for a session
    /// that was simply never tracked.
    func testSnapshotOmitsWaveCountWhenTheLastSessionHasNone() {
        let snapshot = WidgetSnapshotWriter.makeSnapshot(
            from: [TestFixture.session(date: TestCalendar.makeDate(year: 2026, month: 2, day: 16), spot: TestFixture.spot())],
            now: now,
            calendar: TestCalendar.gmt
        )
        XCTAssertNil(snapshot.lastSessionWaveCount)
    }

    /// A skunked session genuinely reports zero, and that must survive the
    /// round trip through the App Group container.
    func testSnapshotRoundTripsZeroWaveCount() throws {
        let session = TestFixture.session(date: TestCalendar.makeDate(year: 2026, month: 2, day: 16), spot: TestFixture.spot())
        session.waveCount = 0

        let snapshot = WidgetSnapshotWriter.makeSnapshot(from: [session], now: now, calendar: TestCalendar.gmt)
        XCTAssertEqual(snapshot.lastSessionWaveCount, 0)

        let decoded = try JSONDecoder().decode(PeakWidgetSnapshot.self, from: JSONEncoder().encode(snapshot))
        XCTAssertEqual(decoded.lastSessionWaveCount, 0)
        XCTAssertEqual(decoded, snapshot)
    }

    /// A snapshot written by an older build has no wave-count key at all; it must
    /// still decode rather than stranding the widget on stale data.
    func testSnapshotDecodesFromPreWaveStatsPayload() throws {
        let legacy = Data(#"{"currentStreakWeeks":2,"totalSessions":7,"sessionsThisMonth":3,"generatedAt":760000000}"#.utf8)
        let decoded = try JSONDecoder().decode(PeakWidgetSnapshot.self, from: legacy)
        XCTAssertEqual(decoded.totalSessions, 7)
        XCTAssertNil(decoded.lastSessionWaveCount)
    }
}
