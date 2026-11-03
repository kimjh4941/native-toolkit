//
//  CApiRoundTripUITests.swift
//  IosLibraryCApiUITests
//

import UIKit
import XCTest

/// The path of the C ABI's UI tests with the functions that exist so far: test -> app -> C function ->
/// result line -> test, in the foreground and with the call made in the background (TB-2b), and the
/// Clipboard functions on it (TB-3).
final class CApiRoundTripUITests: CApiUITestCase {

    func testTheLaunchInstallsTheDelegateThroughC() throws {
        let app = try launchApp(section: .notification)
        XCTAssertEqual(try app.waitForLine(ofRow: "launch.install"), "[launch.install@none] \(NotificationError.none)")
    }

    func testTheVersionComesFromC() throws {
        let app = try launchApp(section: .common)
        XCTAssertEqual(try app.run("common.version"), "[common.version@foregroundActive] 0x020000")
    }

    func testTheLastSystemCodeComesFromC() throws {
        let app = try launchApp(section: .common)
        XCTAssertEqual(try app.run("common.lastSystemCode"), "[common.lastSystemCode@foregroundActive] 0")
    }

    func testInstallingOnTheMainThreadReturnsNone() throws {
        let app = try launchApp(section: .notification)
        XCTAssertEqual(try app.run("notification.install"), "[notification.install@foregroundActive] \(NotificationError.none)")
    }

    func testInstallingOffTheMainThreadReturnsWrongThread() throws {
        let app = try launchApp(section: .notification)
        XCTAssertEqual(try app.run("notification.installOffMain"),
                       "[notification.installOffMain@foregroundActive] \(NotificationError.wrongThread)")
    }

    /// What keeps a tap short when the rows of all features are there (working notes 5.10).
    func testOnlyTheNamedSectionIsDrawn() throws {
        let app = try launchApp(section: .common)
        XCTAssertTrue(app.isDrawn("common.version"))
        XCTAssertFalse(app.isDrawn("notification.install"))
    }

    /// The way a foreground row of part 2, 12.1 reaches C: the state in the line says that the call
    /// was really made in the background.
    func testACallCanBeMadeInTheBackground() throws {
        let app = try launchApp(section: .common)
        XCTAssertEqual(try app.runInTheBackground("common.version"), "[common.version@background] 0x020000")
    }

    // MARK: - Clipboard.h in a real app (part 2, 12.2, "C から書いて C で読む"; TB-3)

    // The app writes, so it reads its own content and the system asks nothing, until the runner writes.
    // The general pasteboard here is the simulator's (`CApiUITestCase` stops anywhere else).

    private let text = "ntk-capi-ui-text"

    private func line(_ row: String, _ value: String) -> String {
        "[clipboard.\(row)@foregroundActive] \(value)"
    }

    private func run(_ app: CApiUITestApp, _ row: String) throws -> String {
        try app.run("clipboard.\(row)")
    }

    func testWritingAndReadingTheGeneralPasteboard() throws {
        let app = try launchApp(section: .clipboard)
        XCTAssertEqual(try run(app, "copy"), line("copy", "0 0"))
        XCTAssertEqual(try run(app, "read"), line("read", "0 0 items=1 hasTypes=true text=\(text)"))
        XCTAssertEqual(try run(app, "readData"), line("readData", "0 0 data=\(text)"))
        XCTAssertEqual(try run(app, "readDataAbsent"), line("readDataAbsent", "0 0 data=NULL"))
        XCTAssertEqual(try run(app, "snapshot"), line("snapshot", "0 0 strings=1 items=1 matching=0 first=-1"))
        XCTAssertEqual(try run(app, "snapshotMatching"), line("snapshotMatching", "0 0 strings=1 items=1 matching=1 first=0"))
        XCTAssertEqual(try run(app, "append"), line("append", "0 0"))
        XCTAssertEqual(try run(app, "snapshot"), line("snapshot", "0 0 strings=1 items=2 matching=0 first=-1"))
        XCTAssertEqual(try run(app, "clear"), line("clear", "0 0"))
        XCTAssertEqual(try run(app, "snapshot"), line("snapshot", "0 0 strings=0 items=0 matching=0 first=-1"))
    }

