import XCTest

final class PeakUISmokeTests: XCTestCase {
    private var app: XCUIApplication!
    private let e2eSessionMarker = "E2E conditions marker"

    override func setUp() {
        super.setUp()
        continueAfterFailure = false
        app = XCUIApplication()
        launchAppWithUITestEnvironment(surfConditionsScenario: "success")
    }

    private func launchAppWithUITestEnvironment(surfConditionsScenario: String) {
        app = XCUIApplication()
        app.launchEnvironment["UITESTS"] = "1"
        app.launchEnvironment["UITESTS_CLASSIC_NAVIGATION"] = "1"
        app.launchEnvironment["UITESTS_SURF_CONDITIONS_SCENARIO"] = surfConditionsScenario
        app.launchEnvironment["UITESTS_DISABLE_ANIMATIONS"] = "1"
        app.launchEnvironment["UITESTS_FIXED_DATE"] = "2026-02-01T12:00:00Z"
        app.launchEnvironment["UITESTS_SESSION_MARKER"] = e2eSessionMarker
        app.launch()
    }

    override func tearDown() {
        app = nil
        super.tearDown()
    }

    func testCreateSessionAppearsInHistory() {
        tapTab(named: "Log")

        let cta = app.buttons["Log Session"]
        assertExists(cta)
        cta.tap()

        selectSpot(key: "trestles", fallbackText: "Trestles")

        saveSession()

        tapTab(named: "History")
        XCTAssertTrue(app.staticTexts["Trestles"].waitForExistence(timeout: 3))
    }

    func testHistoryFilterNarrowsResults() {
        tapTab(named: "History")

        let oceanBeach = app.staticTexts["Ocean Beach"]
        XCTAssertTrue(oceanBeach.waitForExistence(timeout: 3))

        let filtersButton = app.buttons["Filters"]
        assertExists(filtersButton)
        filtersButton.tap()

        tapRow(label: "Trestles")

        let doneButton = app.buttons["Done"]
        assertExists(doneButton)
        doneButton.tap()

        XCTAssertTrue(app.staticTexts["Trestles"].waitForExistence(timeout: 3))
        XCTAssertFalse(app.staticTexts["Ocean Beach"].exists)
    }

    func testAutoFillConditionsEndToEnd() {
        tapTab(named: "Log")

        let cta = app.buttons["Log Session"]
        assertExists(cta)
        cta.tap()

        selectSpot(key: "trestles", fallbackText: "Trestles")

        let scrollView = app.scrollViews["session.editor.scroll"]
        showOptionalFields(in: scrollView)

        let duration = app.sliders["session.editor.duration"]
        assertExists(duration)
        scrollToVisible(duration, in: scrollView)
        duration.adjust(toNormalizedSliderPosition: 0.5)

        let autoFillButton = app.buttons["session.editor.autoFillConditions"]
        scrollToVisible(autoFillButton, in: scrollView)
        assertExists(autoFillButton)
        XCTAssertTrue(isCentreVisible(autoFillButton, in: scrollView), "Auto-fill must be below the editor navigation bar before tapping")
        autoFillButton.tap()

        assertConditionsNotice(beginsWith: "Filled from Open-Meteo")

        let notes = app.textViews["session.editor.notes"]
        scrollToVisible(notes, in: scrollView)
        assertExists(notes)
        notes.tap()
        notes.typeText(e2eSessionMarker)

        saveSession()

        tapTab(named: "History")
        let latestSession = latestHistoryRow(markerSessionNote: e2eSessionMarker)
        XCTAssertTrue(latestSession.waitForExistence(timeout: 5), "Expected the newly saved session to appear in history.")
        latestSession.tap()

        let sourceTitle = app.staticTexts["Source"]
        assertExists(sourceTitle)
        let sourceValue = app.staticTexts.containing(
            NSPredicate(format: "label CONTAINS[c] %@", "Open-Meteo")
        ).firstMatch
        XCTAssertTrue(sourceValue.waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["E2E conditions marker"].waitForExistence(timeout: 2))
    }

    func testAutoFillConditionsShowsErrorNotice() {
        app.terminate()
        launchAppWithUITestEnvironment(surfConditionsScenario: "remote_error")
        tapTab(named: "Log")

        let cta = app.buttons["Log Session"]
        assertExists(cta)
        cta.tap()

        selectSpot(key: "trestles", fallbackText: "Trestles")

        let scrollView = app.scrollViews["session.editor.scroll"]
        showOptionalFields(in: scrollView)

        let duration = app.sliders["session.editor.duration"]
        assertExists(duration)
        scrollToVisible(duration, in: scrollView)
        duration.adjust(toNormalizedSliderPosition: 0.5)

        let autoFillButton = app.buttons["session.editor.autoFillConditions"]
        scrollToVisible(autoFillButton, in: scrollView)
        assertExists(autoFillButton)
        XCTAssertTrue(isCentreVisible(autoFillButton, in: scrollView), "Auto-fill must be below the editor navigation bar before tapping")
        autoFillButton.tap()

        assertConditionsNotice(contains: "Mock surf report service error")
    }

    func testAutoFillConditionsShowsNoDataNotice() {
        app.terminate()
        launchAppWithUITestEnvironment(surfConditionsScenario: "no_data")
        tapTab(named: "Log")

        let cta = app.buttons["Log Session"]
        assertExists(cta)
        cta.tap()

        selectSpot(key: "trestles", fallbackText: "Trestles")

        let scrollView = app.scrollViews["session.editor.scroll"]
        showOptionalFields(in: scrollView)

        let duration = app.sliders["session.editor.duration"]
        assertExists(duration)
        scrollToVisible(duration, in: scrollView)
        duration.adjust(toNormalizedSliderPosition: 0.5)

        let autoFillButton = app.buttons["session.editor.autoFillConditions"]
        scrollToVisible(autoFillButton, in: scrollView)
        assertExists(autoFillButton)
        XCTAssertTrue(isCentreVisible(autoFillButton, in: scrollView), "Auto-fill must be below the editor navigation bar before tapping")
        autoFillButton.tap()

        assertConditionsNotice(contains: "Surf report data is unavailable")
    }

    // MARK: - Wave stats (3.0)

