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
        autoFillButton.tap()

        assertConditionsNotice(contains: "Surf report data is unavailable")
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
        XCTAssertTrue(lowConfidence.label.contains("log a few more") || lowConfidence.label.contains("Log a few more"),
                      "unexpected low-confidence copy: \(lowConfidence.label)")

        XCTAssertFalse(app.staticTexts["window.card.time"].exists,
                       "invented a window from a logbook too thin to support one")
        XCTAssertFalse(matchElement.exists,
                       "cited a past session while claiming there was not enough history")
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

        let tab = app.tabBars.buttons["More"]
        XCTAssertTrue(tab.waitForExistence(timeout: 5))
        tab.tap()

        let settings = app.buttons["Settings"]
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

    func dismissKeyboard() {
        guard app.keyboards.firstMatch.exists else { return }
        app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.12)).tap()
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

    func scrollToVisible(_ element: XCUIElement, in scrollView: XCUIElement, maxSwipes: Int = 8) {
        guard scrollView.exists else { return }
        var attempts = 0
        while !element.isHittable && attempts < maxSwipes {
            scrollView.swipeUp()
            attempts += 1
        }
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
        assertExists(notice, timeout: 5, file: file, line: line)

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