    func testANamedPasteboardFromCreationToRemoval() throws {
        let app = try launchApp(section: .clipboard)
        XCTAssertEqual(try run(app, "createNamed"), line("createNamed", "0 0 name=com.jonghyunkim.nativetoolkit.capi.ui"))
        XCTAssertEqual(try run(app, "copyNamed"), line("copyNamed", "0 0"))
        XCTAssertEqual(try run(app, "readNamed"), line("readNamed", "0 0 items=1 hasTypes=true text=\(text)"))
        XCTAssertEqual(try run(app, "removeNamed"), line("removeNamed", "0 0"))
        XCTAssertEqual(try run(app, "readNamed"), line("readNamed", "\(ClipboardError.unavailable) 0 items=0 hasTypes=false text=NULL"))
    }

    func testFailuresComeWhereTheDesignSays() throws {
        let app = try launchApp(section: .clipboard)
        XCTAssertEqual(try run(app, "copyBlankHtml"), line("copyBlankHtml", "\(ClipboardError.emptyContent) 0"))
        XCTAssertEqual(try run(app, "copyNoItems"), line("copyNoItems", "rejected \(ClipboardError.emptyItems)"))
        XCTAssertEqual(try run(app, "detectNoPatterns"), line("detectNoPatterns", "rejected \(ClipboardError.emptyPatterns)"))
        XCTAssertEqual(try run(app, "removeGeneral"), line("removeGeneral", "\(ClipboardError.cannotRemoveGeneral) 0"))
    }

    func testDetectingAndTheChangeCount() throws {
        let app = try launchApp(section: .clipboard)
        XCTAssertEqual(try run(app, "copyUrlAsText"), line("copyUrlAsText", "0 0"))
        XCTAssertEqual(try run(app, "checkChange"), line("checkChange", "0 0 changed=0"))
        XCTAssertEqual(try run(app, "detectPatterns"), line("detectPatterns", "0 0 patterns=1"))
        let values = try run(app, "detectValues")
        XCTAssertTrue(values.hasPrefix(line("detectValues", "0 0 json={")), values)
        XCTAssertTrue(values.contains("\"probableWebURL\":\"https://example.com/ntk\""), values)
        XCTAssertEqual(try run(app, "copy"), line("copy", "0 0"))
        XCTAssertEqual(try run(app, "checkChange"), line("checkChange", "0 0 changed=1"))
        XCTAssertEqual(try run(app, "checkChange"), line("checkChange", "0 0 changed=0"))
    }

    // MARK: - Content of another app: the runner writes it, and the system asks the user (M3)

    /// The app's main thread stops until the answer, so the alert is answered before anything of the app is read.
    private func answerPaste(_ label: String) throws {
        let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")
        let button = springboard.alerts.firstMatch.buttons[label]
        guard button.waitForExistence(timeout: 10) else {
            throw CApiUITestError("no paste alert with \(label)")
        }
        button.tap()
    }

    private func writeFromTheRunner() {
        UIPasteboard.general.string = "written-by-the-runner"
    }

    func testAReadTheUserAllows() throws {
        let app = try launchApp(section: .clipboard)
        writeFromTheRunner()
        try app.start("clipboard.read")
        try answerPaste("Allow Paste")
        XCTAssertEqual(try app.waitForLine(ofRow: "clipboard.read"), line("read", "0 0 items=1 hasTypes=true text=written-by-the-runner"))
    }

    /// M3: a denied paste is not a failure.
    func testAReadTheUserDenies() throws {
        let app = try launchApp(section: .clipboard)
        writeFromTheRunner()
        try app.start("clipboard.read")
        try answerPaste("Don’t Allow Paste")
        XCTAssertEqual(try app.waitForLine(ofRow: "clipboard.read"), line("read", "0 0 items=1 hasTypes=false text=NULL"))
    }

    func testReadDataTheUserDenies() throws {
        let app = try launchApp(section: .clipboard)
        writeFromTheRunner()
        try app.start("clipboard.readData")
        try answerPaste("Don’t Allow Paste")
        XCTAssertEqual(try app.waitForLine(ofRow: "clipboard.readData"), line("readData", "0 0 data=NULL"))
    }

    func testReadDataTheUserAllows() throws {
        let app = try launchApp(section: .clipboard)
        writeFromTheRunner()
        try app.start("clipboard.readData")
        try answerPaste("Allow Paste")
        XCTAssertEqual(try app.waitForLine(ofRow: "clipboard.readData"), line("readData", "0 0 data=written-by-the-runner"))
    }

