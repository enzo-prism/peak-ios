import Foundation
import XCTest

final class PeakAdCaptureFlowTests: XCTestCase {
    private var app: XCUIApplication!
    private var captureDirectory: URL!

    override func setUpWithError() throws {
        try super.setUpWithError()
        continueAfterFailure = false

        let capturePath = ProcessInfo.processInfo.environment["PEAK_AD_CAPTURE_DIR"]
            ?? "/tmp/PeakAdCaptureV2"
        captureDirectory = URL(fileURLWithPath: capturePath, isDirectory: true)
        try FileManager.default.createDirectory(at: captureDirectory, withIntermediateDirectories: true)

        XCUIDevice.shared.orientation = .portrait

        app = XCUIApplication()
        app.launchEnvironment["UITESTS"] = "1"
        app.launchEnvironment["PEAK_AD_CAPTURE"] = "1"
        app.launchEnvironment["UITESTS_SURF_CONDITIONS_SCENARIO"] = "success"
        app.launchEnvironment["UITESTS_FIXED_DATE"] = "2026-02-01T12:00:00Z"
        app.launchEnvironment["UITESTS_SESSION_MARKER"] = "Peak ad capture"
        app.launch()
    }

    override func tearDown() {
        XCUIDevice.shared.orientation = .portrait
        app = nil
        super.tearDown()
    }

    func testCapturePeakAdMedia() throws {
        tapTab(named: "Log")
        assertExists(app.staticTexts["Peak"], timeout: 5)
        pause(1.0)
        try capture("01-log-home")

        let logSession = app.buttons["log.hero.cta"].exists ? app.buttons["log.hero.cta"] : app.buttons["Log Session"]
        assertExists(logSession)
        tap(logSession)
        assertExists(app.textFields["session.editor.spot"], timeout: 5)
        pause(1.0)
        try capture("02-editor-first-paint")

        let useLast = app.buttons["session.editor.useLastSession"]
        if useLast.waitForExistence(timeout: 3) {
            scrollToHittable(useLast)
            tap(useLast)
            pause(0.7)
        }
        try capture("03-editor-last-session")

        // Auto-fill needs a surf break with pinned coordinates. The most recent seeded session uses
        // a spot without a location, so select Trestles (pinned) before pulling conditions.
        let trestles = app.buttons["session.editor.spotOption.trestles"]
        if trestles.waitForExistence(timeout: 2) {
            scrollToHittable(trestles)
            tap(trestles)
            pause(0.4)
        }

        let details = app.staticTexts["DETAILS"].firstMatch
        if details.waitForExistence(timeout: 3) {
            scrollToHittable(details)
            if details.isHittable {
                details.tap()
                pause(0.45)
            }
        }

        let duration = app.sliders["session.editor.duration"]
        assertExists(duration)
        scrollToHittable(duration)
        duration.adjust(toNormalizedSliderPosition: 0.5)
        pause(0.45)
        try capture("04-editor-duration")

        let autoFill = app.buttons["session.editor.autoFillConditions"]
        assertExists(autoFill)
        scrollToHittable(autoFill)
        tap(autoFill)

        let replace = app.buttons["Replace"]
        if replace.waitForExistence(timeout: 1) {
            replace.tap()
        }

        let notice = app.descendants(matching: .any).matching(
            NSPredicate(
                format: "identifier == %@ AND label CONTAINS[c] %@",
                "session.editor.conditionsNotice",
                "Open-Meteo"
            )
        ).firstMatch
        _ = notice.waitForExistence(timeout: 6)
        pause(0.8)
        try capture("05-editor-conditions")

        let cancel = app.buttons["Cancel"].firstMatch
        if cancel.waitForExistence(timeout: 2) {
            tap(cancel)
            pause(0.8)
        }

        tapTab(named: "History")
        assertExists(app.staticTexts["Trestles"], timeout: 5)
        pause(0.8)
        try capture("06-history")

        tapFirstExisting(["Trestles", "San Onofre State Beach - Old Man's"])
        pause(0.9)
        try capture("07-session-detail")

        let media = app.staticTexts["MEDIA"].firstMatch
        if media.waitForExistence(timeout: 2) {
            scrollToHittable(media)
            if media.isHittable {
                media.tap()
                pause(0.6)
                try capture("08-session-media")
            }
        }

        tapTab(named: "Quiver")
        assertExists(app.staticTexts["6'2\" Fish"], timeout: 5)
        pause(0.8)
        try capture("09-quiver")

        tapFirstExisting(["6'2\" Fish", "7'4\" Midlength Performance Egg"])
        pause(0.8)
        try capture("10-gear-detail")

        tapTab(named: "Stats")
        assertExists(app.staticTexts["SESSIONS"], timeout: 5)
        pause(0.8)
        try capture("11-stats")

        tapTab(named: "More")
        assertExists(app.staticTexts["Settings"], timeout: 5)
        tapFirstExisting(["Settings"])
        pause(0.8)
        try capture("12-settings")
    }

    private func tapTab(named name: String) {
        let tab = app.tabBars.buttons[name]
        if tab.waitForExistence(timeout: 3) {
            tap(tab)
            return
        }

        let predicate = NSPredicate(format: "label == %@", name)
        if let button = firstHittable(in: app.buttons.matching(predicate)) {
            tap(button)
            return
        }
        if let cell = firstHittable(in: app.cells.matching(predicate)) {
            tap(cell)
            return
        }
        if let element = firstHittable(in: app.otherElements.matching(predicate)) {
            tap(element)
            return
        }

        XCTFail("Missing tab: \(name)")
    }

    private func tapFirstExisting(_ labels: [String]) {
        for label in labels {
            let button = app.buttons[label].firstMatch
            if button.waitForExistence(timeout: 1) {
                scrollToHittable(button)
                tap(button)
                return
            }

            let text = app.staticTexts[label].firstMatch
            if text.waitForExistence(timeout: 1) {
                scrollToHittable(text)
                tap(text)
                return
            }
        }
        XCTFail("Missing any of: \(labels.joined(separator: ", "))")
    }

    private func assertExists(
        _ element: XCUIElement,
        timeout: TimeInterval = 3,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        XCTAssertTrue(element.waitForExistence(timeout: timeout), "Missing element: \(element)", file: file, line: line)
    }

    private func scrollToHittable(_ element: XCUIElement, maxSwipes: Int = 8) {
        var attempts = 0
        while element.exists && !element.isHittable && attempts < maxSwipes {
            app.swipeUp()
            attempts += 1
        }
    }

    private func tap(_ element: XCUIElement) {
        if element.isHittable {
            element.tap()
        } else {
            element.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
        }
    }

    private func firstHittable(in query: XCUIElementQuery) -> XCUIElement? {
        let elements = query.allElementsBoundByIndex
        return elements.first(where: { $0.exists && $0.isHittable }) ?? elements.first(where: { $0.exists })
    }

    private func capture(_ name: String) throws {
        let screenshot = XCUIScreen.main.screenshot()
        let url = captureDirectory.appendingPathComponent("\(name).png")
        try screenshot.pngRepresentation.write(to: url, options: .atomic)

        let attachment = XCTAttachment(screenshot: screenshot)
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    private func pause(_ seconds: TimeInterval) {
        Thread.sleep(forTimeInterval: seconds)
    }
}
