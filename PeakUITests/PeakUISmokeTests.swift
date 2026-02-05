import XCTest

final class PeakUISmokeTests: XCTestCase {
    private var app: XCUIApplication!

    override func setUp() {
        super.setUp()
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchEnvironment["UITESTS"] = "1"
        app.launchEnvironment["UITESTS_DISABLE_ANIMATIONS"] = "1"
        app.launchEnvironment["UITESTS_FIXED_DATE"] = "2026-02-01T12:00:00Z"
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
        spotField.typeText("Trestles")

        tapRow(label: "Trestles")

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

    func assertExists(_ element: XCUIElement, timeout: TimeInterval = 3, file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertTrue(element.waitForExistence(timeout: timeout), "Missing element: \(element)", file: file, line: line)
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

}
