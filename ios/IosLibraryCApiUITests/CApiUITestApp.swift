//
//  CApiUITestApp.swift
//  IosLibraryCApiUITests
//

import XCTest

/// The sections of the app (`CApiRowCatalog.sections`): a test cannot name another one. One that is
/// here and not in the app fails at `launch`.
enum CApiSection: String {
    case common
    case notification
    case clipboard
    case dialog
}

/// How the tests operate `IosLibraryCApiUITestApp`. The identifiers are copies of the app's: the test
/// bundle is a separate process and cannot reference them.
struct CApiUITestApp {
    /// Also in `scripts/ios_ui_runner.py` (`CAPI_UI_BUNDLE_ID`), which deletes the app by it.
    static let bundleIdentifier = "com.jonghyunkim.nativetoolkit.IosLibraryCApiUITestApp"
    /// The app's `RowRunner.delay`, and a margin for the call to run.
    static let backgroundWait: TimeInterval = 5
    static let timeout: TimeInterval = 10

    private let app = XCUIApplication(bundleIdentifier: bundleIdentifier)
    let test: CApiUITestCase
    private let section: CApiSection

    /// `section` is the section to draw (`CApiRowCatalog.sectionVariable` in the app).
    init(test: CApiUITestCase, section: CApiSection) {
        self.test = test
        self.section = section
        app.launchEnvironment["NTK_CAPI_SECTION"] = section.rawValue
    }

    /// Stops the test unless the app drew the section, also for a test that reads no row.
    func launch() throws {
        try CApiUITestCase.requireSimulator()
        app.launch()
        try test.checkInterruption()
        let drawn = try waitForLine(ofRow: "launch.section")
        guard drawn == "[launch.section@none] \(section.rawValue)" else {
            throw CApiUITestError("the app did not draw the section \(section.rawValue): \(drawn)")
        }
    }

    func terminate() throws {
        app.terminate()
        try test.checkInterruption()
    }

    // MARK: Rows

    /// Presses the row's Run button and returns without waiting for a line.
    func start(_ rowId: String) throws {
        try tap("row.\(rowId).run")
    }

    /// Runs the row and returns the line this call wrote. For a row that writes one line per call.
    func run(_ rowId: String, timeout: TimeInterval = Self.timeout) throws -> String {
        let before = lines(ofRow: rowId).count
        try start(rowId)
        return try waitForLine(ofRow: rowId, occurrence: before, timeout: timeout)
    }

    /// Starts the row with the delay, goes to the home screen so that the call is made in the
    /// background, comes back and returns the line it wrote. A fixed wait: the result line cannot be
    /// read while the app is in the background.
    func runInTheBackground(_ rowId: String, timeout: TimeInterval = Self.timeout) throws -> String {
        let before = lines(ofRow: rowId).count
        try tap("row.\(rowId).runAfterDelay")
        XCUIDevice.shared.press(.home)
        Thread.sleep(forTimeInterval: Self.backgroundWait)
        app.activate()
        try test.checkInterruption()
        return try waitForLine(ofRow: rowId, occurrence: before, timeout: timeout)
    }

    /// Whether the row is drawn. Only the section of this launch is (`CApiRowCatalog.drawn`).
    func isDrawn(_ rowId: String) -> Bool {
        app.buttons["row.\(rowId).run"].waitForExistence(timeout: 2)
    }

    // MARK: Result lines

    /// The line number `occurrence` (from 0) of this row, once it is there. A row that reports later
    /// (a C completion, a C event) is read with this after `start`.
    func waitForLine(ofRow rowId: String, occurrence: Int = 0, timeout: TimeInterval = Self.timeout) throws -> String {
        let query = lines(ofRow: rowId)
        let deadline = Date().addingTimeInterval(timeout)
        while query.count <= occurrence {
            try test.checkInterruption()
            guard Date() < deadline else {
                throw CApiUITestError("no line \(occurrence) of \(rowId) after \(timeout) s (\(query.count) lines)")
            }
            Thread.sleep(forTimeInterval: 0.2)
        }
        return query.element(boundBy: occurrence).label
    }

