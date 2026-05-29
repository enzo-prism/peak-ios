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

        let spotField = app.textFields["session.editor.spot"]
        assertExists(spotField)
        spotField.tap()
        spotField.typeText("Trestles\n")

        selectEditorSpot(key: "trestles", fallbackLabel: "Trestles")

        let saveButton = app.buttons["Save"]
        assertExists(saveButton)
        saveButton.tap()

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

        let spotField = app.textFields["session.editor.spot"]
        assertExists(spotField)
        spotField.tap()
        spotField.typeText("Trestles\n")

        selectEditorSpot(key: "trestles", fallbackLabel: "Trestles")

        setEditorDuration()

        let autoFillButton = app.buttons["session.editor.autoFillConditions"]
        assertExists(autoFillButton)
        scrollToHittable(autoFillButton)
        autoFillButton.tap()

        // Scrolling can nudge the wind/wave sliders, which prompts a replace confirmation.
        let replaceConditions = app.buttons["Replace"]
        if replaceConditions.waitForExistence(timeout: 1) {
            replaceConditions.tap()
        }

        let successNotice = conditionsNotice(containing: "Filled from Open-Meteo")
        XCTAssertTrue(
            successNotice.waitForExistence(timeout: 5),
            "Expected successful auto-fill notice. Found: \(conditionsNoticeLabel())"
        )

        let notes = app.textViews["session.editor.notes"]
        assertExists(notes)
        notes.tap()
        notes.typeText(e2eSessionMarker)

        let saveButton = app.buttons["Save"]
        assertExists(saveButton)
        saveButton.tap()

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

        let spotField = app.textFields["session.editor.spot"]
        assertExists(spotField)
        spotField.tap()
        spotField.typeText("Trestles\n")

        selectEditorSpot(key: "trestles", fallbackLabel: "Trestles")

        setEditorDuration()

        let autoFillButton = app.buttons["session.editor.autoFillConditions"]
        assertExists(autoFillButton)
        scrollToHittable(autoFillButton)
        autoFillButton.tap()

        // Scrolling can nudge the wind/wave sliders, which prompts a replace confirmation.
        let replaceConditions = app.buttons["Replace"]
        if replaceConditions.waitForExistence(timeout: 1) {
            replaceConditions.tap()
        }

        let errorNotice = conditionsNotice(containing: "Mock surf report service error")
        XCTAssertTrue(errorNotice.waitForExistence(timeout: 5), "Expected remote error notice.")
    }

    func testAutoFillConditionsShowsNoDataNotice() {
        app.terminate()
        launchAppWithUITestEnvironment(surfConditionsScenario: "no_data")
        tapTab(named: "Log")

        let cta = app.buttons["Log Session"]
        assertExists(cta)
        cta.tap()

        let spotField = app.textFields["session.editor.spot"]
        assertExists(spotField)
        spotField.tap()
        spotField.typeText("Trestles\n")

        selectEditorSpot(key: "trestles", fallbackLabel: "Trestles")

        setEditorDuration()

        let autoFillButton = app.buttons["session.editor.autoFillConditions"]
        assertExists(autoFillButton)
        scrollToHittable(autoFillButton)
        autoFillButton.tap()

        // Scrolling can nudge the wind/wave sliders, which prompts a replace confirmation.
        let replaceConditions = app.buttons["Replace"]
        if replaceConditions.waitForExistence(timeout: 1) {
            replaceConditions.tap()
        }

        let noDataNotice = conditionsNotice(containing: "Surf report data is unavailable")
        XCTAssertTrue(noDataNotice.waitForExistence(timeout: 5), "Expected no-data notice.")
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

    func conditionsNotice(containing text: String) -> XCUIElement {
        app.descendants(matching: .any).matching(
            NSPredicate(
                format: "identifier == %@ AND label CONTAINS[c] %@",
                "session.editor.conditionsNotice",
                text
            )
        ).firstMatch
    }

    func conditionsNoticeLabel() -> String {
        let notice = app.descendants(matching: .any).matching(identifier: "session.editor.conditionsNotice").firstMatch
        return notice.exists ? notice.label : "none"
    }

    func selectEditorSpot(
        key: String,
        fallbackLabel: String,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        let spotOption = app.buttons["session.editor.spotOption.\(key)"]
        if spotOption.waitForExistence(timeout: 3) {
            scrollToHittable(spotOption, maxSwipes: 4)
            if spotOption.isHittable {
                spotOption.tap()
                return
            }
        }

        let quickStartSpot = app.buttons["session.editor.quickStartSpot.\(key)"]
        if quickStartSpot.waitForExistence(timeout: 1) {
            scrollToHittable(quickStartSpot, maxSwipes: 4)
            if quickStartSpot.isHittable {
                quickStartSpot.tap()
                return
            }
        }

        tapRow(label: fallbackLabel, file: file, line: line)
    }

    func setEditorDuration(position: CGFloat = 0.5, file: StaticString = #filePath, line: UInt = #line) {
        let duration = app.sliders["session.editor.duration"]
        assertExists(duration, file: file, line: line)
        scrollToHittable(duration, maxSwipes: 2)
        duration.adjust(toNormalizedSliderPosition: position)
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

    func assertExists(_ element: XCUIElement, timeout: TimeInterval = 3, file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertTrue(element.waitForExistence(timeout: timeout), "Missing element: \(element)", file: file, line: line)
    }

    func scrollToHittable(_ element: XCUIElement, maxSwipes: Int = 8) {
        // Swipe on the app rather than scrollViews.firstMatch — the editor has nested
        // horizontal chip scroll views, so firstMatch isn't reliably the main vertical scroll.
        var attempts = 0
        while !element.isHittable && attempts < maxSwipes {
            app.swipeUp()
            attempts += 1
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
