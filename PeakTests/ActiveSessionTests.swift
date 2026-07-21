import XCTest

@testable import Peak

/// Covers the in-progress session: how elapsed time becomes a loggable
/// duration, how the ended session prefills the editor, and the App-Group
/// hand-off between the surface that ends a session and the app that logs it.
final class ActiveSessionTests: XCTestCase {
    private var defaults: UserDefaults!
    private var suiteName: String!

    override func setUp() {
        super.setUp()
        // A scratch suite per test so nothing touches the real App Group.
        suiteName = "peak.tests.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
        defaults = nil
        suiteName = nil
        super.tearDown()
    }

    // MARK: - Duration rounding

    func testDurationRoundsToNearestFiveMinuteStep() {
        let start = TestCalendar.makeDate(year: 2026, month: 2, day: 18, hour: 6)

        // 62 min → 60, 63 min → 65 (nearest step, not truncation).
        XCTAssertEqual(ActiveSessionCalculator.durationMinutes(from: start, to: start.addingTimeInterval(62 * 60)), 60)
        XCTAssertEqual(ActiveSessionCalculator.durationMinutes(from: start, to: start.addingTimeInterval(63 * 60)), 65)
        XCTAssertEqual(ActiveSessionCalculator.durationMinutes(from: start, to: start.addingTimeInterval(90 * 60)), 90)
    }

    func testDurationClampsToMinimumAndMaximum() {
        let start = TestCalendar.makeDate(year: 2026, month: 2, day: 18, hour: 6)

        // A 40-second mis-tap still opens the editor at one step, not zero.
        XCTAssertEqual(ActiveSessionCalculator.durationMinutes(from: start, to: start.addingTimeInterval(40)), 5)
        // A forgotten timer clamps at the editor's own 8-hour ceiling.
        XCTAssertEqual(
            ActiveSessionCalculator.durationMinutes(from: start, to: start.addingTimeInterval(20 * 3600)),
            SurfSession.maxDurationMinutes
        )
    }

    /// A clock change (or a stale record) can hand back a negative interval;
    /// that must not produce a nonsense duration.
    func testDurationHandlesNonPositiveElapsedTime() {
        let start = TestCalendar.makeDate(year: 2026, month: 2, day: 18, hour: 6)

        XCTAssertEqual(ActiveSessionCalculator.durationMinutes(from: start, to: start), 5)
        XCTAssertEqual(ActiveSessionCalculator.durationMinutes(from: start, to: start.addingTimeInterval(-3600)), 5)
    }

    func testDurationIsAlwaysAWholeNumberOfSteps() {
        let start = TestCalendar.makeDate(year: 2026, month: 2, day: 18, hour: 6)

        for seconds in stride(from: 0, through: 4 * 3600, by: 137) {
            let minutes = ActiveSessionCalculator.durationMinutes(from: start, to: start.addingTimeInterval(Double(seconds)))
            XCTAssertEqual(minutes % SurfSession.durationStepMinutes, 0, "\(minutes) is not a whole step")
            XCTAssertGreaterThanOrEqual(minutes, SurfSession.durationStepMinutes)
            XCTAssertLessThanOrEqual(minutes, SurfSession.maxDurationMinutes)
        }
    }

    // MARK: - Draft prefill

    func testDraftPrefillsStartTimeDurationAndSpot() {
        let trestles = TestFixture.spot(name: "Trestles")
        let oceanBeach = TestFixture.spot(name: "Ocean Beach")
        let start = TestCalendar.makeDate(year: 2026, month: 2, day: 18, hour: 6, minute: 30)
        let record = EndedSessionRecord(
            state: ActiveSessionState(spotKey: oceanBeach.key, spotName: "Ocean Beach", startDate: start),
            endedAt: start.addingTimeInterval(97 * 60)
        )

        let draft = ActiveSessionCalculator.makeDraft(from: record, spots: [trestles, oceanBeach])

        XCTAssertEqual(draft.date, start)
        XCTAssertEqual(draft.durationMinutes, 95)
        XCTAssertEqual(draft.selectedSpot?.key, oceanBeach.key)
        XCTAssertEqual(draft.spotName, "Ocean Beach")
        // A prefilled draft arrives ready to save — spot is the only requirement.
        XCTAssertTrue(draft.isReadyToSave)
    }

    /// The spot was deleted while the session ran: keep the name so the editor
    /// can recreate it rather than silently losing where the surfer was.
    func testDraftKeepsSpotNameWhenSpotIsNoLongerInTheLibrary() {
        let start = TestCalendar.makeDate(year: 2026, month: 2, day: 18, hour: 6)
        let record = EndedSessionRecord(
            state: ActiveSessionState(spotKey: "pipeline", spotName: "Pipeline", startDate: start),
            endedAt: start.addingTimeInterval(3600)
        )

        let draft = ActiveSessionCalculator.makeDraft(from: record, spots: [TestFixture.spot(name: "Trestles")])

        XCTAssertNil(draft.selectedSpot)
        XCTAssertEqual(draft.spotName, "Pipeline")
        XCTAssertEqual(draft.durationMinutes, 60)
    }