    /// Two things are worth protecting here, and they are the two the feature
    /// lives or dies on: every derived number must be correctable by hand, and
    /// the screen must never present those numbers as fact. The second is a
    /// product requirement rather than a nicety — a confidently wrong wave count
    /// is the single biggest source of one-star reviews in this category — so the
    /// microcopy is asserted, not merely the control.
    ///
    /// This path involves no Apple Watch workout at all, which is the point:
    /// manual entry has to work for the majority of users who never wear one.
    func testWaveCountIsEditableAndReachesSessionDetail() {
        tapTab(named: "Log")

        let cta = app.buttons["Log Session"]
        assertExists(cta)
        cta.tap()

        selectSpot(key: "trestles", fallbackText: "Trestles")

        let scrollView = app.scrollViews["session.editor.scroll"]
        showOptionalFields(in: scrollView)

        // Three increments from an unset field: 0 -> 1 -> 2 -> 3.
        incrementWaveCount(times: 3, in: scrollView)

        let value = app.staticTexts["session.editor.waveCount.value"]
        assertExists(value)
        XCTAssertEqual(value.label, "3", "the stepper did not write the wave count back to the draft")

        let notes = app.textViews["session.editor.notes"]
        scrollToVisible(notes, in: scrollView)
        assertExists(notes)
        notes.tap()
        notes.typeText(e2eSessionMarker)

        saveSession()

        tapTab(named: "History")
        let row = latestHistoryRow(markerSessionNote: e2eSessionMarker)
        XCTAssertTrue(row.waitForExistence(timeout: 5), "Expected the saved session in history.")
        row.tap()

        let waveTag = heroElement("session.detail.heroTag.waveCount")
        XCTAssertTrue(waveTag.exists, "Wave count tag missing from the session hero.")
        XCTAssertEqual(waveTag.label, "3 waves")

        // The hero must say where the number came from, in the same glance.
        let caption = heroElement("session.detail.waveStats.caption")
        XCTAssertTrue(caption.exists, "no provenance line beside the wave stats")
        XCTAssertTrue(
            caption.label.localizedCaseInsensitiveContains("you"),
            "a hand-entered count must be credited to the user, got: \(caption.label)"
        )
    }

    /// The editor always states where the numbers come from, and the copy changes
    /// the moment a human touches one — which is exactly the promise that a later
    /// workout import will not overwrite them.
    func testEditorExplainsWhereWaveStatsComeFrom() {
        tapTab(named: "Log")

        let cta = app.buttons["Log Session"]
        assertExists(cta)
        cta.tap()

        selectSpot(key: "trestles", fallbackText: "Trestles")

        let scrollView = app.scrollViews["session.editor.scroll"]
        showOptionalFields(in: scrollView)

        dismissKeyboard()

        let caption = app.staticTexts["session.editor.waveStats.caption"]
        assertExists(caption)
        scrollToVisible(caption, in: scrollView)
        let initialCopy = caption.label
        XCTAssertFalse(initialCopy.isEmpty, "wave stats must always carry a provenance line")
        XCTAssertTrue(
            initialCopy.localizedCaseInsensitiveContains("estimat")
                || initialCopy.localizedCaseInsensitiveContains("enter"),
            "the copy must frame these as estimates or as your own entry, got: \(initialCopy)"
        )

        incrementWaveCount(times: 1, in: scrollView)

        let updated = app.staticTexts["session.editor.waveStats.caption"]
        assertExists(updated)
        XCTAssertTrue(
            updated.label.localizedCaseInsensitiveContains("you"),
            "after an edit the copy must credit the user, got: \(updated.label)"
        )
    }

    /// Sessions with no wave stats are completely unaffected: no tag, no caption,
    /// no empty row. Most Peak users will never record a wave stat, and their
    /// session detail must look exactly as it did before 3.0.
    func testSessionsWithoutWaveStatsShowNoWaveChrome() {
        tapTab(named: "History")

        let row = latestHistoryRow()
        XCTAssertTrue(row.waitForExistence(timeout: 5))
        row.tap()

        XCTAssertTrue(
            heroElement("session.detail.heroTag.duration").exists,
            "the hero should still render normally"
        )
        XCTAssertFalse(heroElement("session.detail.heroTag.waveCount", timeout: 0).exists)
        XCTAssertFalse(heroElement("session.detail.waveStats.caption", timeout: 0).exists)
    }

    /// Drives the wave-count stepper.
    ///
    /// Two hazards are handled here. The spot field leaves the keyboard up, which
    /// can park the stepper underneath it — so the keyboard is waited out, not
    /// merely dismissed. And `isHittable` is a snapshot: checking it and then
    /// tapping loses the race against the keyboard's dismissal animation, which
    /// is exactly how this test failed first time round. A coordinate tap does
    /// not re-check hittability, so it cannot lose that race.
    /// Each increment is confirmed against the displayed value before moving on.
    /// A blind burst of taps is not safe here: the first keyboard of a session on
    /// a freshly erased simulator — which is what CI always gets — raises
    /// springboard's "Enable Dictation?" alert, and a system alert swallows the
    /// tap underneath it. Retrying until the value actually moves absorbs that
    /// without hiding a broken control: if the stepper genuinely does not write
    /// back, every retry fails too and the assertion below still catches it.
    private func incrementWaveCount(times: Int, in scrollView: XCUIElement) {
        dismissKeyboard()
        _ = app.keyboards.firstMatch.waitForNonExistence(timeout: 3)

        let increment = app.buttons["session.editor.waveCount.increment"]
        assertExists(increment)
        scrollToVisible(increment, in: scrollView)

        let value = app.staticTexts["session.editor.waveCount.value"]
        assertExists(value)

        for step in 1...times {
            let expected = String(step)
            var attempts = 0
            while value.label != expected && attempts < 4 {
                increment.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
                attempts += 1
                if value.label != expected {
                    _ = value.waitForExistence(timeout: 1)
                }
            }
            XCTAssertEqual(value.label, expected, "wave count did not reach \(expected) after \(attempts) taps")
        }
    }

    /// Hero tags collapse their children for VoiceOver, so SwiftUI is free to
    /// expose them as a static text or as a generic element depending on the
    /// build. Resolve across both rather than pinning a type. `timeout` of 0
    /// makes this a pure negative check with no waiting.
    private func heroElement(_ identifier: String, timeout: TimeInterval = 5) -> XCUIElement {
        let queries: [XCUIElementQuery] = [app.staticTexts, app.otherElements, app.buttons]
        for query in queries where query[identifier].exists {
            return query[identifier]
        }
        guard timeout > 0 else { return app.staticTexts[identifier] }

        // Poll each type in turn so a slow first paint does not spend the whole
        // budget waiting on the wrong query.
        let slice = max(0.5, timeout / Double(queries.count))
        for query in queries where query[identifier].waitForExistence(timeout: slice) {
            return query[identifier]
        }
        return app.staticTexts[identifier]
    }
}

