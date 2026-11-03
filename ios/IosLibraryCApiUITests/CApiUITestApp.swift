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

    private func lines(ofRow rowId: String) -> XCUIElementQuery {
        app.staticTexts.matching(NSPredicate(format: "identifier BEGINSWITH 'result.line.' AND label BEGINSWITH %@", "[\(rowId)@"))
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
