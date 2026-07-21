import XCTest

/// Covers the 2.7 ecosystem surfaces from the app's side: logging a session as
/// it happens (start → end → prefilled editor) and the widget's deep link.
///
/// ActivityKit itself is gated off under `UITESTS`, so these tests exercise the
/// real state machine and the real presentation without depending on Lock
/// Screen or Dynamic Island chrome the simulator can't drive.
final class PeakEcosystemUITests: XCTestCase {
    private var app: XCUIApplication!

    override func setUp() {
        super.setUp()
        continueAfterFailure = false
    }

    override func tearDown() {
        app = nil
        super.tearDown()
    }

    private func launchApp(openURL: String? = nil) {
        app = XCUIApplication()
        app.launchEnvironment["UITESTS"] = "1"
        app.launchEnvironment["UITESTS_DISABLE_ANIMATIONS"] = "1"
        app.launchEnvironment["UITESTS_FIXED_DATE"] = "2026-02-01T12:00:00Z"
        if let openURL {
            app.launchEnvironment["UITESTS_OPEN_URL"] = openURL
        }
        app.launch()
    }

    /// The headline flow: paddle out, get out, and land in an editor that
    /// already knows when you started, how long you were in, and where.
    func testStartSessionThenEndOpensPrefilledEditor() {
        launchApp()
        tapTab(named: "Log")

        let start = app.buttons["Start Session"]
        XCTAssertTrue(start.waitForExistence(timeout: 5), "Missing Start Session control on the Log hero")
        start.tap()

        // The hero swaps to the running state.
        let end = app.buttons["End Session"]
        XCTAssertTrue(end.waitForExistence(timeout: 5), "Hero did not switch to the running-session state")
        XCTAssertFalse(app.buttons["Start Session"].exists, "Start control should be replaced while a session runs")
        XCTAssertTrue(app.staticTexts["In progress"].exists, "Missing in-progress indicator")

        end.tap()

        // Ending hands the session to the editor, prefilled.
        let spotField = app.textFields["session.editor.spot"]
        XCTAssertTrue(spotField.waitForExistence(timeout: 5), "Ending a session did not open the log editor")

        // The most recent seeded session is at San Onofre, so that spot is
        // preselected and the draft is already save-ready.
        let saveButton = app.buttons["Save"]
        XCTAssertTrue(saveButton.waitForExistence(timeout: 3))
        XCTAssertEqual(spotField.value as? String, "San Onofre State Beach - Old Man's")
        XCTAssertTrue(saveButton.isEnabled, "A prefilled draft should be ready to save")

        // Duration arrived from the timer rather than sitting unset.
        let scrollView = app.scrollViews["session.editor.scroll"]
        let duration = app.sliders["session.editor.duration"]
        if duration.waitForExistence(timeout: 3) {
            scrollToVisible(duration, in: scrollView)
            XCTAssertNotEqual(duration.value as? String, "Not set", "Duration should be prefilled from the timer")
        }

        saveButton.tap()

        // Back on the Log tab the timer is available again, not stuck running.
        XCTAssertTrue(app.buttons["Start Session"].waitForExistence(timeout: 5), "Hero did not reset after saving")
    }

    /// Cancelling out of the prefilled editor must still clear the session —
    /// the surfer is out of the water either way.
    func testEndingASessionClearsTheRunningStateEvenIfTheLogIsDismissed() {
        launchApp()
        tapTab(named: "Log")

        let start = app.buttons["Start Session"]
        XCTAssertTrue(start.waitForExistence(timeout: 5))
        start.tap()

        let end = app.buttons["End Session"]
        XCTAssertTrue(end.waitForExistence(timeout: 5))
        end.tap()

        let cancel = app.buttons["Cancel"]
        XCTAssertTrue(cancel.waitForExistence(timeout: 5), "Missing Cancel in the prefilled editor")
        cancel.tap()

        XCTAssertTrue(app.buttons["Start Session"].waitForExistence(timeout: 5), "Session still running after dismissing the log")
    }

    /// Tapping either widget opens Peak straight into a new session.
    func testWidgetDeepLinkOpensNewSessionSheet() {
        launchApp(openURL: "peak://new-session")

        let spotField = app.textFields["session.editor.spot"]
        XCTAssertTrue(spotField.waitForExistence(timeout: 5), "Widget deep link did not open the new-session sheet")
        let saveButton = app.buttons["Save"]
        XCTAssertTrue(saveButton.waitForExistence(timeout: 3))

        // A deep-linked session starts blank — it isn't a resumed timer. An
        // empty SwiftUI text field reports its prompt as `value`, so assert the
        // absence of a real spot rather than an empty string.
        XCTAssertEqual(spotField.value as? String, "Search or add a break")
        XCTAssertFalse(saveButton.isEnabled, "A blank draft has no spot yet, so it can't be saved")
    }

    /// A URL Peak doesn't own must not open anything.
    func testUnrelatedDeepLinkDoesNotOpenTheSheet() {
        launchApp(openURL: "peak://not-a-real-destination")

        XCTAssertTrue(app.buttons["Log Session"].waitForExistence(timeout: 5), "App did not settle on the Log tab")
        XCTAssertFalse(
            app.textFields["session.editor.spot"].exists,
            "An unknown deep link should not open the editor"
        )
    }
}

private extension PeakEcosystemUITests {
    func tapTab(named name: String, file: StaticString = #filePath, line: UInt = #line) {
        let tabButton = app.tabBars.buttons[name]
        if tabButton.waitForExistence(timeout: 5) {
            if tabButton.isHittable {
                tabButton.tap()
            } else {
                tabButton.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
            }
            return
        }
        XCTFail("Missing tab: \(name)", file: file, line: line)
    }

    func scrollToVisible(_ element: XCUIElement, in scrollView: XCUIElement, maxSwipes: Int = 8) {
        guard scrollView.exists else { return }
        var attempts = 0
        while !element.isHittable && attempts < maxSwipes {
            scrollView.swipeUp()
            attempts += 1
        }
    }
}