/// Best Window Today.
///
/// The states worth protecting are the two honesty-critical ones: a real
/// recommendation only appears when the surfer's own history can support it, and
/// a thin logbook says so plainly instead of inventing a window. Both run against
/// a mocked forecast, so no test here touches the network.
final class PeakWindowCardUITests: XCTestCase {
    private var app: XCUIApplication!

    override func tearDown() {
        app = nil
        super.tearDown()
    }

    /// `windowScenario` also decides how much rated history gets seeded — "confident"
    /// seeds a full logbook at Trestles, anything else leaves the default four
    /// sessions. `TodayWindowServiceTests` proves each fixture reaches the state
    /// asserted here.
    private func launch(windowScenario: String?) {
        app = XCUIApplication()
        app.launchEnvironment["UITESTS"] = "1"
        app.launchEnvironment["UITESTS_CLASSIC_NAVIGATION"] = "1"
        app.launchEnvironment["UITESTS_DISABLE_ANIMATIONS"] = "1"
        app.launchEnvironment["UITESTS_FIXED_DATE"] = "2026-02-01T12:00:00Z"
        if let windowScenario {
            app.launchEnvironment["UITESTS_WINDOW_SCENARIO"] = windowScenario
        }
        app.launch()
        tapLogTab()
    }

    private func tapLogTab() {
        let tab = app.tabBars.buttons["Log"]
        if tab.waitForExistence(timeout: 5) {
            if tab.isHittable {
                tab.tap()
            } else {
                tab.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
            }
        }
    }

    private func tapTab(named name: String, file: StaticString = #filePath, line: UInt = #line) {
        let tabButton = app.tabBars.buttons[name]
        if tabButton.waitForExistence(timeout: 5) {
            if tabButton.isHittable {
                tabButton.tap()
            } else {
                tabButton.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
            }
            return
        }

        let predicate = NSPredicate(format: "label == %@", name)

        if let element = firstHittableTab(in: app.buttons.matching(predicate)) {
            element.tap()
            return
        }

        if let element = firstHittableTab(in: app.cells.matching(predicate)) {
            element.tap()
            return
        }

        if let element = firstHittableTab(in: app.otherElements.matching(predicate)) {
            element.tap()
            return
        }

        XCTFail("Missing tab: \(name)", file: file, line: line)
    }

    private func firstHittableTab(in query: XCUIElementQuery) -> XCUIElement? {
        let elements = query.allElementsBoundByIndex
        if let hittable = elements.first(where: { $0.exists && $0.isHittable }) {
            return hittable
        }
        if let first = elements.first, first.exists {
            return first
        }
        return nil
    }

    /// Addressed by label, not by an identifier on a wrapper: identifiers that sit
    /// on containers are not queryable as buttons.
    private var checkButton: XCUIElement {
        app.buttons["Check conditions"]
    }

    /// The cited-session row, found by its copy so it does not matter whether the
    /// NavigationLink surfaces as a button or as text.
    private var matchElement: XCUIElement {
        app.descendants(matching: .any)
            .matching(NSPredicate(format: "label BEGINSWITH %@", "Similar to your"))
            .firstMatch
    }

    func testCardStartsIdleAndDoesNotFetchOnItsOwn() {
        launch(windowScenario: "confident")

        // Auto-refresh ships OFF, so the card must be sitting idle with nothing
        // fetched until the surfer asks for it.
        let idle = app.staticTexts["window.card.idle"]
        XCTAssertTrue(idle.waitForExistence(timeout: 5), "card did not start in its idle state")
        XCTAssertTrue(checkButton.waitForExistence(timeout: 3), "no Check conditions button")
        XCTAssertFalse(app.staticTexts["window.card.time"].exists, "a window appeared without being asked for")
    }

    func testCheckingConditionsProducesAWindowJustifiedByAPastSession() {
        launch(windowScenario: "confident")

        XCTAssertTrue(checkButton.waitForExistence(timeout: 5))
        checkButton.tap()

        let time = app.staticTexts["window.card.time"]
        XCTAssertTrue(time.waitForExistence(timeout: 10), "no window appeared for a full logbook")
        XCTAssertFalse((time.label).isEmpty, "window time range was empty")

        // Every recommendation must carry its justification: what today looks like,
        // and which of the surfer's own sessions it resembles.
        XCTAssertTrue(app.staticTexts["window.card.factors"].waitForExistence(timeout: 3),
                      "window shown without the conditions that justify it")

        // Addressed by label rather than by the identifier on the NavigationLink:
        // an identifier applied over a styled wrapper is not reliably queryable as
        // a button (see `log.hero.cta`).
        let match = matchElement
        XCTAssertTrue(match.waitForExistence(timeout: 3), "window shown without citing a past session")

        // The claim has to be checkable: tapping through reaches the real session.
        // Asserted on a detail-only element — "Trestles" alone would also match the
        // recents list we started from and would prove nothing.
        match.tap()
        XCTAssertTrue(app.buttons["session.detail.share"].firstMatch.waitForExistence(timeout: 5),
                      "the cited session did not open its detail")
    }

    /// The honesty case. With almost no rated history at this spot the card must
    /// say it cannot help yet — never a fabricated recommendation.
    func testThinLogbookShowsTheHonestLowConfidenceState() {
        launch(windowScenario: "thin")

        XCTAssertTrue(checkButton.waitForExistence(timeout: 5))
        checkButton.tap()

        let lowConfidence = app.staticTexts["window.card.lowConfidence"]
        XCTAssertTrue(lowConfidence.waitForExistence(timeout: 10),
                      "a thin logbook did not produce the low-confidence state")
        // The copy has to describe what is actually missing. It used to say "log a
        // few more rated sessions", which was false: plain sessions were discarded
        // outright, so following it changed nothing.
        let copy = lowConfidence.label.lowercased()
        XCTAssertTrue(copy.contains("conditions"),
                      "low-confidence copy does not mention the thing that is missing: \(lowConfidence.label)")
        XCTAssertFalse(copy.contains("log a few more"),
                       "still telling the surfer to do the thing that does not help")

        XCTAssertFalse(app.staticTexts["window.card.time"].exists,
                       "invented a window from a logbook too thin to support one")
        XCTAssertFalse(matchElement.exists,
                       "cited a past session while claiming there was not enough history")
    }

