import XCTest

@testable import Peak

/// The logic behind Peak's App Intents entities: identifier stability (a Siri
/// or Spotlight result must keep resolving to the same session), lookup and
/// ordering, and the sentences Siri actually speaks.
final class SessionIntentQueriesTests: XCTestCase {
    private let now = TestCalendar.makeDate(year: 2026, month: 2, day: 18, hour: 12)
    private var calendar: Calendar { TestCalendar.gmt }

    // MARK: - Identifiers

    /// Editing a session changes `updatedAt`, never `createdAt` — so the
    /// identifier a shortcut captured last month still points at it.
    func testSessionIdentifierIsStableAcrossEdits() {
        let created = TestCalendar.makeDate(year: 2026, month: 2, day: 10, hour: 7)
        let session = TestFixture.session(date: created, createdAt: created, updatedAt: created)
        let identifier = SessionIntentQueries.identifier(for: session)

        session.rating = 5
        session.notes = "Better than I remembered"
        session.updatedAt = now

        XCTAssertEqual(SessionIntentQueries.identifier(for: session), identifier)
    }

    func testDistinctSessionsGetDistinctIdentifiers() {
        let a = TestFixture.session(createdAt: TestCalendar.makeDate(year: 2026, month: 2, day: 10, hour: 7))
        let b = TestFixture.session(createdAt: TestCalendar.makeDate(year: 2026, month: 2, day: 10, hour: 8))

        XCTAssertNotEqual(SessionIntentQueries.identifier(for: a), SessionIntentQueries.identifier(for: b))
    }

    func testSpotIdentifierIsTheNormalizedKey() {
        let spot = TestFixture.spot(name: "Ocean Beach")
        XCTAssertEqual(SessionIntentQueries.identifier(for: spot), spot.key)
    }

    // MARK: - Lookup

    func testSessionsLookupReturnsOnlyRequestedIdentifiers() {
        let a = TestFixture.session(createdAt: TestCalendar.makeDate(year: 2026, month: 2, day: 10, hour: 7))
        let b = TestFixture.session(createdAt: TestCalendar.makeDate(year: 2026, month: 2, day: 11, hour: 7))
        let c = TestFixture.session(createdAt: TestCalendar.makeDate(year: 2026, month: 2, day: 12, hour: 7))

        let found = SessionIntentQueries.sessions(
            withIdentifiers: [SessionIntentQueries.identifier(for: a), SessionIntentQueries.identifier(for: c)],
            in: [a, b, c]
        )

        XCTAssertEqual(found.count, 2)
        XCTAssertEqual(
            Set(found.map(SessionIntentQueries.identifier(for:))),
            Set([a, c].map(SessionIntentQueries.identifier(for:)))
        )
    }

    func testSessionsLookupWithEmptyOrUnknownIdentifiersReturnsNothing() {
        let session = TestFixture.session()

        XCTAssertTrue(SessionIntentQueries.sessions(withIdentifiers: [], in: [session]).isEmpty)
        XCTAssertTrue(SessionIntentQueries.sessions(withIdentifiers: ["nope"], in: [session]).isEmpty)
    }

    func testSpotsLookupByIdentifier() {
        let trestles = TestFixture.spot(name: "Trestles")
        let oceanBeach = TestFixture.spot(name: "Ocean Beach")

        let found = SessionIntentQueries.spots(withIdentifiers: [oceanBeach.key], in: [trestles, oceanBeach])

        XCTAssertEqual(found.map(\.name), ["Ocean Beach"])
    }

    /// "…at ocean beach" has to resolve regardless of casing or diacritics, and
    /// a partial name should still find the spot.
    func testSpotStringMatchIsCaseAndDiacriticInsensitive() {
        let trestles = TestFixture.spot(name: "Trestles")
        let oceanBeach = TestFixture.spot(name: "Ocean Beach")
        let saoVicente = TestFixture.spot(name: "São Vicente")
        let spots = [trestles, oceanBeach, saoVicente]

        XCTAssertEqual(SessionIntentQueries.spots(matching: "ocean beach", in: spots).map(\.name), ["Ocean Beach"])
        XCTAssertEqual(SessionIntentQueries.spots(matching: "OCEAN", in: spots).map(\.name), ["Ocean Beach"])
        XCTAssertEqual(SessionIntentQueries.spots(matching: "Trestles", in: spots).map(\.name), ["Trestles"])
        XCTAssertEqual(SessionIntentQueries.spots(matching: "sao vicente", in: spots).map(\.name), ["São Vicente"])
        XCTAssertTrue(SessionIntentQueries.spots(matching: "Pipeline", in: spots).isEmpty)
    }

