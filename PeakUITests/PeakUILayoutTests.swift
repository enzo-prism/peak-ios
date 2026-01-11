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

    func testQuiverLayoutFits() {
        tapTab(named: "Quiver")

        let gearRow = app.staticTexts["6'2\" Fish"]
        if gearRow.waitForExistence(timeout: 2) {
            assertFits(gearRow)
        }

        attachScreenshot(name: "Quiver")
    }

    func testQuiverRowHitAreaFullWidth() {
        tapTab(named: "Quiver")

        let row = app.buttons.matching(identifier: "quiver.row").firstMatch
        assertExists(row)
        assertRowFullWidth(row, in: app.scrollViews.firstMatch, name: "Quiver row")

        tapEdge(of: row, x: 0.95)

        let usageSummary = app.staticTexts["Usage Summary"]
        assertExists(usageSummary)
    }

    func testSpotRowHitAreaFullWidth() {
        tapTab(named: "More")
        tapElement(named: "Library")
        tapElement(named: "Spots")

        let row = app.buttons.matching(identifier: "spot.row").firstMatch
        assertExists(row)
        assertRowFullWidth(row, in: app.scrollViews.firstMatch, name: "Spot row")

        tapEdge(of: row, x: 0.95)

        let summaryTitle = app.staticTexts["Summary"]
        assertExists(summaryTitle)
    }

    func testBuddyRowHitAreaFullWidth() {
        tapTab(named: "More")
        tapElement(named: "Library")
        tapElement(named: "Buddies")

        let row = app.buttons.matching(identifier: "buddy.row").firstMatch
        assertExists(row)
        assertRowFullWidth(row, in: app.scrollViews.firstMatch, name: "Buddy row")

        tapEdge(of: row, x: 0.95)

        let deleteButton = app.buttons["Delete Buddy"]
        assertExists(deleteButton)
    }

    func testHistoryRowHitAreaFullWidth() {
        tapTab(named: "History")

        let row = historyRowCell()
        assertExists(row)
        assertRowFullWidth(row, in: app.windows.firstMatch, name: "History row")

        tapEdge(of: row, x: 0.95)

        let deleteButton = app.buttons["Delete Session"]
        assertExists(deleteButton)
    }

    func testTabBarIconSizesMatchSystem() throws {
        if UIDevice.current.userInterfaceIdiom != .phone {
            throw XCTSkip("Tab bar icon sizing is iPhone-only.")
        }

        let tabBar = app.tabBars.firstMatch
        XCTAssertTrue(tabBar.waitForExistence(timeout: 2), "Missing tab bar")

        let referenceHeight = tabIconHeight(named: "History")
        let tolerance: CGFloat = 2.5
        let maxIconHeight = tabBar.frame.height * 0.65

        for name in ["Log", "Stats", "Quiver", "More"] {
            let iconHeight = tabIconHeight(named: name)
            XCTAssertLessThanOrEqual(
                abs(iconHeight - referenceHeight),
                tolerance,
                "Tab icon height mismatch for \(name)"
            )
            XCTAssertLessThanOrEqual(
                iconHeight,
                maxIconHeight,
                "Tab icon height too large for \(name)"
            )
        }
    }

    func testSessionEditorLayoutFits() {
        tapTab(named: "Log")

        let newSession = app.buttons["New Session"]
        assertExists(newSession)
        assertFits(newSession)

        attachScreenshot(name: "Editor Entry")
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

    func testMoreLayoutFits() {
        tapTab(named: "More")

        let settings = app.staticTexts["Settings"]
        assertExists(settings)
        assertFits(settings)

        let library = app.staticTexts["Library"]
        assertExists(library)
        assertFits(library)

        attachScreenshot(name: "More")
    }

    func testSessionDeleteConfirmationDialogLayout() {
        tapTab(named: "History")

        let sessionName = "San Onofre State Beach - Old Man's"
        if app.staticTexts[sessionName].waitForExistence(timeout: 2) {
            tapElement(named: sessionName)
        } else {
            let row = firstHistoryRow()
            assertExists(row)
            row.tap()
        }

        let deleteButton = app.buttons["Delete Session"]
        assertExists(deleteButton)
        scrollToVisible(deleteButton, in: app.scrollViews.firstMatch)
        deleteButton.tap()

        assertPopupLayout(
            title: "Delete this session?",
            buttons: ["Delete"]
        )
        attachScreenshot(name: "Popup Session Delete")
        app.buttons["Delete"].tap()
    }

    func testSpotDeleteBlockedAlertLayout() {
        tapTab(named: "More")
        tapElement(named: "Library")
        tapElement(named: "Spots")
        tapElement(named: "Ocean Beach")

        let deleteButton = app.buttons["Delete Spot"]
        assertExists(deleteButton)
        scrollToVisible(deleteButton, in: app.scrollViews.firstMatch)
        deleteButton.tap()

        assertPopupLayout(
            title: "Cannot Delete",
            messageContains: "Used by",
            buttons: ["OK"]
        )
        attachScreenshot(name: "Popup Spot Delete Blocked")
        app.buttons["OK"].tap()
    }

    func testBuddyDeleteBlockedAlertLayout() {
        tapTab(named: "More")
        tapElement(named: "Library")
        tapElement(named: "Buddies")
        tapElement(named: "Kai")

        let deleteButton = app.buttons["Delete Buddy"]
        assertExists(deleteButton)
        scrollToVisible(deleteButton, in: app.scrollViews.firstMatch)
        deleteButton.tap()

        assertPopupLayout(
            title: "Cannot Delete",
            messageContains: "Used by",
            buttons: ["OK"]
        )
        attachScreenshot(name: "Popup Buddy Delete Blocked")
        app.buttons["OK"].tap()
    }

    func testGearArchiveConfirmationDialogLayout() {
        tapTab(named: "Quiver")
        tapElement(named: "6'2\" Fish")

        let archiveButton = app.buttons["Archive Gear"]
        assertExists(archiveButton)
        scrollToVisible(archiveButton, in: app.scrollViews.firstMatch)
        archiveButton.tap()

        assertPopupLayout(
            title: "Archive gear?",
            messageContains: "Archived gear stays",
            buttons: ["Archive"]
        )
        attachScreenshot(name: "Popup Gear Archive")
        app.buttons["Archive"].tap()
    }

    func testSettingsResetConfirmationDialogLayout() {
        tapTab(named: "More")
        tapElement(named: "Settings")

        let resetButton = app.buttons["Reset All Data"]
        assertExists(resetButton)
        scrollToVisible(resetButton, in: scrollContainer())
        resetButton.tap()

        assertPopupLayout(
            title: "Reset all data?",
            messageContains: "permanently deletes",
            buttons: ["Delete Everything"]
        )
        attachScreenshot(name: "Popup Reset Data")
        app.buttons["Delete Everything"].tap()

        assertPopupLayout(
            title: "Reset Complete",
            messageContains: "All data has been deleted",
            buttons: ["OK"]
        )
        attachScreenshot(name: "Popup Reset Complete")
        app.buttons["OK"].tap()
    }

    func testSessionEditorKeyboardAvoidsFields() {
        tapTab(named: "Log")

        let newSession = app.buttons["New Session"]
        assertExists(newSession)
        newSession.tap()

        let scrollView = app.scrollViews.firstMatch

        let spotField = app.textFields["session.editor.spot"]
        assertExists(spotField)
        scrollToVisible(spotField, in: scrollView)
        spotField.tap()
        app.typeText("San Onofre State Beach")
        assertNotCoveredByKeyboard(spotField)

        let gearField = app.textFields["session.editor.gear"]
        assertExists(gearField)
        scrollToVisible(gearField, in: scrollView)
        gearField.tap()
        app.typeText("7'4\" Midlength")
        assertNotCoveredByKeyboard(gearField)

        let buddyField = app.textFields["session.editor.buddy"]
        assertExists(buddyField)
        scrollToVisible(buddyField, in: scrollView)
        buddyField.tap()
        app.typeText("Chris")
        assertNotCoveredByKeyboard(buddyField)

        let notesField = app.textViews["session.editor.notes"]
        assertExists(notesField)
        scrollToVisible(notesField, in: scrollView)
        notesField.tap()
        app.typeText("Long notes to confirm the editor stays visible above the keyboard.")
        assertNotCoveredByKeyboard(notesField)
    }

    func testGearEditorKeyboardAvoidsFields() {
        tapTab(named: "Quiver")

        let addGear = app.buttons["quiver.add"]
        assertExists(addGear)
        addGear.tap()

        let scrollView = app.scrollViews.firstMatch

        let nameField = app.textFields["gear.editor.name"]
        assertExists(nameField)
        nameField.tap()
        app.typeText("Twin Pin")
        assertNotCoveredByKeyboard(nameField)

        let notesField = app.textViews["gear.editor.notes"]
        assertExists(notesField)
        scrollToVisible(notesField, in: scrollView)
        notesField.tap()
        app.typeText("Adds glide and trims on shoulder-high days.")
        assertNotCoveredByKeyboard(notesField)
    }

    func testSpotEditorKeyboardAvoidsFields() {
        tapTab(named: "More")
        tapElement(named: "Library")
        tapElement(named: "Spots")

        let addSpot = app.buttons["spot.library.add"]
        assertExists(addSpot)
        addSpot.tap()

        let scrollView = app.scrollViews.firstMatch

        let nameField = app.textFields["spot.editor.name"]
        assertExists(nameField)
        nameField.tap()
        app.typeText("Little Rincon")
        assertNotCoveredByKeyboard(nameField)

        let locationField = app.textFields["spot.editor.location"]
        assertExists(locationField)
        scrollToVisible(locationField, in: scrollView)
        locationField.tap()
        app.typeText("Santa Barbara")
        assertNotCoveredByKeyboard(locationField)
    }

    func testBuddyEditorKeyboardAvoidsFields() {
        tapTab(named: "More")
        tapElement(named: "Library")
        tapElement(named: "Buddies")

        let addBuddy = app.buttons["buddy.library.add"]
        assertExists(addBuddy)
        addBuddy.tap()

        let nameField = app.textFields["buddy.editor.name"]
        assertExists(nameField)
        nameField.tap()
        app.typeText("Sam")
        assertNotCoveredByKeyboard(nameField)
    }
}