    /// A card that cannot recommend anything is still allowed to be useful. The
    /// forecast is true even when the surfer's history cannot interpret it, so the
    /// day's real conditions are shown — clearly labelled as conditions, never as
    /// a recommendation.
    func testLowConfidenceStateStillShowsTheRealConditions() {
        launch(windowScenario: "thin")

        XCTAssertTrue(checkButton.waitForExistence(timeout: 5))
        checkButton.tap()

        let conditions = app.staticTexts["window.card.conditions"]
        XCTAssertTrue(conditions.waitForExistence(timeout: 10),
                      "the low-confidence card showed no conditions at all")
        XCTAssertFalse(conditions.label.isEmpty, "conditions row was empty")
        // Labelled honestly: this is a report, not advice.
        XCTAssertTrue(app.staticTexts["Forecast conditions, not a recommendation."].exists,
                      "conditions were shown without saying they are not a recommendation")
        XCTAssertFalse(app.staticTexts["window.card.time"].exists,
                       "a window appeared alongside the low-confidence state")
    }

    /// A spot with no coordinates cannot be forecast, but that is a fixable
    /// problem. The card used to render literally nothing for these — no card, no
    /// explanation — which is how the whole feature stayed invisible for anyone
    /// whose home break came from an import.
    func testUnlocatedSpotExplainsItselfAndOffersToFixIt() {
        launch(windowScenario: "unlocated")

        let explanation = app.staticTexts["window.card.needsLocation"]
        XCTAssertTrue(explanation.waitForExistence(timeout: 5),
                      "the card rendered nothing for a spot with no coordinates")
        XCTAssertTrue(explanation.label.contains("Ocean Beach"),
                      "the explanation did not name the spot: \(explanation.label)")

        // And the fix is one tap away, not buried in another tab.
        let addLocation = app.buttons["Add location"]
        XCTAssertTrue(addLocation.waitForExistence(timeout: 3), "no way to add the missing location")
        addLocation.tap()
        XCTAssertTrue(app.textFields["spot.editor.name"].waitForExistence(timeout: 5),
                      "Add location did not open the spot editor")
    }

    /// The action that actually bootstraps personalisation. Explicit tap only, and
    /// the summary has to be honest about how many sessions it managed.
    func testFillingInPastConditionsReportsWhatItManaged() {
        app = XCUIApplication()
        app.launchEnvironment["UITESTS"] = "1"
        app.launchEnvironment["UITESTS_CLASSIC_NAVIGATION"] = "1"
        app.launchEnvironment["UITESTS_DISABLE_ANIMATIONS"] = "1"
        // Deliberately no fixed seed date: eligibility is measured against the
        // provider's ~92-day archive horizon and the real clock, so the seeded
        // sessions have to be genuinely recent to be fillable.
        app.launchEnvironment["UITESTS_SURF_CONDITIONS_SCENARIO"] = "success"
        app.launch()
        tapLogTab()

        let fill = app.buttons["Fill in past conditions"]
        XCTAssertTrue(fill.waitForExistence(timeout: 5),
                      "no way to fill in conditions for sessions logged without them")
        fill.tap()

        let summary = app.staticTexts["window.card.backfillSummary"]
        XCTAssertTrue(summary.waitForExistence(timeout: 30), "the backfill never reported a result")
        XCTAssertTrue(summary.label.contains("Filled in"),
                      "backfill did not fill anything in: \(summary.label)")
        // Having filled everything it could, the offer goes away rather than
        // inviting a pointless second run.
        XCTAssertFalse(fill.exists, "still offering to fill in conditions with nothing left to fill")
    }

    func testForecastFailureIsReportedWithoutClaimingAWindow() {
        launch(windowScenario: "error")

        XCTAssertTrue(checkButton.waitForExistence(timeout: 5))
        checkButton.tap()

        XCTAssertTrue(app.staticTexts["window.card.error"].waitForExistence(timeout: 10),
                      "a failed fetch did not surface an error")
        XCTAssertFalse(app.staticTexts["window.card.time"].exists,
                       "showed a window despite the forecast failing")
    }

    func testSettingsExposesTheAutoRefreshOptIn() {
        launch(windowScenario: nil)

        tapTab(named: "More")

        let settings = app.buttons["more.settings"]
        XCTAssertTrue(settings.waitForExistence(timeout: 5))
        settings.tap()

        let toggle = app.switches["settings.window.autoRefresh"]
        var swipes = 0
        while !toggle.exists && swipes < 8 {
            app.swipeUp()
            swipes += 1
        }
        XCTAssertTrue(toggle.waitForExistence(timeout: 5), "auto-refresh toggle missing from Settings")
        // Ships off: Peak does not fetch until asked.
        XCTAssertEqual(toggle.value as? String, "0", "auto-refresh was on by default")
    }
}

private extension PeakUISmokeTests {
    func tapTab(named name: String, file: StaticString = #filePath, line: UInt = #line) {
        let tabButton = app.tabBars.buttons[name]
        if tabButton.waitForExistence(timeout: 3) {
            if tabButton.isHittable {
                tabButton.tap()
            } else {
                tabButton.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
            }
            return
        }

        let predicate = NSPredicate(format: "label == %@", name)

        if let element = firstHittable(in: app.buttons.matching(predicate)) {
            element.tap()
            return
        }

        if let element = firstHittable(in: app.cells.matching(predicate)) {
            element.tap()
            return
        }

        if let element = firstHittable(in: app.otherElements.matching(predicate)) {
            element.tap()
            return
        }

        XCTFail("Missing tab: \(name)", file: file, line: line)
    }

    func tapRow(label: String, file: StaticString = #filePath, line: UInt = #line) {
        if app.buttons[label].exists {
            app.buttons[label].tap()
            return
        }
        if app.staticTexts[label].exists {
            app.staticTexts[label].tap()
            return
        }
        XCTFail("Missing row: \(label)", file: file, line: line)
    }

    func selectSpotSuggestion(key: String, file: StaticString = #filePath, line: UInt = #line) {
        dismissKeyboard()

        let exactChips = app.buttons.matching(identifier: "session.editor.spotSuggestion.\(key)")
        if exactChips.firstMatch.waitForExistence(timeout: 2),
           let exactChip = firstHittable(in: exactChips) {
            tapElement(exactChip)
            return
        }

        let quickStartChips = app.buttons.matching(identifier: "session.editor.quickStartSpot.\(key)")
        if quickStartChips.firstMatch.waitForExistence(timeout: 2),
           let quickStartChip = firstHittable(in: quickStartChips) {
            tapElement(quickStartChip)
            return
        }

        XCTFail("Missing spot suggestion for key: \(key)", file: file, line: line)
    }