    func testEmptySpotSearchTermReturnsEverythingAlphabetically() {
        let spots = [TestFixture.spot(name: "Trestles"), TestFixture.spot(name: "Ocean Beach")]

        XCTAssertEqual(SessionIntentQueries.spots(matching: "  ", in: spots).map(\.name), ["Ocean Beach", "Trestles"])
    }

    // MARK: - Suggestions

    func testRecentSessionsAreNewestFirstAndLimited() {
        let sessions = (1...5).map { day in
            TestFixture.session(date: TestCalendar.makeDate(year: 2026, month: 2, day: day))
        }

        let recent = SessionIntentQueries.recentSessions(from: sessions, limit: 3)

        XCTAssertEqual(recent.map(\.date), [
            TestCalendar.makeDate(year: 2026, month: 2, day: 5),
            TestCalendar.makeDate(year: 2026, month: 2, day: 4),
            TestCalendar.makeDate(year: 2026, month: 2, day: 3)
        ])
    }

    /// Suggested spots lead with the ones the surfer actually uses; ties fall
    /// back to alphabetical so the list doesn't reshuffle between invocations.
    func testFrequentSpotsRankByUsageThenName() {
        let trestles = TestFixture.spot(name: "Trestles")
        let oceanBeach = TestFixture.spot(name: "Ocean Beach")
        let pipeline = TestFixture.spot(name: "Pipeline")
        let sessions = [
            TestFixture.session(date: TestCalendar.makeDate(year: 2026, month: 2, day: 1), spot: oceanBeach),
            TestFixture.session(date: TestCalendar.makeDate(year: 2026, month: 2, day: 2), spot: oceanBeach),
            TestFixture.session(date: TestCalendar.makeDate(year: 2026, month: 2, day: 3), spot: oceanBeach),
            TestFixture.session(date: TestCalendar.makeDate(year: 2026, month: 2, day: 4), spot: trestles),
            TestFixture.session(date: TestCalendar.makeDate(year: 2026, month: 2, day: 5), spot: pipeline)
        ]

        let ranked = SessionIntentQueries.frequentSpots(
            from: [trestles, oceanBeach, pipeline],
            sessions: sessions
        )

        XCTAssertEqual(ranked.map(\.name), ["Ocean Beach", "Pipeline", "Trestles"])
    }

    func testFrequentSpotsIncludeNeverSurfedSpotsLast() {
        let trestles = TestFixture.spot(name: "Trestles")
        let unused = TestFixture.spot(name: "Aliso")
        let sessions = [TestFixture.session(spot: trestles)]

        let ranked = SessionIntentQueries.frequentSpots(from: [unused, trestles], sessions: sessions)

        XCTAssertEqual(ranked.map(\.name), ["Trestles", "Aliso"])
    }

    // MARK: - Intent answers

    func testLastSessionPicksTheMostRecentRegardlessOfOrder() {
        let latest = TestFixture.session(date: TestCalendar.makeDate(year: 2026, month: 2, day: 17))
        let sessions = [
            TestFixture.session(date: TestCalendar.makeDate(year: 2026, month: 2, day: 3)),
            latest,
            TestFixture.session(date: TestCalendar.makeDate(year: 2026, month: 2, day: 9))
        ]

        XCTAssertEqual(SessionIntentQueries.lastSession(in: sessions)?.date, latest.date)
        XCTAssertNil(SessionIntentQueries.lastSession(in: []))
    }

    func testSessionsThisMonthFiltersToTheCalendarMonth() {
        let sessions = [
            TestFixture.session(date: TestCalendar.makeDate(year: 2026, month: 1, day: 31)),
            TestFixture.session(date: TestCalendar.makeDate(year: 2026, month: 2, day: 1)),
            TestFixture.session(date: TestCalendar.makeDate(year: 2026, month: 2, day: 28)),
            TestFixture.session(date: TestCalendar.makeDate(year: 2026, month: 3, day: 1))
        ]

        let thisMonth = SessionIntentQueries.sessionsThisMonth(in: sessions, now: now, calendar: calendar)

        XCTAssertEqual(thisMonth.count, 2)
        // Newest first.
        XCTAssertEqual(thisMonth.first?.date, TestCalendar.makeDate(year: 2026, month: 2, day: 28))
    }