    func testDetectingValuesTheUserAllows() throws {
        let app = try launchApp(section: .clipboard)
        UIPasteboard.general.string = "https://example.com/ntk"
        try app.start("clipboard.detectValues")
        try answerPaste("Allow Paste")
        let values = try app.waitForLine(ofRow: "clipboard.detectValues")
        XCTAssertTrue(values.hasPrefix(line("detectValues", "0 0 json={")), values)
        XCTAssertTrue(values.contains("\"probableWebURL\":\"https://example.com/ntk\""), values)
    }

    func testALoadTheUserAllows() throws {
        let app = try launchApp(section: .clipboard)
        writeFromTheRunner()
        try app.start("clipboard.loadText")
        try answerPaste("Allow Paste")
        XCTAssertEqual(try app.waitForLine(ofRow: "clipboard.loadText"), line("loadText", "0 0 hasId=true kind=0 text=written-by-the-runner"))
    }

    /// M3: unlike a read, a denied load is a failure.
    func testALoadTheUserDenies() throws {
        let app = try launchApp(section: .clipboard)
        writeFromTheRunner()
        try app.start("clipboard.loadText")
        try answerPaste("Don’t Allow Paste")
        XCTAssertEqual(try app.waitForLine(ofRow: "clipboard.loadText"), line("loadText", "\(ClipboardError.loadFailed) 0 hasId=true kind=-1 text=NULL"))
    }

    /// Cancelled before the first main turn, the load never starts, so the system asks nothing (part 2, 12.2).
    func testALoadCancelledAtOnceAsksNothing() throws {
        let app = try launchApp(section: .clipboard)
        writeFromTheRunner()
        try app.start("clipboard.loadAndCancel")
        XCTAssertEqual(try app.waitForLine(ofRow: "clipboard.loadAndCancel"), line("loadAndCancel", "\(ClipboardError.canceled) 0 hasId=true kind=-1 text=NULL"))
        let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")
        XCTAssertFalse(springboard.alerts.firstMatch.waitForExistence(timeout: 3), "a cancelled load showed the paste alert")
    }

    /// Part 2, 12.2: the one test that waits the 15 seconds. The timeout includes the time to answer, and a later
    /// answer delivers nothing.
    func testALoadNotAnsweredTimesOut() throws {
        let app = try launchApp(section: .clipboard)
        writeFromTheRunner()
        try app.start("clipboard.loadText")
        let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")
        XCTAssertTrue(springboard.alerts.firstMatch.waitForExistence(timeout: 10), "no paste alert")
        Thread.sleep(forTimeInterval: 17)
        try answerPaste("Don’t Allow Paste")
        XCTAssertEqual(try app.waitForLine(ofRow: "clipboard.loadText"), line("loadText", "\(ClipboardError.timedOut) 0 hasId=true kind=-1 text=NULL"))
        Thread.sleep(forTimeInterval: 1)
        XCTAssertFalse(app.isDrawnLine(ofRow: "clipboard.loadText", occurrence: 1), "a second completion")
    }

    /// As above with the other answer: an answer after the timeout delivers nothing, also when it allows.
    func testALoadAllowedAfterItTimedOutDeliversNothing() throws {
        let app = try launchApp(section: .clipboard)
        writeFromTheRunner()
        try app.start("clipboard.loadText")
        let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")
        XCTAssertTrue(springboard.alerts.firstMatch.waitForExistence(timeout: 10), "no paste alert")
        Thread.sleep(forTimeInterval: 17)
        try answerPaste("Allow Paste")
        XCTAssertEqual(try app.waitForLine(ofRow: "clipboard.loadText"), line("loadText", "\(ClipboardError.timedOut) 0 hasId=true kind=-1 text=NULL"))
        Thread.sleep(forTimeInterval: 1)
        XCTAssertFalse(app.isDrawnLine(ofRow: "clipboard.loadText", occurrence: 1), "a second completion")
    }