    func selectSpot(key: String, fallbackText: String, file: StaticString = #filePath, line: UInt = #line) {
        let quickStartChips = app.buttons.matching(identifier: "session.editor.quickStartSpot.\(key)")
        if quickStartChips.firstMatch.waitForExistence(timeout: 1),
           let quickStartChip = firstHittable(in: quickStartChips) {
            tapElement(quickStartChip)
            return
        }

        let spotField = app.textFields["session.editor.spot"]
        assertExists(spotField, file: file, line: line)
        tapElement(spotField)
        spotField.typeText(fallbackText)
        selectSpotSuggestion(key: key, file: file, line: line)
    }

    /// Dismisses the keyboard and confirms it actually went away.
    ///
    /// A single tap on empty chrome is not reliable: whether it lands on
    /// something that resigns first responder depends on the sheet's layout. A
    /// keyboard that silently stays up hides the bottom of the editor, and every
    /// later `scrollToVisible` then spins against content it can never reach —
    /// which reads as a broken control rather than a stuck keyboard.
    func dismissKeyboard() {
        guard app.keyboards.firstMatch.exists else { return }
        app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.12)).tap()
        if app.keyboards.firstMatch.waitForNonExistence(timeout: 2) { return }

        // Fall back to the keyboard's own dismiss affordances before giving up.
        for label in ["Done", "return", "Return"] where app.keyboards.buttons[label].exists {
            app.keyboards.buttons[label].tap()
            if app.keyboards.firstMatch.waitForNonExistence(timeout: 2) { return }
        }
        app.swipeDown()
        _ = app.keyboards.firstMatch.waitForNonExistence(timeout: 2)
    }

    func tapElement(_ element: XCUIElement) {
        if element.isHittable {
            element.tap()
        } else {
            element.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
        }
    }

    func assertExists(_ element: XCUIElement, timeout: TimeInterval = 3, file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertTrue(element.waitForExistence(timeout: timeout), "Missing element: \(element)", file: file, line: line)
    }

    /// Scrolls until `element`'s centre sits inside the scroll view, in whichever
    /// direction is needed.
    ///
    /// Two traps this avoids. First, `isHittable` is true for an element whose
    /// frame merely *overlaps* the viewport, so a field hanging off the bottom
    /// edge passes the check while a tap at its centre lands off-screen and
    /// silently fails to take focus. Centre containment is the property taps
    /// actually depend on. Second, a swipe carries momentum — one can move this
    /// app's editor by ~670pt, more than a phone viewport — so a target can pass
    /// from below the fold to above it between two checks; a loop that only ever
    /// swipes up then pins itself at the end of the content with the element
    /// unreachable above.
    func scrollToVisible(_ element: XCUIElement, in scrollView: XCUIElement, maxSwipes: Int = 8) {
        guard scrollView.exists else { return }
        var attempts = 0
        while !isCentreVisible(element, in: scrollView) && attempts < maxSwipes {
            if element.exists, element.frame.height > 0 {
                let visible = visibleContentFrame(in: scrollView)
                // Full swipes can alternate above/below a short iPad sheet
                // forever. Once AX has a frame, move toward the visible centre
                // by a measured distance and release without flick momentum.
                let limit = visible.height * 0.45
                let delta = min(limit, max(-limit, visible.midY - element.frame.midY))
                guard abs(delta) > 1 else { break }
                let origin = scrollView.coordinate(withNormalizedOffset: .zero)
                // Trailing scroll padding avoids dragging an editable slider.
                let x = visible.maxX - scrollView.frame.minX - 4
                let startY = visible.midY - delta / 2 - scrollView.frame.minY
                let start = origin.withOffset(CGVector(dx: x, dy: startY))
                let end = origin.withOffset(CGVector(dx: x, dy: startY + delta))
                start.press(forDuration: 0.05, thenDragTo: end, withVelocity: .slow, thenHoldForDuration: 0.1)
            } else {
                scrollView.swipeUp()
            }
            attempts += 1
        }
    }

    private func isCentreVisible(_ element: XCUIElement, in scrollView: XCUIElement) -> Bool {
        guard element.exists, element.isHittable else { return false }
        let frame = element.frame
        guard frame.height > 0 else { return false }
        return visibleContentFrame(in: scrollView).contains(CGPoint(x: frame.midX, y: frame.midY))
    }

    private func visibleContentFrame(in scrollView: XCUIElement) -> CGRect {
        var visible = scrollView.frame
        // A sheet's ScrollView extends behind its navigation bar on iPad.
        // AX can call a partly covered button hittable even when its centre is
        // under Cancel/Save. Exclude that chrome for BOTH visibility and scroll
        // direction; otherwise a target above the usable viewport scrolls away.
        for bar in app.navigationBars.allElementsBoundByIndex where bar.exists {
            let frame = bar.frame
            if frame.intersects(visible), frame.maxY < visible.maxY {
                let bottom = visible.maxY
                visible.origin.y = frame.maxY
                visible.size.height = bottom - frame.maxY
            }
        }
        // A centre resting exactly on an edge is not reliably tappable.
        return visible.insetBy(dx: 8, dy: 8)
    }

    func showOptionalFields(in scrollView: XCUIElement, file: StaticString = #filePath, line: UInt = #line) {
        if app.buttons["Hide optional fields"].exists {
            return
        }

        // The streamlined editor force-expands optional sections under UI tests, so the toggle may
        // not exist; only tap it when present (older editor layout).
        let showButton = app.buttons["Show optional fields"]
        if showButton.waitForExistence(timeout: 1) {
            scrollToVisible(showButton, in: scrollView)
            showButton.tap()
        }
    }

    func saveSession(file: StaticString = #filePath, line: UInt = #line) {
        let primarySave = app.buttons["Save Session"]
        if primarySave.waitForExistence(timeout: 2) {
            primarySave.tap()
            return
        }

        let toolbarSave = app.buttons["Save"]
        assertExists(toolbarSave, file: file, line: line)
        toolbarSave.tap()
    }

    func assertConditionsNotice(
        beginsWith prefix: String? = nil,
        contains substring: String? = nil,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        let notice = app.descendants(matching: .any)["session.editor.conditionsNotice"]
        // iPad's larger accessibility hierarchy can delay publication of the
        // async result during a busy full-suite run even though the mock throws
        // immediately. Ten seconds keeps the assertion deterministic without
        // weakening the expected message check below.
        assertExists(notice, timeout: 10, file: file, line: line)

        if let prefix {
            XCTAssertTrue(
                notice.label.lowercased().hasPrefix(prefix.lowercased()),
                "Expected conditions notice to begin with \(prefix), got: \(notice.label)",
                file: file,
                line: line
            )
        }

        if let substring {
            XCTAssertTrue(
                notice.label.localizedCaseInsensitiveContains(substring),
                "Expected conditions notice to contain \(substring), got: \(notice.label)",
                file: file,
                line: line
            )
        }
    }

    func latestHistoryRow(
        markerSessionNote: String? = nil,
        timeout: TimeInterval = 5,
        file: StaticString = #filePath,
        line: UInt = #line
    ) -> XCUIElement {
        if markerSessionNote != nil,
           let row = firstHit(of: app.buttons.matching(identifier: "history.row.test-marker"), timeout: timeout) {
            return row
        }

        if let row = firstHit(of: app.buttons.matching(identifier: "history.row"), timeout: timeout) {
            return row
        }

        if let row = firstHit(of: app.otherElements.matching(identifier: "history.row"), timeout: timeout) {
            return row
        }

        if let row = firstHit(of: app.cells.matching(identifier: "history.row"), timeout: timeout) {
            return row
        }

        if let row = firstHit(of: app.cells.containing(.staticText, identifier: "Trestles"), timeout: timeout) {
            return row
        }

        let firstCell = app.cells.firstMatch
        if firstCell.waitForExistence(timeout: timeout) {
            return firstCell
        }

        XCTFail("Missing history row in list", file: file, line: line)
        return firstCell
    }

    func firstHittable(in query: XCUIElementQuery) -> XCUIElement? {
        let elements = query.allElementsBoundByIndex
        if let hittable = elements.first(where: { $0.exists && $0.isHittable }) {
            return hittable
        }
        if let first = elements.first, first.exists {
            return first
        }
        return nil
    }

    func firstHit(of query: XCUIElementQuery, timeout: TimeInterval) -> XCUIElement? {
        guard query.firstMatch.waitForExistence(timeout: timeout) else {
            return nil
        }
        return firstHittable(in: query)
    }

}