    func testLastSessionDialogSpeaksDaysAndSpot() {
        let spot = TestFixture.spot(name: "Trestles")

        let today = TestFixture.session(date: TestCalendar.makeDate(year: 2026, month: 2, day: 18, hour: 6), spot: spot)
        XCTAssertEqual(
            SessionIntentQueries.lastSessionDialog(for: today, now: now, calendar: calendar),
            "You surfed today at Trestles."
        )

        let yesterday = TestFixture.session(date: TestCalendar.makeDate(year: 2026, month: 2, day: 17, hour: 6), spot: spot)
        XCTAssertEqual(
            SessionIntentQueries.lastSessionDialog(for: yesterday, now: now, calendar: calendar),
            "You surfed yesterday at Trestles."
        )

        let lastWeek = TestFixture.session(date: TestCalendar.makeDate(year: 2026, month: 2, day: 12, hour: 6), spot: spot)
        XCTAssertEqual(
            SessionIntentQueries.lastSessionDialog(for: lastWeek, now: now, calendar: calendar),
            "You last surfed 6 days ago at Trestles."
        )
    }

    func testLastSessionDialogOmitsSpotWhenThereIsNone() {
        let session = TestFixture.session(date: TestCalendar.makeDate(year: 2026, month: 2, day: 17, hour: 6), spot: nil)

        XCTAssertEqual(
            SessionIntentQueries.lastSessionDialog(for: session, now: now, calendar: calendar),
            "You surfed yesterday."
        )
    }

    func testLastSessionDialogHandlesAnEmptyLogbook() {
        XCTAssertEqual(
            SessionIntentQueries.lastSessionDialog(for: nil, now: now, calendar: calendar),
            "You haven't logged a surf session yet."
        )
    }

    func testSessionsThisMonthDialogUsesSingularAndPluralAndZero() {
        XCTAssertTrue(
            SessionIntentQueries.sessionsThisMonthDialog(count: 0, now: now, calendar: calendar)
                .hasPrefix("You haven't logged any sessions in")
        )
        XCTAssertTrue(
            SessionIntentQueries.sessionsThisMonthDialog(count: 1, now: now, calendar: calendar)
                .hasPrefix("You've logged 1 session in")
        )
        XCTAssertTrue(
            SessionIntentQueries.sessionsThisMonthDialog(count: 4, now: now, calendar: calendar)
                .hasPrefix("You've logged 4 sessions in")
        )
    }

    // MARK: - Entity projections

    func testSessionEntityCarriesDisplayValuesFromTheModel() {
        let spot = TestFixture.spot(name: "Ocean Beach")
        let created = TestCalendar.makeDate(year: 2026, month: 2, day: 10, hour: 7)
        let session = TestFixture.session(
            date: TestCalendar.makeDate(year: 2026, month: 2, day: 10, hour: 7),
            spot: spot,
            rating: 4,
            durationMinutes: 90,
            createdAt: created
        )

        let entity = SurfSessionEntity(session: session)

        XCTAssertEqual(entity.id, SessionIntentQueries.identifier(for: session))
        XCTAssertEqual(entity.spotName, "Ocean Beach")
        XCTAssertEqual(entity.rating, 4)
        XCTAssertEqual(entity.durationMinutes, 90)
    }

    func testSessionEntitySubtitleCombinesDateDurationAndRating() {
        let date = TestCalendar.makeDate(year: 2026, month: 2, day: 10)

        let full = SurfSessionEntity.subtitle(date: date, rating: 4, durationMinutes: 90)
        XCTAssertTrue(full.contains("1h 30m"), full)
        XCTAssertTrue(full.contains("★★★★"), full)

        // Unrated, undurated sessions degrade to just the date — no stray separators.
        let sparse = SurfSessionEntity.subtitle(date: date, rating: 0, durationMinutes: nil)
        XCTAssertFalse(sparse.contains("·"), sparse)
        XCTAssertFalse(sparse.contains("★"), sparse)
    }

    func testSpotEntityUsesKeyAsIdentifier() {
        let spot = TestFixture.spot(name: "Ocean Beach", locationName: "San Francisco")

        let entity = SpotEntity(spot: spot)

        XCTAssertEqual(entity.id, spot.key)
        XCTAssertEqual(entity.name, "Ocean Beach")
        XCTAssertEqual(entity.locationName, "San Francisco")
    }

    // MARK: - Start/end intent dialog

    func testStartSessionDialogNamesTheSpotWhenKnown() {
        XCTAssertEqual(StartSessionIntent.startedDialog(spotName: "Trestles"), "Session started at Trestles.")
        XCTAssertEqual(StartSessionIntent.startedDialog(spotName: nil), "Session started.")
        XCTAssertEqual(StartSessionIntent.startedDialog(spotName: ""), "Session started.")
    }

    func testStartSessionDialogReportsAnAlreadyRunningSession() {
        XCTAssertEqual(
            StartSessionIntent.alreadyRunningDialog(spotName: "Trestles"),
            "A session at Trestles is already running."
        )
        XCTAssertEqual(StartSessionIntent.alreadyRunningDialog(spotName: nil), "A session is already running.")
    }
}
