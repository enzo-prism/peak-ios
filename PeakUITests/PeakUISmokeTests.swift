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

        let duration = app.sliders["session.editor.duration"]
        assertExists(duration)
        duration.adjust(toNormalizedSliderPosition: 0.5)

        let scrollView = app.scrollViews["session.editor.scroll"]
        showOptionalFields(in: scrollView)

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

        let duration = app.sliders["session.editor.duration"]
        assertExists(duration)
        duration.adjust(toNormalizedSliderPosition: 0.5)

        let scrollView = app.scrollViews["session.editor.scroll"]
        showOptionalFields(in: scrollView)

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

        let duration = app.sliders["session.editor.duration"]
        assertExists(duration)
        duration.adjust(toNormalizedSliderPosition: 0.5)

        let scrollView = app.scrollViews["session.editor.scroll"]
        showOptionalFields(in: scrollView)

        let autoFillButton = app.buttons["session.editor.autoFillConditions"]
        scrollToVisible(autoFillButton, in: scrollView)
        assertExists(autoFillButton)
        autoFillButton.tap()

        assertConditionsNotice(contains: "Surf report data is unavailable")
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

        let showButton = app.buttons["Show optional fields"]
        scrollToVisible(showButton, in: scrollView)
        assertExists(showButton, file: file, line: line)
        showButton.tap()
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