/// Not part of the regression suite: captures App Store marketing screenshots
/// with seeded data. Run explicitly via
/// `UI_TEST_TARGET="PeakUITests/MarketingScreenshotCapture" ./scripts/test-ui.sh`.
final class MarketingScreenshotCapture: XCTestCase {
    private var app: XCUIApplication!

    override func setUp() {
        super.setUp()
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchEnvironment["UITESTS"] = "1"
        app.launchEnvironment["UITESTS_CLASSIC_NAVIGATION"] = "1"
        app.launchEnvironment["UITESTS_DISABLE_ANIMATIONS"] = "1"
        app.launchEnvironment["UITESTS_FIXED_DATE"] = "2026-06-10T12:00:00Z"
        app.launchEnvironment["PEAK_SCREENSHOTS"] = "1"
        app.launch()
    }

    override func tearDown() {
        app = nil
        super.tearDown()
    }

    func testCaptureMarketingScreenshots() {
        tapTab("Log")
        capture("01-log")

        tapTab("History")
        capture("02-history")

        // Open the media-rich session (the seeded "Trestles" session carries a photo
        // and a video) so the session-detail shot showcases the media-forward hero
        // strip. Fall back to the first row if the labeled row can't be found.
        let historyRows = app.buttons.matching(identifier: "history.row")
        let mediaRow = historyRows
            .containing(NSPredicate(format: "label CONTAINS[c] %@", "Trestles"))
            .firstMatch
        let sessionRow = mediaRow.waitForExistence(timeout: 3) ? mediaRow : historyRows.firstMatch
        if sessionRow.waitForExistence(timeout: 3) {
            sessionRow.tap()
            _ = app.staticTexts.firstMatch.waitForExistence(timeout: 3)
            sleep(1)
            capture("03-session-detail")
        }

        tapTab("Stats")
        sleep(1)
        capture("04-stats")

        tapTab("Quiver")
        sleep(1)
        capture("05-quiver")
    }

    private func tapTab(_ name: String) {
        // iPhone presents a bottom tab bar; iPadOS renders the tab strip at
        // the top, where tabs may not live inside an XCUI tabBars container.
        let tab = app.tabBars.buttons[name]
        if tab.waitForExistence(timeout: 3) {
            tab.tap()
        } else {
            let anyTab = app.buttons[name].firstMatch
            XCTAssertTrue(anyTab.waitForExistence(timeout: 5), "Tab \(name) not found")
            anyTab.tap()
        }
        sleep(1)
    }

    private func capture(_ name: String) {
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot(), quality: .original)
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}

/// First-run welcome. Every other UI test launches with the welcome suppressed
/// (that is what keeps the pre-2.9 baselines valid), so this suite forces it on
/// with `UITESTS_SHOW_WELCOME` and also proves the suppression still holds.
final class PeakWelcomeUITests: XCTestCase {
    private var app: XCUIApplication!

    override func setUp() {
        super.setUp()
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchEnvironment["UITESTS"] = "1"
        app.launchEnvironment["UITESTS_CLASSIC_NAVIGATION"] = "1"
        app.launchEnvironment["UITESTS_DISABLE_ANIMATIONS"] = "1"
        app.launchEnvironment["UITESTS_FIXED_DATE"] = "2026-02-01T12:00:00Z"
    }

    override func tearDown() {
        app = nil
        super.tearDown()
    }

    func testWelcomeWalkthroughEndsInTheEditor() {
        app.launchEnvironment["UITESTS_SHOW_WELCOME"] = "1"
        app.launch()

        XCTAssertTrue(
            app.staticTexts["Your surf logbook"].waitForExistence(timeout: 10),
            "Expected the first welcome screen"
        )

        let firstNext = app.buttons["welcome.next"]
        XCTAssertTrue(firstNext.waitForExistence(timeout: 3))
        firstNext.tap()

        XCTAssertTrue(
            app.staticTexts["Stays on your phone"].waitForExistence(timeout: 3),
            "Expected the privacy promise screen"
        )

        let secondNext = app.buttons["welcome.next"]
        XCTAssertTrue(secondNext.waitForExistence(timeout: 3))
        secondNext.tap()

        XCTAssertTrue(
            app.staticTexts["Log your first session"].waitForExistence(timeout: 3),
            "Expected the CTA screen"
        )

        let cta = app.buttons["welcome.cta"]
        XCTAssertTrue(cta.waitForExistence(timeout: 3))
        cta.tap()

        // The CTA dismisses the welcome and opens the new-session editor.
        XCTAssertTrue(
            app.textFields["session.editor.spot"].waitForExistence(timeout: 10),
            "Expected the session editor to open from the welcome CTA"
        )
    }