    /// Key lost but name intact — normalizing the name still finds the spot.
    func testDraftResolvesSpotByNameWhenKeyIsMissing() {
        let spot = TestFixture.spot(name: "Ocean Beach")
        let start = TestCalendar.makeDate(year: 2026, month: 2, day: 18, hour: 6)
        let record = EndedSessionRecord(
            state: ActiveSessionState(spotKey: nil, spotName: "ocean beach", startDate: start),
            endedAt: start.addingTimeInterval(1800)
        )

        let draft = ActiveSessionCalculator.makeDraft(from: record, spots: [spot])

        XCTAssertEqual(draft.selectedSpot?.key, spot.key)
        XCTAssertEqual(draft.durationMinutes, 30)
    }

    func testDraftWithoutASpotStillCarriesTimeAndDuration() {
        let start = TestCalendar.makeDate(year: 2026, month: 2, day: 18, hour: 6)
        let record = EndedSessionRecord(
            state: ActiveSessionState(startDate: start),
            endedAt: start.addingTimeInterval(45 * 60)
        )

        let draft = ActiveSessionCalculator.makeDraft(from: record, spots: [])

        XCTAssertNil(draft.selectedSpot)
        XCTAssertEqual(draft.spotName, "")
        XCTAssertEqual(draft.date, start)
        XCTAssertEqual(draft.durationMinutes, 45)
        XCTAssertFalse(draft.isReadyToSave)
    }

    // MARK: - App-Group store

    func testActiveSessionRoundTripsThroughDefaults() {
        let state = ActiveSessionState(
            spotKey: "trestles",
            spotName: "Trestles",
            startDate: TestCalendar.makeDate(year: 2026, month: 2, day: 18, hour: 6)
        )

        XCTAssertNil(ActiveSessionStore.loadActive(from: defaults))
        ActiveSessionStore.saveActive(state, to: defaults)
        XCTAssertEqual(ActiveSessionStore.loadActive(from: defaults), state)

        ActiveSessionStore.clearActive(in: defaults)
        XCTAssertNil(ActiveSessionStore.loadActive(from: defaults))
    }

    func testEndActiveMovesStateToPendingLog() {
        let start = TestCalendar.makeDate(year: 2026, month: 2, day: 18, hour: 6)
        let end = start.addingTimeInterval(3600)
        ActiveSessionStore.saveActive(ActiveSessionState(spotKey: "trestles", spotName: "Trestles", startDate: start), to: defaults)

        let record = ActiveSessionStore.endActive(at: end, in: defaults)

        XCTAssertEqual(record?.endedAt, end)
        XCTAssertEqual(record?.state.spotName, "Trestles")
        // The session is no longer running, but is queued for the editor.
        XCTAssertNil(ActiveSessionStore.loadActive(from: defaults))
        XCTAssertEqual(ActiveSessionStore.loadPendingLog(from: defaults), record)
    }

    func testEndActiveWithNothingRunningIsANoOp() {
        XCTAssertNil(ActiveSessionStore.endActive(in: defaults))
        XCTAssertNil(ActiveSessionStore.loadPendingLog(from: defaults))
    }

    /// Draining is destructive on purpose: a session must never open the editor
    /// twice (once on foreground, again on the next launch).
    func testTakePendingLogConsumesTheRecord() {
        let start = TestCalendar.makeDate(year: 2026, month: 2, day: 18, hour: 6)
        ActiveSessionStore.saveActive(ActiveSessionState(spotName: "Trestles", startDate: start), to: defaults)
        ActiveSessionStore.endActive(at: start.addingTimeInterval(3600), in: defaults)

        XCTAssertNotNil(ActiveSessionStore.takePendingLog(from: defaults))
        XCTAssertNil(ActiveSessionStore.takePendingLog(from: defaults))
    }

    func testResetClearsBothSlots() {
        let start = TestCalendar.makeDate(year: 2026, month: 2, day: 18, hour: 6)
        ActiveSessionStore.saveActive(ActiveSessionState(startDate: start), to: defaults)
        ActiveSessionStore.savePendingLog(
            EndedSessionRecord(state: ActiveSessionState(startDate: start), endedAt: start),
            to: defaults
        )

        ActiveSessionStore.reset(in: defaults)

        XCTAssertNil(ActiveSessionStore.loadActive(from: defaults))
        XCTAssertNil(ActiveSessionStore.loadPendingLog(from: defaults))
    }
}