private struct PixelBuffer {
    let data: [UInt8]
    let width: Int
    let height: Int
    let scale: CGFloat
}

private extension PeakUILayoutTests {
    func tapTab(named name: String, file: StaticString = #filePath, line: UInt = #line) {
        let tabButton = app.tabBars.buttons[name]
        if tabButton.waitForExistence(timeout: 2) {
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

    func tabIconHeight(
        named name: String,
        file: StaticString = #filePath,
        line: UInt = #line
    ) -> CGFloat {
        tapTab(named: name)

        let tabBar = app.tabBars.firstMatch
        XCTAssertTrue(tabBar.waitForExistence(timeout: 2), "Missing tab bar", file: file, line: line)

        let button = app.tabBars.buttons[name]
        XCTAssertTrue(button.waitForExistence(timeout: 2), "Missing tab: \(name)", file: file, line: line)

        let tabBarFrame = tabBar.frame
        let buttonFrame = button.frame.offsetBy(dx: -tabBarFrame.minX, dy: -tabBarFrame.minY)
        let screenshot = tabBar.screenshot()
        let pixelBuffer = pixelBuffer(from: screenshot)
        let scale = pixelBuffer.scale
        let iconRegionHeight = tabBarFrame.height * 0.65
        let pixelRegion = CGRect(
            x: buttonFrame.minX * scale,
            y: 0,
            width: buttonFrame.width * scale,
            height: iconRegionHeight * scale
        )
        guard let bounds = iconPixelBounds(in: pixelRegion, pixelBuffer: pixelBuffer) else {
            XCTFail("Missing tab icon pixels: \(name)", file: file, line: line)
            return 0
        }

        let iconHeight = bounds.height / scale
        XCTAssertGreaterThan(iconHeight, 0, "Invalid tab icon height for \(name)", file: file, line: line)

        return iconHeight
    }

    func brightPixelBounds(in rect: CGRect, pixelBuffer: PixelBuffer) -> CGRect? {
        let minX = max(Int(rect.minX), 0)
        let minY = max(Int(rect.minY), 0)
        let maxX = min(Int(rect.maxX), pixelBuffer.width - 1)
        let maxY = min(Int(rect.maxY), pixelBuffer.height - 1)

        guard minX < maxX, minY < maxY else { return nil }

        var foundMinX = Int.max
        var foundMinY = Int.max
        var foundMaxX = Int.min
        var foundMaxY = Int.min

        let bytesPerPixel = 4
        let threshold = 0.55
        let alphaThreshold = 32

        for y in minY...maxY {
            let rowIndex = y * pixelBuffer.width * bytesPerPixel
            for x in minX...maxX {
                let index = rowIndex + x * bytesPerPixel
                let r = pixelBuffer.data[index]
                let g = pixelBuffer.data[index + 1]
                let b = pixelBuffer.data[index + 2]
                let a = pixelBuffer.data[index + 3]

                if a < alphaThreshold { continue }

                let luminance = (0.2126 * Double(r) + 0.7152 * Double(g) + 0.0722 * Double(b)) / 255.0
                if luminance < threshold { continue }

                if x < foundMinX { foundMinX = x }
                if y < foundMinY { foundMinY = y }
                if x > foundMaxX { foundMaxX = x }
                if y > foundMaxY { foundMaxY = y }
            }
        }

        guard foundMinX <= foundMaxX, foundMinY <= foundMaxY else { return nil }
        return CGRect(
            x: CGFloat(foundMinX),
            y: CGFloat(foundMinY),
            width: CGFloat(foundMaxX - foundMinX + 1),
            height: CGFloat(foundMaxY - foundMinY + 1)
        )
    }

    func iconPixelBounds(in rect: CGRect, pixelBuffer: PixelBuffer) -> CGRect? {
        if let brightBounds = brightPixelBounds(in: rect, pixelBuffer: pixelBuffer) {
            return brightBounds
        }
        return contrastPixelBounds(in: rect, pixelBuffer: pixelBuffer)
    }

    func contrastPixelBounds(in rect: CGRect, pixelBuffer: PixelBuffer) -> CGRect? {
        let minX = max(Int(rect.minX), 0)
        let minY = max(Int(rect.minY), 0)
        let maxX = min(Int(rect.maxX), pixelBuffer.width - 1)
        let maxY = min(Int(rect.maxY), pixelBuffer.height - 1)

        guard minX < maxX, minY < maxY else { return nil }

        let bytesPerPixel = 4
        func sampleColor(x: Int, y: Int) -> (Double, Double, Double, Double) {
            let index = (y * pixelBuffer.width + x) * bytesPerPixel
            let r = Double(pixelBuffer.data[index]) / 255.0
            let g = Double(pixelBuffer.data[index + 1]) / 255.0
            let b = Double(pixelBuffer.data[index + 2]) / 255.0
            let a = Double(pixelBuffer.data[index + 3]) / 255.0
            return (r, g, b, a)
        }

        let inset = 2
        let samplePoints = [
            (minX + inset, minY + inset),
            (maxX - inset, minY + inset),
            (minX + inset, maxY - inset),
            (maxX - inset, maxY - inset)
        ].filter { $0.0 >= minX && $0.0 <= maxX && $0.1 >= minY && $0.1 <= maxY }

        guard !samplePoints.isEmpty else { return nil }

        var bgR = 0.0
        var bgG = 0.0
        var bgB = 0.0
        var bgCount = 0.0

        for point in samplePoints {
            let (r, g, b, a) = sampleColor(x: point.0, y: point.1)
            guard a > 0.1 else { continue }
            bgR += r
            bgG += g
            bgB += b
            bgCount += 1.0
        }

        guard bgCount > 0 else { return nil }

        bgR /= bgCount
        bgG /= bgCount
        bgB /= bgCount

        let alphaThreshold: UInt8 = 32
        let distanceThreshold = 0.25

        var foundMinX = Int.max
        var foundMinY = Int.max
        var foundMaxX = Int.min
        var foundMaxY = Int.min

        for y in minY...maxY {
            let rowIndex = y * pixelBuffer.width * bytesPerPixel
            for x in minX...maxX {
                let index = rowIndex + x * bytesPerPixel
                let r = Double(pixelBuffer.data[index]) / 255.0
                let g = Double(pixelBuffer.data[index + 1]) / 255.0
                let b = Double(pixelBuffer.data[index + 2]) / 255.0
                let a = pixelBuffer.data[index + 3]

                if a < alphaThreshold { continue }

                let distance = abs(r - bgR) + abs(g - bgG) + abs(b - bgB)
                if distance < distanceThreshold { continue }

                if x < foundMinX { foundMinX = x }
                if y < foundMinY { foundMinY = y }
                if x > foundMaxX { foundMaxX = x }
                if y > foundMaxY { foundMaxY = y }
            }
        }

        guard foundMinX <= foundMaxX, foundMinY <= foundMaxY else { return nil }
        return CGRect(
            x: CGFloat(foundMinX),
            y: CGFloat(foundMinY),
            width: CGFloat(foundMaxX - foundMinX + 1),
            height: CGFloat(foundMaxY - foundMinY + 1)
        )
    }

    func pixelBuffer(from screenshot: XCUIScreenshot, file: StaticString = #filePath, line: UInt = #line) -> PixelBuffer {
        let image = screenshot.image
        guard let cgImage = image.cgImage else {
            XCTFail("Missing screenshot CGImage", file: file, line: line)
            return PixelBuffer(data: [], width: 0, height: 0, scale: image.scale)
        }

        let scale = image.scale
        let width = Int(image.size.width * scale)
        let height = Int(image.size.height * scale)

        var data = [UInt8](repeating: 0, count: width * height * 4)
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        guard let context = CGContext(
            data: &data,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: width * 4,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else {
            XCTFail("Failed to create pixel buffer", file: file, line: line)
            return PixelBuffer(data: [], width: width, height: height, scale: scale)
        }

        context.translateBy(x: 0, y: CGFloat(height))
        context.scaleBy(x: 1, y: -1)
        context.draw(cgImage, in: CGRect(x: 0, y: 0, width: width, height: height))

        return PixelBuffer(data: data, width: width, height: height, scale: scale)
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

    func scrollContainer() -> XCUIElement {
        let table = app.tables.firstMatch
        if table.exists {
            return table
        }
        return app.scrollViews.firstMatch
    }

    func firstHistoryRow() -> XCUIElement {
        let row = app.otherElements.matching(identifier: "history.row").firstMatch
        if row.exists {
            return row
        }
        let buttonRow = app.buttons.matching(identifier: "history.row").firstMatch
        if buttonRow.exists {
            return buttonRow
        }
        return app.cells.matching(identifier: "history.row").firstMatch
    }

    func historyRowCell() -> XCUIElement {
        let sessionName = "San Onofre State Beach - Old Man's"
        let sessionCell = app.cells.containing(.staticText, identifier: sessionName).firstMatch
        if sessionCell.exists {
            return sessionCell
        }

        let fallbackCell = app.cells.containing(.staticText, identifier: "Trestles").firstMatch
        if fallbackCell.exists {
            return fallbackCell
        }

        return app.cells.firstMatch
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

    func tapElement(named name: String, file: StaticString = #filePath, line: UInt = #line) {
        let predicate = NSPredicate(format: "label == %@", name)

        if let element = firstHittable(in: app.buttons.matching(predicate)) {
            element.tap()
            return
        }

        if let element = firstHittable(in: app.cells.matching(predicate)) {
            element.tap()
            return
        }

        if let element = firstHittable(in: app.staticTexts.matching(predicate)) {
            element.tap()
            return
        }

        XCTFail("Missing element: \(name)", file: file, line: line)
    }

    func popupContainer(for title: String) -> XCUIElement {
        let alert = app.alerts.firstMatch
        if alert.waitForExistence(timeout: 2), alert.staticTexts[title].exists {
            return alert
        }

        let sheet = app.sheets.firstMatch
        if sheet.waitForExistence(timeout: 2), sheet.staticTexts[title].exists {
            return sheet
        }

        let popover = app.popovers.firstMatch
        if popover.waitForExistence(timeout: 2), popover.staticTexts[title].exists {
            return popover
        }

        return app
    }

    func assertRowFullWidth(
        _ element: XCUIElement,
        in container: XCUIElement,
        name: String,
        horizontalPadding: CGFloat = 40,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        assertExists(container, file: file, line: line)

        let containerWidth = container.frame.width
        XCTAssertGreaterThan(containerWidth, 0, "Missing container width for \(name)", file: file, line: line)

        let expectedMinWidth = containerWidth - horizontalPadding
        XCTAssertGreaterThanOrEqual(
            element.frame.width,
            expectedMinWidth,
            "\(name) hit area too narrow",
            file: file,
            line: line
        )
    }

    func tapEdge(of element: XCUIElement, x: CGFloat, y: CGFloat = 0.5) {
        element.coordinate(withNormalizedOffset: CGVector(dx: x, dy: y)).tap()
    }

    func assertPopupLayout(
        title: String,
        messageContains: String? = nil,
        buttons: [String],
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        let container = popupContainer(for: title)
        let titleElement = container.staticTexts[title]
        if titleElement.exists {
            assertExists(titleElement, file: file, line: line)
            assertFits(titleElement, file: file, line: line)
        } else {
            let fallbackTitle = app.staticTexts[title]
            assertExists(fallbackTitle, file: file, line: line)
            assertFits(fallbackTitle, file: file, line: line)
        }

        if let messageContains {
            let predicate = NSPredicate(format: "label CONTAINS %@", messageContains)
            let messageElement = container.staticTexts.matching(predicate).firstMatch
            if messageElement.exists {
                assertExists(messageElement, file: file, line: line)
                assertFits(messageElement, file: file, line: line)
            } else {
                let fallbackMessage = app.staticTexts.matching(predicate).firstMatch
                assertExists(fallbackMessage, file: file, line: line)
                assertFits(fallbackMessage, file: file, line: line)
            }
        }

        for label in buttons {
            let button = container.buttons[label]
            if button.exists {
                assertExists(button, file: file, line: line)
                assertFits(button, file: file, line: line)
            } else {
                let predicate = NSPredicate(format: "label CONTAINS[c] %@", label)
                let partialButton = container.buttons.matching(predicate).firstMatch
                if partialButton.exists {
                    assertExists(partialButton, file: file, line: line)
                    assertFits(partialButton, file: file, line: line)
                } else {
                    let fallbackButton = app.buttons.matching(predicate).firstMatch
                    assertExists(fallbackButton, file: file, line: line)
                    assertFits(fallbackButton, file: file, line: line)
                }
            }
        }
    }

    func assertNotCoveredByKeyboard(_ element: XCUIElement, file: StaticString = #filePath, line: UInt = #line) {
        let keyboard = app.keyboards.firstMatch
        XCTAssertTrue(keyboard.waitForExistence(timeout: 2), "Keyboard not visible", file: file, line: line)

        let elementFrame = element.frame
        let keyboardFrame = keyboard.frame
        let tolerance: CGFloat = 6

        XCTAssertLessThanOrEqual(
            elementFrame.maxY,
            keyboardFrame.minY - tolerance,
            "Element covered by keyboard: \(element)",
            file: file,
            line: line
        )
    }
}