    func testWelcomeSkipReturnsToTheLogTab() {
        app.launchEnvironment["UITESTS_SHOW_WELCOME"] = "1"
        app.launch()

        let skip = app.buttons["welcome.skip"]
        XCTAssertTrue(skip.waitForExistence(timeout: 10))
        skip.tap()

        XCTAssertTrue(app.buttons["Log Session"].waitForExistence(timeout: 10))
        XCTAssertFalse(app.buttons["welcome.cta"].exists)
    }

    func testWelcomeIsSuppressedOnAPlainUITestLaunch() {
        app.launch()

        XCTAssertTrue(
            app.buttons["Log Session"].waitForExistence(timeout: 10),
            "A plain UI-test launch must land on the Log tab, not the welcome"
        )
        XCTAssertFalse(app.buttons["welcome.next"].exists)
        XCTAssertFalse(app.buttons["welcome.cta"].exists)
    }
}

// MARK: - On-device insights (3.2)

/// The 3.2 surfaces, tested on a simulator that has no Apple Intelligence and
/// never will.
///
/// Two things have to hold and both are checked here:
///  * with no model, the recap and the year paragraph still render, in full,
///    from the aggregates — the feature's absence must be invisible;
///  * with the model boundary stubbed, the AI layout renders and carries its
///    privacy line — so the half of the UI a simulator cannot reach still cannot
///    rot unnoticed.
///
/// The stub is a fixed string injected at the `InsightsGenerating` seam. No test
/// in this class touches, or depends on, a real model response.
final class PeakInsightsUITests: XCTestCase {
    private var app: XCUIApplication!

    /// The canned draft `StubInsightsGenerator` returns.
    private let stubbedHeadline = "A solid stretch in the water"
    private let privacyLine = "Written on this iPhone. Your logbook never leaves it."

    override func tearDown() {
        app = nil
        super.tearDown()
    }

    /// Anchors the seeded logbook to the 20th of the *current* real month.
    ///
    /// The recap card is about "this month", and the app reads that from the real
    /// clock. Pinning the seed to a fixed calendar date would leave the current
    /// month empty and the card correctly hidden; pinning it to `Date()` would
    /// break on the first of the month, when the -7 and -14 day sessions fall
    /// into the previous one. The 20th is inside every month and leaves every
    /// seeded session in it.
    private func launch(insightsScenario: String? = nil) {
        app = XCUIApplication()
        app.launchEnvironment["UITESTS"] = "1"
        app.launchEnvironment["UITESTS_CLASSIC_NAVIGATION"] = "1"
        app.launchEnvironment["UITESTS_DISABLE_ANIMATIONS"] = "1"
        app.launchEnvironment["UITESTS_FIXED_DATE"] = Self.currentMonthAnchor()
        if let insightsScenario {
            app.launchEnvironment["UITESTS_INSIGHTS_SCENARIO"] = insightsScenario
        }
        app.launch()
    }

    private static func currentMonthAnchor() -> String {
        let calendar = Calendar.current
        var components = calendar.dateComponents([.year, .month], from: Date())
        components.day = 20
        components.hour = 12
        let anchor = calendar.date(from: components) ?? Date()
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.string(from: anchor)
    }

    private var expectedTitle: String {
        "\(Date().formatted(.dateTime.month(.wide))) recap"
    }

    /// The card, addressed by its merged accessibility element rather than by an
    /// identifier — identifiers on content inside a ScrollView clobber each other.
    private var recapCard: XCUIElement {
        app.descendants(matching: .any)
            .matching(NSPredicate(format: "label == %@", expectedTitle))
            .firstMatch
    }

    private func openStats() {
        tapTab(named: "Stats")
    }

    private func tapTab(named name: String, file: StaticString = #filePath, line: UInt = #line) {
        let tabButton = app.tabBars.buttons[name]
        if tabButton.waitForExistence(timeout: 10) {
            if tabButton.isHittable {
                tabButton.tap()
            } else {
                tabButton.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
            }
            return
        }

        let predicate = NSPredicate(format: "label == %@", name)

        if let element = firstHittable(in: app.buttons.matching(predicate)) {
            element.tap()
            return
        }

        if let element = firstHittable(in: app.cells.matching(predicate)) {
            element.tap()
            return
        }

        if let element = firstHittable(in: app.otherElements.matching(predicate)) {
            element.tap()
            return
        }

        XCTFail("Missing tab: \(name)", file: file, line: line)
    }

    private func firstHittable(in query: XCUIElementQuery) -> XCUIElement? {
        let elements = query.allElementsBoundByIndex
        if let hittable = elements.first(where: { $0.exists && $0.isHittable }) {
            return hittable
        }
        if let first = elements.first, first.exists {
            return first
        }
        return nil
    }

    func testMonthlyRecapRendersFromAggregatesWithoutAnyModel() {
        launch()
        openStats()

        XCTAssertTrue(recapCard.waitForExistence(timeout: 10), "No monthly recap card on Stats")

        let value = recapCard.value as? String ?? ""
        XCTAssertTrue(
            value.contains("session"),
            "The recap did not lead with its figures: \(value)"
        )
        XCTAssertTrue(
            value.contains("Most days at"),
            "The recap dropped its plain-stats highlights: \(value)"
        )
    }

    /// The graceful-absence requirement, stated as an assertion: with no model on
    /// the device, nothing on screen refers to one.
    func testNothingHintsAtAModelWhenThereIsNoneOnTheDevice() {
        launch()
        openStats()

        XCTAssertTrue(recapCard.waitForExistence(timeout: 10))
        let value = recapCard.value as? String ?? ""

        XCTAssertFalse(value.contains(privacyLine), "Privacy note shown with no model behind it")
        XCTAssertFalse(value.contains(stubbedHeadline))
        XCTAssertFalse(
            app.staticTexts[privacyLine].exists,
            "A device with no Apple Intelligence must show no trace of the feature"
        )
    }

    func testStubbedInsightRendersAlongsideTheFiguresAndItsPrivacyNote() {
        launch(insightsScenario: "stub")
        openStats()

        XCTAssertTrue(recapCard.waitForExistence(timeout: 10))

        // The prose is additive: the figures are still there next to it.
        let value = NSPredicate(format: "value CONTAINS %@", stubbedHeadline)
        XCTAssertTrue(
            recapCard.waitForExistence(timeout: 5) && value.evaluate(with: recapCard),
            "Generated prose never reached the card: \(recapCard.value as? String ?? "")"
        )

        let full = recapCard.value as? String ?? ""
        XCTAssertTrue(full.contains("session"), "Prose replaced the figures instead of joining them")
        XCTAssertTrue(full.contains(privacyLine), "Generated text shown without saying where it came from")
    }

