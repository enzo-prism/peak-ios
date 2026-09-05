import XCTest
import UIKit

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
        app.launchEnvironment["UITESTS_CLASSIC_NAVIGATION"] = "1"
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

        // iPadOS / sidebar-adaptable tab chrome may not live inside an XCUI
        // tabBars container. Fall through the same way PeakUISmokeTests does.
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
            if element.exists && element.frame.midY < scrollView.frame.minY {
                scrollView.swipeDown()
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
        // Keep a margin so a centre resting exactly on the edge still counts as
        // off-screen; taps there are unreliable.
        let visible = scrollView.frame.insetBy(dx: 0, dy: 8)
        return visible.minY <= frame.midY && frame.midY <= visible.maxY
    }
}


/// Exercises the shipping shell: no classic-navigation override. Existing flow
/// tests retain their explicit compact lane; these cover adaptive tab/sidebar
/// chrome and the regular-width master/detail destinations it exposes.
final class PeakProductionNavigationUITests: XCTestCase {
    private var app: XCUIApplication!

    override func setUp() {
        super.setUp()
        continueAfterFailure = false
    }

    override func tearDown() {
        if let app {
            let attachment = XCTAttachment(screenshot: app.screenshot())
            attachment.name = name
            attachment.lifetime = .keepAlways
            add(attachment)
            app.terminate()
        }
        XCUIDevice.shared.orientation = .portrait
        app = nil
        super.tearDown()
    }

    private func launchProductionNavigation() {
        XCUIDevice.shared.orientation = UIDevice.current.userInterfaceIdiom == .pad ? .landscapeLeft : .portrait
        app = XCUIApplication()
        app.launchEnvironment["UITESTS"] = "1"
        app.launchEnvironment["UITESTS_DISABLE_ANIMATIONS"] = "1"
        app.launchEnvironment["UITESTS_FIXED_DATE"] = "2026-02-01T12:00:00Z"
        // Be explicit even if the surrounding test runner supplies an override.
        app.launchEnvironment["UITESTS_CLASSIC_NAVIGATION"] = "0"
        app.launch()
        XCTAssertTrue(app.buttons["Log Session"].waitForExistence(timeout: 8))
    }

    func testCompactProductionNavigationKeepsFivePrimaryTabs() throws {
        try XCTSkipIf(UIDevice.current.userInterfaceIdiom == .pad, "Compact phone navigation is checked on iPhone")
        launchProductionNavigation()
        for title in ["Log", "History", "Stats", "Quiver", "More"] {
            XCTAssertTrue(app.tabBars.buttons[title].waitForExistence(timeout: 5), "Missing primary tab: \(title)")
        }
        XCTAssertFalse(app.tabBars.buttons["Search"].exists)
        app.tabBars.buttons["More"].tap()
        XCTAssertTrue(app.buttons["more.spots"].waitForExistence(timeout: 5))
    }

    func testIPadProductionSearchFindsSeededSession() throws {
        try requireIPad()
        launchProductionNavigation()
        selectDestination("Search")
        XCTAssertTrue(app.otherElements["history.search.prompt"].waitForExistence(timeout: 5)
                      || app.staticTexts["Search your sessions"].exists)
        let searchField = app.searchFields.firstMatch
        if !searchField.isHittable {
            let searchButton = app.navigationBars.buttons["Search"].firstMatch
            if searchButton.exists && searchButton.isHittable { searchButton.tap() }
        }
        XCTAssertTrue(searchField.waitForExistence(timeout: 5), "Dedicated Search did not expose its search field")
        searchField.tap()
        searchField.typeText("Trestles")
        XCTAssertTrue(app.descendants(matching: .any)["history.row"].firstMatch.waitForExistence(timeout: 5),
                      "Searching the production tab returned no seeded session")
        XCTAssertTrue(app.staticTexts["Trestles"].firstMatch.exists)
    }

    func testIPadProductionLibraryOpensSpotsAndBuddies() throws {
        try requireIPad()
        launchProductionNavigation()
        selectDestination("Spots")
        XCTAssertTrue(app.buttons["spot.library.add"].waitForExistence(timeout: 5))
        let spot = app.buttons["spot.row"].firstMatch
        XCTAssertTrue(spot.waitForExistence(timeout: 5), "Production Spots must expose selectable split-view rows")
        spot.tap()
        XCTAssertTrue(app.buttons["library.detail.edit"].waitForExistence(timeout: 5), "Spot selection did not populate its detail column")
        selectDestination("Buddies")
        XCTAssertTrue(app.buttons["buddy.library.add"].waitForExistence(timeout: 5), "Sidebar Buddies did not open its library")
    }

    func testIPadProductionHistoryOpensSessionDetail() throws {
        try requireIPad()
        launchProductionNavigation()
        selectDestination("History")
        let session = app.buttons["history.row"].firstMatch
        XCTAssertTrue(session.waitForExistence(timeout: 5), "Production History must expose selectable split-view rows")
        session.tap()
        XCTAssertTrue(app.buttons["session.detail.share"].waitForExistence(timeout: 5), "History selection did not populate its detail column")
    }