    /// Whether the line is there now, without waiting.
    func isDrawnLine(ofRow rowId: String, occurrence: Int) -> Bool {
        lines(ofRow: rowId).count > occurrence
    }

    /// Whether a line of this row, later or not, holds `text`, once it is there. A row whose number of lines
    /// the system decides (a change event) is read with this.
    func waitForLine(ofRow rowId: String, matching text: String, timeout: TimeInterval = Self.timeout) throws -> Bool {
        let query = lines(ofRow: rowId).matching(NSPredicate(format: "label CONTAINS %@", text))
        return query.firstMatch.waitForExistence(timeout: timeout)
    }

    private func lines(ofRow rowId: String) -> XCUIElementQuery {
        app.staticTexts.matching(NSPredicate(format: "identifier BEGINSWITH 'result.line.' AND label BEGINSWITH %@", "[\(rowId)@"))
    }

    // MARK: Dialogs

    /// The alert with this title, once it is shown. An alert without a title is found by not naming one.
    func alert(_ title: String?, timeout: TimeInterval = Self.timeout) throws -> XCUIElement {
        let alert = title.map { app.alerts[$0] } ?? app.alerts.firstMatch
        guard alert.waitForExistence(timeout: timeout) else {
            throw CApiUITestError("the alert \(title ?? "without a title") did not appear")
        }
        try test.checkInterruption()
        return alert
    }

    /// Presses a button of the alert and waits until it is gone.
    func press(_ button: String, inAlert title: String?) throws {
        let alert = try alert(title)
        alert.buttons[button].tap()
        try test.checkInterruption()
        guard wait(until: !alert.exists) else {
            throw CApiUITestError("the alert \(title ?? "without a title") did not go away")
        }
    }

    /// Whether an alert with this title is on the screen now.
    func isAlertShown(_ title: String) -> Bool {
        app.alerts[title].exists
    }

    /// Waits until the alert is gone.
    func waitUntilGone(alert title: String) throws {
        guard wait(until: !app.alerts[title].exists) else {
            throw CApiUITestError("the alert \(title) did not go away")
        }
    }

    /// Whether no dialog shows up for this long: an alert, a sheet, or an action sheet in a popover, which is not
    /// a sheet to XCTest and is seen by its first option.
    func noDialogAppears(for seconds: TimeInterval) -> Bool {
        let deadline = Date().addingTimeInterval(seconds)
        repeat {
            if app.alerts.firstMatch.exists || app.sheets.firstMatch.exists || app.buttons["Alpha"].exists {
                return false
            }
            Thread.sleep(forTimeInterval: 0.2)
        } while Date() < deadline
        return true
    }

    /// Types into the text field at `index` of the alert (`secure` for the secure ones).
    func type(_ text: String, intoField index: Int, secure: Bool = false, ofAlert title: String) throws {
        let alert = try alert(title)
        let field = (secure ? alert.secureTextFields : alert.textFields).element(boundBy: index)
        field.tap()
        field.typeText(text)
        try test.checkInterruption()
    }

    /// Whether the button of the alert can be pressed.
    func isEnabled(_ button: String, inAlert title: String) throws -> Bool {
        try alert(title).buttons[button].isEnabled
    }

    /// An action sheet is a sheet or a popover, depending on the system and the device: this is its button.
    func pressSheetButton(_ label: String) throws {
        let button = app.buttons[label]
        guard button.waitForExistence(timeout: Self.timeout) else {
            throw CApiUITestError("the sheet button \(label) did not appear")
        }
        try test.checkInterruption()
        button.tap()
        try test.checkInterruption()
    }

    /// Whether a button with this label is shown now and can be hit.
    func isButtonHittable(_ label: String) -> Bool {
        let button = app.buttons[label]
        return button.waitForExistence(timeout: 2) && button.isHittable
    }

