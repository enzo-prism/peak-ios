import CoreGraphics
import Foundation
import XCTest

final class PeakUILayoutTests: XCTestCase {
    private var app: XCUIApplication!

    override func setUp() {
        super.setUp()
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchEnvironment["UITESTS"] = "1"
        app.launchEnvironment["UITESTS_DISABLE_ANIMATIONS"] = "1"
        app.launch()
    }

    override func tearDown() {
        XCUIDevice.shared.orientation = .portrait
        app = nil
        super.tearDown()
    }

    func testLogLayoutFits() {
        tapTab(named: "Log")

        let heroTitle = app.staticTexts["Peak"]
        assertExists(heroTitle)
        assertFits(heroTitle)

        let heroCTA = app.buttons["Log Session"]
        assertExists(heroCTA)
        assertFits(heroCTA)

        let recentTitle = app.staticTexts["Recent sessions"]
        if recentTitle.waitForExistence(timeout: 2) {
            assertFits(recentTitle)
        }

        let row = app.staticTexts["Trestles"]
        if row.waitForExistence(timeout: 2) {
            assertFits(row)
        }

        attachScreenshot(name: "Log")
    }

    func testHistoryLayoutFits() {
        tapTab(named: "History")

        let row = app.staticTexts["Trestles"]
        assertExists(row)
        assertFits(row)

        attachScreenshot(name: "History")
    }

    func testStatsLayoutFits() {
        tapTab(named: "Stats")

        let sessionsCard = app.staticTexts["SESSIONS"]
        assertExists(sessionsCard)
        assertFits(sessionsCard)

        let avgCard = app.staticTexts["AVG RATING"]
        assertExists(avgCard)
        assertFits(avgCard)

        attachScreenshot(name: "Stats")
    }

    func testSessionEditorLayoutFits() {
        tapTab(named: "Log")

        let heroCTA = app.buttons["Log Session"]
        assertExists(heroCTA)
        heroCTA.tap()

        let datePicker = app.datePickers.firstMatch
        assertExists(datePicker)
        assertFits(datePicker)

        let spotField = app.textFields["Spot"]
        assertExists(spotField)
        assertFits(spotField)

        let gearField = app.textFields["Add gear"]
        assertExists(gearField)
        assertFits(gearField)

        let ratingButton = app.buttons["Rate 1 stars"]
        assertExists(ratingButton)

        let notes = app.textViews.firstMatch
        let scrollView = app.scrollViews.firstMatch
        if notes.exists {
            scrollToVisible(notes, in: scrollView)
            assertFits(notes)
        }

        attachScreenshot(name: "Editor")
    }

    func testLogLayoutFitsLandscape() {
        XCUIDevice.shared.orientation = .landscapeLeft
        defer { XCUIDevice.shared.orientation = .portrait }

        tapTab(named: "Log")

        let heroTitle = app.staticTexts["Peak"]
        assertExists(heroTitle)
        assertFits(heroTitle)

        let heroCTA = app.buttons["Log Session"]
        assertExists(heroCTA)
        assertFits(heroCTA)

        attachScreenshot(name: "Log Landscape")
    }
}

private extension PeakUILayoutTests {
    func tapTab(named name: String, file: StaticString = #filePath, line: UInt = #line) {
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

    func assertExists(_ element: XCUIElement, timeout: TimeInterval = 3, file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertTrue(element.waitForExistence(timeout: timeout), "Missing element: \(element)", file: file, line: line)
    }

    func assertFits(_ element: XCUIElement, file: StaticString = #filePath, line: UInt = #line) {
        let window = app.windows.firstMatch
        XCTAssertTrue(window.exists, "Missing app window", file: file, line: line)

        let windowFrame = window.frame
        let elementFrame = element.frame
        let tolerance: CGFloat = 2

        XCTAssertGreaterThanOrEqual(elementFrame.minX, windowFrame.minX - tolerance, "\(element) minX out of bounds", file: file, line: line)
        XCTAssertGreaterThanOrEqual(elementFrame.minY, windowFrame.minY - tolerance, "\(element) minY out of bounds", file: file, line: line)
        XCTAssertLessThanOrEqual(elementFrame.maxX, windowFrame.maxX + tolerance, "\(element) maxX out of bounds", file: file, line: line)
        XCTAssertLessThanOrEqual(elementFrame.maxY, windowFrame.maxY + tolerance, "\(element) maxY out of bounds", file: file, line: line)
    }

    func scrollToVisible(_ element: XCUIElement, in scrollView: XCUIElement, maxSwipes: Int = 6) {
        guard scrollView.exists else { return }
        var attempts = 0
        while !element.isHittable && attempts < maxSwipes {
            scrollView.swipeUp()
            attempts += 1
        }
    }

    func attachScreenshot(name: String) {
        let screenshot = XCUIScreen.main.screenshot()
        let attachment = XCTAttachment(screenshot: screenshot)
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
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