    func testYearInReviewAlwaysCarriesANarrativeParagraph() {
        launch()

        tapTab(named: "More")

        let entry = app.buttons["more.yearInReview"]
        XCTAssertTrue(entry.waitForExistence(timeout: 5), "Year in Review entry was not accessible")
        entry.tap()

        let summary = app.descendants(matching: .any)
            .matching(NSPredicate(format: "label == %@", "Year summary"))
            .firstMatch
        XCTAssertTrue(summary.waitForExistence(timeout: 10), "Year in Review had no narrative paragraph")

        let text = summary.value as? String ?? ""
        XCTAssertTrue(text.contains("You logged"), "The plain narrative did not render: \(text)")
        XCTAssertFalse(text.contains(privacyLine), "Claimed on-device authorship with no model present")
    }
}

// MARK: - Marketing screenshot capture

/// Regenerates the App Store screenshot set. Skipped unless `PEAK_SHOT_DIR` is
/// exported for the run, so the normal UI gate is unaffected (it reports one
/// skipped test, not one more executed test).
///
/// Replaces the `PeakAdCaptureFlowTests` harness that was dropped from the
/// project; folded in here because `PeakUITests` is not a synchronized group and
/// a standalone file would be invisible to the build (AGENTS.md rule 3).
///
///     PEAK_SHOT_DIR=/tmp/shots/iphone xcodebuild test \
///       -only-testing:PeakUITests/PeakMarketingCaptureTests ...
///
/// Seeded, fictional data only — Apple requires screenshots show the app in use
/// with fictional content. Insights are deliberately NOT stubbed: the captured
/// Stats screen is the plain one every device renders, never the Apple
/// Intelligence layout that only some hardware can show.
final class PeakMarketingCaptureTests: XCTestCase {
    private var app: XCUIApplication!
    private var shotDirectory: URL!

    override func setUpWithError() throws {
        try super.setUpWithError()
        continueAfterFailure = false

        guard let path = ProcessInfo.processInfo.environment["PEAK_SHOT_DIR"] else {
            throw XCTSkip("Set PEAK_SHOT_DIR to capture App Store screenshots")
        }
        shotDirectory = URL(fileURLWithPath: path, isDirectory: true)
        try FileManager.default.createDirectory(at: shotDirectory, withIntermediateDirectories: true)

        XCUIDevice.shared.orientation = .portrait

        app = XCUIApplication()
        app.launchEnvironment["UITESTS"] = "1"
        app.launchEnvironment["UITESTS_CLASSIC_NAVIGATION"] = "1"
        app.launchEnvironment["PEAK_SCREENSHOTS"] = "1"
        app.launchEnvironment["UITESTS_DISABLE_ANIMATIONS"] = "1"
        // Deliberately no UITESTS_FIXED_DATE: the seed dates every session
        // relative to its base date, so pinning the past leaves the
        // recent-weeks surfaces (streak, consistency heatmap, monthly goal)
        // empty. Seeding from "now" is what makes Stats look alive.
        app.launchEnvironment["UITESTS_WINDOW_SCENARIO"] = "confident"
        app.launchEnvironment["UITESTS_SURF_CONDITIONS_SCENARIO"] = "success"
        app.launch()
    }

    override func tearDown() {
        app = nil
        super.tearDown()
    }

    func testCaptureAppStoreScreenshots() throws {
        tapTab("Log")
        _ = app.staticTexts["Peak"].waitForExistence(timeout: 8)
        // Left on the Best Window card's call to action deliberately. Tapping
        // it here would render the canned UI-test forecast, whose hours ignore
        // the daylight filter the real service applies — a late-night "best
        // window" is a fixture artefact, not the product, and has no place in
        // a store screenshot.
        settle()
        try capture("01-log")

        tapTab("History")
        _ = app.staticTexts["Trestles"].firstMatch.waitForExistence(timeout: 8)
        settle()
        try capture("02-history")

        let session = app.staticTexts["Trestles"].firstMatch
        if session.exists {
            tap(session)
            settle()
            try capture("03-session-detail")
            back()
        }

        tapTab("Stats")
        settle()
        // Scroll to the charts. Two swipes clears the counters, the
        // monthly-goal ring (an empty opt-in state until a target is set) and
        // the monthly recap card. The recap is deliberately out of frame: on a
        // machine with Apple Intelligence it renders its on-device authorship
        // line, and a screenshot must not advertise a surface that a reviewer
        // on ineligible hardware would never see.
        app.swipeUp()
        settle(0.5)
        app.swipeUp()
        settle()
        try capture("04-stats")

        tapTab("Quiver")
        settle()
        try capture("05-quiver")

        tapTab("More")
        let recap = app.buttons["Year in Review"].firstMatch
        if recap.waitForExistence(timeout: 4) {
            tap(recap)
            settle()
            try capture("06-year-in-review")
        }
    }

    // MARK: Helpers

    private func tapTab(_ name: String) {
        // The tab bar minimizes on scroll (iOS 26), so a tab we just scrolled
        // past is genuinely absent until the content is scrolled back to the
        // top — which can take several swipes on a long tab like Stats.
        for attempt in 0..<6 {
            let tab = app.tabBars.buttons[name]
            if tab.waitForExistence(timeout: attempt == 0 ? 5 : 1), tab.isHittable {
                tap(tab)
                return
            }
            let button = app.buttons.matching(NSPredicate(format: "label == %@", name)).firstMatch
            if button.exists, button.isHittable {
                tap(button)
                return
            }
            app.swipeDown()
            settle(0.5)
        }
        XCTFail("Missing tab: \(name)")
    }

    private func back() {
        let backButton = app.navigationBars.buttons.element(boundBy: 0)
        if backButton.exists && backButton.isHittable {
            backButton.tap()
            settle()
        }
    }

    private func tap(_ element: XCUIElement) {
        if element.isHittable {
            element.tap()
        } else {
            element.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
        }
    }

    private func settle(_ seconds: TimeInterval = 1.2) {
        Thread.sleep(forTimeInterval: seconds)
    }

    /// Writes an opaque PNG: App Store screenshots may not carry an alpha
    /// channel, and `XCUIScreen.pngRepresentation` includes one.
    private func capture(_ name: String) throws {
        let shot = XCUIScreen.main.screenshot()
        let url = shotDirectory.appendingPathComponent("\(name).png")
        try shot.pngRepresentation.write(to: url, options: .atomic)

        let attachment = XCTAttachment(screenshot: shot)
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