    /// Taps outside the action sheet and says how: `region` is the popover's dismiss region, whose sheet has no
    /// `cancel` to press (the sample's D7), and `coordinate` is a point above a sheet, which must be on none of
    /// its `buttons`. Either way the test cannot have pressed `cancel` by accident.
    func tapOutsideTheSheet(buttons: [String], cancel: String) throws -> String {
        let region = app.otherElements["PopoverDismissRegion"]
        if region.waitForExistence(timeout: 2) {
            let button = app.buttons[cancel]
            if button.exists && button.isHittable {
                throw CApiUITestError("the sheet has a button to press where the region was expected")
            }
            region.tap()
            try test.checkInterruption()
            return "region"
        }
        let offset = CGVector(dx: 0.5, dy: 0.2)
        let window = app.windows.firstMatch.frame
        let point = CGPoint(x: window.minX + window.width * offset.dx, y: window.minY + window.height * offset.dy)
        for label in buttons where app.buttons[label].frame.contains(point) {
            throw CApiUITestError("the point outside the sheet is on the button \(label)")
        }
        app.coordinate(withNormalizedOffset: offset).tap()
        try test.checkInterruption()
        return "coordinate"
    }

    /// Answers the system's offer to save a password (working notes, 8.7) with "not now", if it comes. Whether it did.
    /// The sheet slides in: a tap while it is still moving can be lost (working notes, 8.10), so the button is tapped
    /// once it can be hit and the sheet has stopped moving. The sheet is then followed by its own label, so that
    /// another sheet cannot stand in for it. If it stays, the test fails.
    func declineTheOfferToSaveThePassword() throws -> Bool {
        let first = app.sheets.firstMatch
        guard first.waitForExistence(timeout: 5) else { return false }
        let sheet = app.sheets.matching(NSPredicate(format: "label == %@", first.label)).firstMatch
        let button = sheet.buttons["Not Now"]
        guard button.waitForExistence(timeout: 2) else {
            throw CApiUITestError("a sheet came after the login, without the button expected")
        }
        guard wait(until: button.isHittable && isStill(sheet)) else {
            throw CApiUITestError("the sheet after the login did not settle")
        }
        button.tap()
        try test.checkInterruption()
        guard wait(until: !sheet.exists) else {
            throw CApiUITestError("the sheet after the login did not go away")
        }
        return true
    }

    /// Whether the element is at the same place twice, 0.3 seconds apart.
    private func isStill(_ element: XCUIElement) -> Bool {
        let before = element.frame
        Thread.sleep(forTimeInterval: 0.3)
        return element.exists && element.frame == before
    }

    // MARK: Control Center (the sample's Springboard.openControlCenter; simulator only)

    /// Starts the row with the delay and returns without waiting.
    func startAfterDelay(_ rowId: String) throws {
        try tap("row.\(rowId).runAfterDelay")
    }

    func openControlCenter() throws {
        try CApiUITestCase.requireSimulator()
        dragOnSpringboard(from: CGVector(dx: 0.95, dy: 0.005), to: CGVector(dx: 0.95, dy: 0.6))
        try test.checkInterruption()
    }

    func closeControlCenter() throws {
        try CApiUITestCase.requireSimulator()
        dragOnSpringboard(from: CGVector(dx: 0.5, dy: 0.95), to: CGVector(dx: 0.5, dy: 0.2))
        try test.checkInterruption()
    }

    private func dragOnSpringboard(from start: CGVector, to end: CGVector) {
        let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")
        springboard.coordinate(withNormalizedOffset: start).press(forDuration: 0.1, thenDragTo: springboard.coordinate(withNormalizedOffset: end))
    }

    private func wait(until condition: @autoclosure () -> Bool, timeout: TimeInterval = Self.timeout) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while !condition() {
            guard Date() < deadline else { return false }
            Thread.sleep(forTimeInterval: 0.2)
        }
        return true
    }

    // MARK: Elements

    private func tap(_ identifier: String) throws {
        try one(app.buttons, identifier).tap()
        try test.checkInterruption()
    }

    /// The one element with the identifier. Two rows with one id, or none, stop the test.
    private func one(_ query: XCUIElementQuery, _ identifier: String) throws -> XCUIElement {
        let matches = query.matching(identifier: identifier)
        guard matches.firstMatch.waitForExistence(timeout: Self.timeout) else {
            throw CApiUITestError("\(identifier) did not appear")
        }
        try test.checkInterruption()
        guard matches.count == 1 else {
            throw CApiUITestError("\(identifier) matches \(matches.count) elements")
        }
        return matches.element(boundBy: 0)
    }
}