    func testLoadingWhatTheAppWrote() throws {
        let app = try launchApp(section: .clipboard)
        XCTAssertEqual(try run(app, "copy"), line("copy", "0 0"))
        XCTAssertEqual(try run(app, "loadText"), line("loadText", "0 0 hasId=true kind=0 text=\(text)"))
        XCTAssertEqual(try run(app, "loadFile"), line("loadFile", "0 0 hasId=true kind=3 text=NULL file=\(text)"))
        XCTAssertEqual(try run(app, "clear"), line("clear", "0 0"))
        XCTAssertEqual(try run(app, "loadText"), line("loadText", "\(ClipboardError.noMatchingItem) 0 hasId=true kind=-1 text=NULL"))
    }

    /// The general pasteboard is observed here only, on the simulator (the unit tests stay on named ones).
    func testObservingTheGeneralPasteboard() throws {
        let app = try launchApp(section: .clipboard)
        XCTAssertEqual(try run(app, "addListener"), line("addListener", "added 0 hasHandle=true"))
        XCTAssertEqual(try run(app, "copy"), line("copy", "0 0"))
        Thread.sleep(forTimeInterval: 1)
        XCTAssertFalse(app.isDrawnLine(ofRow: "clipboard.addListener", occurrence: 1), "registering started observing")

        XCTAssertEqual(try run(app, "startObserving"), line("startObserving", "0 0"))
        XCTAssertEqual(try run(app, "copy"), line("copy", "0 0"))
        let change = try app.waitForLine(ofRow: "clipboard.addListener", occurrence: 1)
        XCTAssertTrue(change.hasPrefix(line("addListener", "change kind=0 scope=0 name=NULL")), change)
        XCTAssertEqual(try run(app, "stopObserving"), line("stopObserving", "0 0"))
        XCTAssertEqual(try run(app, "removeListener"), line("removeListener", "removed"))
    }

    func testObservingANamedPasteboardToItsRemoval() throws {
        let app = try launchApp(section: .clipboard)
        XCTAssertEqual(try run(app, "startObservingNamed"), line("startObservingNamed", "\(ClipboardError.unavailable) 0"), "it is not there yet")
        XCTAssertEqual(try run(app, "createNamed"), line("createNamed", "0 0 name=com.jonghyunkim.nativetoolkit.capi.ui"))
        XCTAssertEqual(try run(app, "addListener"), line("addListener", "added 0 hasHandle=true"))
        XCTAssertEqual(try run(app, "startObservingNamed"), line("startObservingNamed", "0 0"))
        XCTAssertEqual(try run(app, "copyNamed"), line("copyNamed", "0 0"))
        let changed = try app.waitForLine(ofRow: "clipboard.addListener", occurrence: 1)
        XCTAssertTrue(changed.contains("change kind=0 scope=1 name=com.jonghyunkim.nativetoolkit.capi.ui"), changed)
        XCTAssertEqual(try run(app, "removeNamed"), line("removeNamed", "0 0"))
        XCTAssertTrue(try app.waitForLine(ofRow: "clipboard.addListener", matching: "change kind=1 scope=1 name=com.jonghyunkim.nativetoolkit.capi.ui"))
        XCTAssertEqual(try run(app, "stopObserving"), line("stopObserving", "0 0"))
        XCTAssertEqual(try run(app, "removeListener"), line("removeListener", "removed"))
    }

    func testDetectingValuesTheUserDenies() throws {
        let app = try launchApp(section: .clipboard)
        UIPasteboard.general.string = "https://example.com/ntk"
        try app.start("clipboard.detectValues")
        try answerPaste("Don’t Allow Paste")
        XCTAssertEqual(try app.waitForLine(ofRow: "clipboard.detectValues"), line("detectValues", "\(ClipboardError.detectionFailed) 0 json=NULL"))
    }
}

/// The numbers of `ntk_notification_error` (`Notification.h`, `scripts/c_abi_error_numbers.json`).
private enum NotificationError {
    static let none = 0
    static let wrongThread = 16
}

/// The numbers of `ntk_clipboard_error` (`Clipboard.h`, `scripts/c_abi_error_numbers.json`).
private enum ClipboardError {
    static let emptyContent = 6
    static let emptyItems = 7
    static let unavailable = 9
    static let emptyPatterns = 12
    static let cannotRemoveGeneral = 22
    static let noMatchingItem = 23
    static let loadFailed = 24
    static let canceled = 27
    static let timedOut = 28
    static let detectionFailed = 29
}