    func testIPadSpotDeepLinkAfterVisitingSidebarLibraryOpensInMore() throws {
        try requireIPad()
        launchProductionNavigation()
        selectDestination("Spots")
        XCTAssertTrue(app.buttons["spot.library.add"].waitForExistence(timeout: 5))

        app.open(URL(string: "peak://spot?id=trestles")!)

        XCTAssertTrue(app.buttons["library.detail.edit"].waitForExistence(timeout: 5),
                      "An inactive sidebar library consumed More's deep link")
        XCTAssertTrue(app.staticTexts["Trestles"].firstMatch.exists)
        // More pushes its detail on a stack; the sidebar library opens a split
        // column. Its back button establishes which destination handled it.
        let backToMore = app.navigationBars.buttons["More"].firstMatch
        XCTAssertTrue(backToMore.waitForExistence(timeout: 5), "Spot deep link did not route through More")
        backToMore.tap()
        XCTAssertTrue(app.buttons["more.spots"].waitForExistence(timeout: 5))
    }

    private func requireIPad() throws {
        try XCTSkipUnless(UIDevice.current.userInterfaceIdiom == .pad, "Requires regular-width iPad navigation")
        try XCTSkipUnless(ProcessInfo.processInfo.operatingSystemVersion.majorVersion >= 18, "Sidebar tabs require iPadOS 18")
    }

    private func selectDestination(_ title: String, file: StaticString = #filePath, line: UInt = #line) {
        // The system can expose adaptive tabs as buttons or sidebar cells.
        // Reveal its own sidebar control when a library-only tab is hidden.
        if tapVisibleDestination(title) { return }
        let sidebarButtons = app.buttons.matching(NSPredicate(
            format: "label CONTAINS[c] 'sidebar' OR identifier CONTAINS[c] 'sidebar'"
        ))
        for button in sidebarButtons.allElementsBoundByIndex where button.isHittable {
            button.tap()
            if tapVisibleDestination(title) { return }
        }
        XCTFail("Missing production navigation destination: \(title)", file: file, line: line)
    }

    private func tapVisibleDestination(_ title: String) -> Bool {
        let predicate = NSPredicate(format: "label == %@", title)
        for query in [app.tabBars.buttons.matching(predicate), app.buttons.matching(predicate), app.cells.matching(predicate)] {
            if let element = query.allElementsBoundByIndex.first(where: { $0.isHittable }) {
                element.tap()
                return true
            }
        }
        return false
    }
}

/// Recovery presentation uses a fabricated temporary archive and an in-memory
/// store. It never damages, replaces, or exports a real user's library.
final class PeakRecoveryUITests: XCTestCase {
    private var app: XCUIApplication!

    override func setUp() {
        super.setUp()
        continueAfterFailure = false
    }

    override func tearDown() {
        if let app {
            let attachment = XCTAttachment(screenshot: app.screenshot())
            attachment.name = name
            attachment.lifetime = .keepAlways
            add(attachment)
            app.terminate()
        }
        app = nil
        super.tearDown()
    }

    private func launchRecovery(_ scenario: String) {
        app = XCUIApplication()
        app.launchEnvironment["UITESTS"] = "1"
        app.launchEnvironment["UITESTS_DISABLE_ANIMATIONS"] = "1"
        app.launchEnvironment["UITESTS_STORE_RECOVERY"] = scenario
        app.launchEnvironment["UITESTS_SHOW_WELCOME"] = "1"
        app.launch()
    }

    func testFreshRecoveryExplainsArchiveAndKeepsDetailsAvailable() {
        launchRecovery("fresh")
        let alert = app.alerts["Your previous library needs recovery"]
        XCTAssertTrue(alert.waitForExistence(timeout: 8))
        XCTAssertTrue(alert.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", "a new empty library is now in use")).firstMatch.exists)
        XCTAssertTrue(alert.buttons["Export Recovery Copy"].exists)
        alert.buttons["Close"].tap()
        XCTAssertTrue(app.staticTexts["Your previous library needs recovery."].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["Log Session"].exists, "Recovery should suppress first-run onboarding")
        app.buttons["Details"].tap()
        XCTAssertTrue(alert.waitForExistence(timeout: 5), "Recovery instructions must remain accessible after dismissal")
    }

    func testTemporaryRecoveryWarnsChangesWillBeLostAndOffersPreservedCopy() {
        launchRecovery("temporary")
        let alert = app.alerts["Temporary library in use"]
        XCTAssertTrue(alert.waitForExistence(timeout: 8))
        XCTAssertTrue(alert.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", "will be lost when Peak closes")).firstMatch.exists)
        XCTAssertTrue(alert.buttons["Export Recovery Copy"].exists)
        alert.buttons["Close"].tap()
        XCTAssertTrue(app.staticTexts["Temporary library. Changes will not be saved."].waitForExistence(timeout: 5))
        app.buttons["Details"].tap()
        XCTAssertTrue(alert.waitForExistence(timeout: 5))
    }

    func testFailedPreservationDoesNotClaimOrOfferAnArchive() {
        launchRecovery("preservationFailed")
        let alert = app.alerts["Temporary library in use"]
        XCTAssertTrue(alert.waitForExistence(timeout: 8))
        XCTAssertTrue(alert.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", "Existing library files have been left on this device")).firstMatch.exists)
        XCTAssertFalse(alert.buttons["Export Recovery Copy"].exists)
        XCTAssertFalse(alert.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", "complete copy")).firstMatch.exists)
        alert.buttons["Close"].tap()
        XCTAssertTrue(app.staticTexts["Temporary library. Changes will not be saved."].waitForExistence(timeout: 5))
        app.buttons["Details"].tap()
        XCTAssertTrue(alert.waitForExistence(timeout: 5))
        XCTAssertFalse(alert.buttons["Export Recovery Copy"].exists)
    }
}
