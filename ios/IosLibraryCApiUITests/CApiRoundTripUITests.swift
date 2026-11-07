//
//  CApiRoundTripUITests.swift
//  IosLibraryCApiUITests
//

import UIKit
import XCTest

/// The path of the C ABI's UI tests with the functions that exist so far: test -> app -> C function ->
/// result line -> test, in the foreground and with the call made in the background (TB-2b), and the
/// Clipboard functions on it (TB-3), Dialog.h (TB-5) and the operations of Notification.h (TB-7).
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

    /// The two answers of the paste alert, in the languages of the simulators here (the iPad Pro is in Japanese).
    private enum PasteAnswer: String {
        case allow
        case deny

        var labels: [String] {
            switch self {
            case .allow: return ["Allow Paste", "ペーストを許可"]
            case .deny: return ["Don’t Allow Paste", "ペーストを許可しない"]
            }
        }
    }

    /// The app's main thread stops until the answer, so the alert is answered before anything of the app is read.
    private func answerPaste(_ answer: PasteAnswer) throws {
        let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")
        let button = springboard.alerts.firstMatch.buttons.matching(NSPredicate(format: "label IN %@", answer.labels)).firstMatch
        guard button.waitForExistence(timeout: 10) else {
            throw CApiUITestError("no paste alert with the \(answer.rawValue) button")
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
        try answerPaste(.allow)
        XCTAssertEqual(try app.waitForLine(ofRow: "clipboard.read"), line("read", "0 0 items=1 hasTypes=true text=written-by-the-runner"))
    }

    /// M3: a denied paste is not a failure.
    func testAReadTheUserDenies() throws {
        let app = try launchApp(section: .clipboard)
        writeFromTheRunner()
        try app.start("clipboard.read")
        try answerPaste(.deny)
        XCTAssertEqual(try app.waitForLine(ofRow: "clipboard.read"), line("read", "0 0 items=1 hasTypes=false text=NULL"))
    }

    func testReadDataTheUserDenies() throws {
        let app = try launchApp(section: .clipboard)
        writeFromTheRunner()
        try app.start("clipboard.readData")
        try answerPaste(.deny)
        XCTAssertEqual(try app.waitForLine(ofRow: "clipboard.readData"), line("readData", "0 0 data=NULL"))
    }

    func testReadDataTheUserAllows() throws {
        let app = try launchApp(section: .clipboard)
        writeFromTheRunner()
        try app.start("clipboard.readData")
        try answerPaste(.allow)
        XCTAssertEqual(try app.waitForLine(ofRow: "clipboard.readData"), line("readData", "0 0 data=written-by-the-runner"))
    }

    func testDetectingValuesTheUserAllows() throws {
        let app = try launchApp(section: .clipboard)
        UIPasteboard.general.string = "https://example.com/ntk"
        try app.start("clipboard.detectValues")
        try answerPaste(.allow)
        let values = try app.waitForLine(ofRow: "clipboard.detectValues")
        XCTAssertTrue(values.hasPrefix(line("detectValues", "0 0 json={")), values)
        XCTAssertTrue(values.contains("\"probableWebURL\":\"https://example.com/ntk\""), values)
    }

    func testALoadTheUserAllows() throws {
        let app = try launchApp(section: .clipboard)
        writeFromTheRunner()
        try app.start("clipboard.loadText")
        try answerPaste(.allow)
        XCTAssertEqual(try app.waitForLine(ofRow: "clipboard.loadText"), line("loadText", "0 0 hasId=true kind=0 text=written-by-the-runner"))
    }

    /// M3: unlike a read, a denied load is a failure.
    func testALoadTheUserDenies() throws {
        let app = try launchApp(section: .clipboard)
        writeFromTheRunner()
        try app.start("clipboard.loadText")
        try answerPaste(.deny)
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

    /// TB-10 (stage 2 working notes, 7.7): a load cancelled from another thread while the paste alert is up completes
    /// with CANCELED, and a later answer delivers nothing. The alert is answered before the app is read (as above);
    /// whether the system keeps it after the cancel is the system's, so it is answered only if it is still up.
    func testALoadCancelledWhileThePasteAlertIsUp() throws {
        let app = try launchApp(section: .clipboard)
        writeFromTheRunner()
        try app.start("clipboard.loadThenCancelLater")
        let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")
        XCTAssertTrue(springboard.alerts.firstMatch.waitForExistence(timeout: 3), "no paste alert before the cancel")
        // The row cancels 4 seconds after it started.
        Thread.sleep(forTimeInterval: 6)
        let stillUp = springboard.alerts.firstMatch.exists
        print("[TB-10] the paste alert after the cancel: \(stillUp ? "up" : "gone")")
        if stillUp {
            try answerPaste(.allow)
        }
        XCTAssertEqual(try app.waitForLine(ofRow: "clipboard.loadThenCancelLater"),
                       line("loadThenCancelLater", "\(ClipboardError.canceled) 0 hasId=true kind=-1 text=NULL"))
        Thread.sleep(forTimeInterval: 1)
        XCTAssertFalse(app.isDrawnLine(ofRow: "clipboard.loadThenCancelLater", occurrence: 1), "a second completion")
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
        try answerPaste(.deny)
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
        try answerPaste(.allow)
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

    // MARK: - Dialog.h (part 2, 12.1 and 12.2; TB-5)

    private func dialogLine(_ row: String, _ value: String, state: String = "foregroundActive") -> String {
        "[dialog.\(row)@\(state)] \(value)"
    }

    /// `<button> <option> <label>` of an answer with no input.
    private func answered(_ button: Int, _ label: String, option: Int = -1, text: String = "NULL", user: String = "NULL", pass: String = "NULL") -> String {
        "0 0 hasId=true button=\(button) option=\(option) label=\(label) text=\(text) user=\(user) pass=\(pass)"
    }

    private func failed(_ error: Int) -> String {
        "\(error) 0 hasId=true button=-1 option=-1 label=NULL text=NULL user=NULL pass=NULL"
    }

    func testAnAlertThroughC() throws {
        let app = try launchApp(section: .dialog)
        try app.start("dialog.alert")
        try app.press("Got it", inAlert: "Alert")
        XCTAssertEqual(try app.waitForLine(ofRow: "dialog.alert"), dialogLine("alert", answered(DialogButton.positive, "Got it")))
    }

    /// P2-22: a request with NULL for its button has the library's text. The alert is found without naming a title;
    /// that it has none is not checked here (`DialogMappingTests` compares the value).
    func testAZeroFilledAlertHasTheTextOfTheLibrary() throws {
        let app = try launchApp(section: .dialog)
        try app.start("dialog.alertDefault")
        try app.press("OK", inAlert: nil)
        XCTAssertEqual(try app.waitForLine(ofRow: "dialog.alertDefault"), dialogLine("alertDefault", answered(DialogButton.positive, "OK")))
    }

    func testAConfirmThroughC() throws {
        let app = try launchApp(section: .dialog)
        try app.start("dialog.confirm")
        try app.press("Yes", inAlert: "Confirm")
        XCTAssertEqual(try app.waitForLine(ofRow: "dialog.confirm"), dialogLine("confirm", answered(DialogButton.positive, "Yes")))
        try app.start("dialog.confirm")
        try app.press("No", inAlert: "Confirm")
        XCTAssertEqual(try app.waitForLine(ofRow: "dialog.confirm", occurrence: 1), dialogLine("confirm", answered(DialogButton.negative, "No")))
    }

    func testADestructiveThroughC() throws {
        let app = try launchApp(section: .dialog)
        try app.start("dialog.destructive")
        try app.press("Erase", inAlert: "Destructive")
        XCTAssertEqual(try app.waitForLine(ofRow: "dialog.destructive"), dialogLine("destructive", answered(DialogButton.destructive, "Erase")))
        try app.start("dialog.destructive")
        try app.press("Keep", inAlert: "Destructive")
        XCTAssertEqual(try app.waitForLine(ofRow: "dialog.destructive", occurrence: 1), dialogLine("destructive", answered(DialogButton.negative, "Keep")))
    }

    /// Also on the iPad (part 2, 13, TB-5), where it is a popover.
    func testAnActionSheetOption() throws {
        let app = try launchApp(section: .dialog)
        try app.start("dialog.actionSheet")
        XCTAssertFalse(app.noDialogAppears(for: 2), "`noDialogAppears` has to see an action sheet as well")
        try app.pressSheetButton("Beta")
        XCTAssertEqual(try app.waitForLine(ofRow: "dialog.actionSheet"), dialogLine("actionSheet", answered(DialogButton.option, "Beta", option: 1)))
        try app.start("dialog.actionSheet")
        try app.pressSheetButton("Alpha")
        XCTAssertEqual(try app.waitForLine(ofRow: "dialog.actionSheet", occurrence: 1), dialogLine("actionSheet", answered(DialogButton.option, "Alpha", option: 0)))
    }

    /// Part 2, 6.2 left this to be measured: the tap outside the sheet.
    func testAnActionSheetClosedByATapOutside() throws {
        let app = try launchApp(section: .dialog)
        try app.start("dialog.actionSheet")
        XCTAssertTrue(app.isButtonHittable("Alpha"), "the sheet is not shown")
        // The notes (8.3) quote which way each simulator took.
        print("[CApiRoundTripUITests] the tap outside the sheet: \(try app.tapOutsideTheSheet(buttons: ["Alpha", "Beta", "Dismiss"], cancel: "Dismiss"))")
        XCTAssertEqual(try app.waitForLine(ofRow: "dialog.actionSheet"), dialogLine("actionSheet", answered(DialogButton.negative, "Dismiss")))
    }

    func testATextInputThroughC() throws {
        let app = try launchApp(section: .dialog)
        try app.start("dialog.textInput")
        try app.type("typed text", intoField: 0, ofAlert: "Input")
        try app.press("Send", inAlert: "Input")
        XCTAssertEqual(try app.waitForLine(ofRow: "dialog.textInput"), dialogLine("textInput", answered(DialogButton.positive, "Send", text: "typed text")))
        try app.start("dialog.textInput")
        try app.type("dropped", intoField: 0, ofAlert: "Input")
        try app.press("Back", inAlert: "Input")
        XCTAssertEqual(try app.waitForLine(ofRow: "dialog.textInput", occurrence: 1), dialogLine("textInput", answered(DialogButton.negative, "Back")))
    }

    /// E-9: nonzero in C is the required form.
    func testATextInputThatIsRequired() throws {
        let app = try launchApp(section: .dialog)
        try app.start("dialog.textInputRequired")
        XCTAssertFalse(try app.isEnabled("Send", inAlert: "Input"))
        try app.type("x", intoField: 0, ofAlert: "Input")
        XCTAssertTrue(try app.isEnabled("Send", inAlert: "Input"))
        try app.press("Send", inAlert: "Input")
        XCTAssertEqual(try app.waitForLine(ofRow: "dialog.textInputRequired"), dialogLine("textInputRequired", answered(DialogButton.positive, "Send", text: "x")))
    }

    func testALoginThroughC() throws {
        let app = try launchApp(section: .dialog)
        try app.start("dialog.login")
        try app.type("account", intoField: 0, ofAlert: "Sign in")
        try app.type("hunter2", intoField: 0, secure: true, ofAlert: "Sign in")
        try app.press("Enter", inAlert: "Sign in")
        XCTAssertEqual(try app.waitForLine(ofRow: "dialog.login"), dialogLine("login", answered(DialogButton.positive, "Enter", user: "account", pass: "hunter2")))
    }

    /// A test of its own, because `testALoginThroughC` ends with the system's offer to save the password on the
    /// screen on iOS 26.2 (stage 2 working notes, 8.7): the next row cannot be pressed until it is answered.
    func testALoginLeftWithoutAnAnswer() throws {
        let app = try launchApp(section: .dialog)
        try app.start("dialog.login")
        try app.press("Leave", inAlert: "Sign in")
        XCTAssertEqual(try app.waitForLine(ofRow: "dialog.login"), dialogLine("login", answered(DialogButton.negative, "Leave")))
    }

    /// The offer of 8.7, which only iOS 26.2 made here, is the system's: with it answered the low row works again.
    /// The password is not saved. On a system that does not offer, this is the low row right after a login.
    func testALowRowAfterALogin() throws {
        let app = try launchApp(section: .dialog)
        try app.start("dialog.login")
        try app.type("account", intoField: 0, ofAlert: "Sign in")
        try app.type("hunter2", intoField: 0, secure: true, ofAlert: "Sign in")
        try app.press("Enter", inAlert: "Sign in")
        XCTAssertEqual(try app.waitForLine(ofRow: "dialog.login"), dialogLine("login", answered(DialogButton.positive, "Enter", user: "account", pass: "hunter2")))
        print("[CApiRoundTripUITests] the offer to save the password: \(try app.declineTheOfferToSaveThePassword())")
        try app.start("dialog.login")
        try app.press("Leave", inAlert: "Sign in")
        XCTAssertEqual(try app.waitForLine(ofRow: "dialog.login", occurrence: 1), dialogLine("login", answered(DialogButton.negative, "Leave")))
    }

    func testALoginThatIsRequired() throws {
        let app = try launchApp(section: .dialog)
        try app.start("dialog.loginRequired")
        XCTAssertFalse(try app.isEnabled("Enter", inAlert: "Sign in"))
        try app.type("a", intoField: 0, ofAlert: "Sign in")
        XCTAssertFalse(try app.isEnabled("Enter", inAlert: "Sign in"), "both are required")
        try app.type("b", intoField: 0, secure: true, ofAlert: "Sign in")
        XCTAssertTrue(try app.isEnabled("Enter", inAlert: "Sign in"))
        try app.press("Leave", inAlert: "Sign in")
        XCTAssertEqual(try app.waitForLine(ofRow: "dialog.loginRequired"), dialogLine("loginRequired", answered(DialogButton.negative, "Leave")))
    }

    func testANullRequestIsRejectedAtOnce() throws {
        let app = try launchApp(section: .dialog)
        XCTAssertEqual(try app.run("dialog.alertOfNull"), dialogLine("alertOfNull", "rejected 1"))
    }

    // MARK: Cancelling (OP-24)

    /// Part 2, 5.3: before the first main turn nothing is shown.
    func testACancelInTheSameTurnShowsNothing() throws {
        let app = try launchApp(section: .dialog)
        try app.start("dialog.alertAndCancel")
        XCTAssertEqual(try app.waitForLine(ofRow: "dialog.alertAndCancel"), dialogLine("alertAndCancel", failed(DialogError.canceled)))
        XCTAssertTrue(app.noDialogAppears(for: 2))
    }

    /// From another thread, with the dialog on the screen: it closes, and CANCELED comes once.
    func testACancelClosesTheDialogOnTheScreen() throws {
        let app = try launchApp(section: .dialog)
        try app.start("dialog.alertThenCancelLater")
        _ = try app.alert("Cancelled later")
        try app.waitUntilGone(alert: "Cancelled later")
        XCTAssertEqual(try app.waitForLine(ofRow: "dialog.alertThenCancelLater"), dialogLine("alertThenCancelLater", failed(DialogError.canceled)))
        Thread.sleep(forTimeInterval: 1)
        XCTAssertFalse(app.isDrawnLine(ofRow: "dialog.alertThenCancelLater", occurrence: 1), "a second completion")
    }

    /// P1-24: a dialog covered by another screen stays when cancelled, and its button then does nothing.
    func testACoveredDialogStaysWhenCancelled() throws {
        let app = try launchApp(section: .dialog)
        try app.start("dialog.coveredThenCancel")
        _ = try app.alert("Cover")
        XCTAssertEqual(try app.waitForLine(ofRow: "dialog.coveredThenCancel"), dialogLine("coveredThenCancel", failed(DialogError.canceled)))
        XCTAssertTrue(app.isAlertShown("Cover"), "the cover was closed with the dialog under it")
        try app.press("Cover OK", inAlert: "Cover")
        XCTAssertEqual(try app.waitForLine(ofRow: "dialog.coveredThenCancel", occurrence: 1), dialogLine("coveredThenCancel", answered(DialogButton.positive, "Cover OK")))
        try app.press("Covered OK", inAlert: "Covered")
        Thread.sleep(forTimeInterval: 1)
        XCTAssertFalse(app.isDrawnLine(ofRow: "dialog.coveredThenCancel", occurrence: 2), "the button of a cancelled dialog reports nothing")
    }

    func testACancelAfterTheAnswerAndOfAnUnknownIdDoNothing() throws {
        let app = try launchApp(section: .dialog)
        XCTAssertEqual(try app.run("dialog.cancelUnknown"), dialogLine("cancelUnknown", "cancel \(DialogError.none)"))
        try app.start("dialog.alert")
        try app.press("Got it", inAlert: "Alert")
        XCTAssertEqual(try app.waitForLine(ofRow: "dialog.alert"), dialogLine("alert", answered(DialogButton.positive, "Got it")))
        XCTAssertEqual(try app.run("dialog.cancelLast"), dialogLine("cancelLast", "cancel \(DialogError.none) hadId=true"))
        Thread.sleep(forTimeInterval: 1)
        XCTAssertFalse(app.isDrawnLine(ofRow: "dialog.alert", occurrence: 1))
    }

    // MARK: Two requests (P1-12), and a callback that goes on

    func testTwoRequestsInOneTurnAreBothShown() throws {
        let app = try launchApp(section: .dialog)
        try app.start("dialog.twoInOneTurn")
        try app.press("Second OK", inAlert: "Second")
        XCTAssertEqual(try app.waitForLine(ofRow: "dialog.twoInOneTurn"), dialogLine("twoInOneTurn", answered(DialogButton.positive, "Second OK")))
        try app.press("First OK", inAlert: "First")
        XCTAssertEqual(try app.waitForLine(ofRow: "dialog.twoInOneTurn", occurrence: 1), dialogLine("twoInOneTurn", answered(DialogButton.positive, "First OK")))
    }

    /// The completion cancels its own request (nothing happens) and shows the next dialog.
    func testACompletionMayShowTheNextDialog() throws {
        let app = try launchApp(section: .dialog)
        try app.start("dialog.chain")
        try app.press("Chain OK", inAlert: "Chain")
        XCTAssertEqual(try app.waitForLine(ofRow: "dialog.chain"), dialogLine("chain", answered(DialogButton.positive, "Chain OK") + " cancel=0 next=0"))
        try app.press("Chained OK", inAlert: "Chained")
        XCTAssertEqual(try app.waitForLine(ofRow: "dialog.chain", occurrence: 1), dialogLine("chain", answered(DialogButton.positive, "Chained OK")))
    }

    // MARK: The foreground (part 2, 12.1)

    /// OP-18 to OP-23 called in the background complete with NOT_FOREGROUND, and nothing is shown after coming back.
    func testEachKindCalledInTheBackgroundIsNotForeground() throws {
        let app = try launchApp(section: .dialog)
        for row in ["alert", "confirm", "destructive", "actionSheet", "textInput", "login"] {
            XCTAssertEqual(try app.runInTheBackground("dialog.\(row)"), dialogLine(row, failed(DialogError.notForeground), state: "background"))
            XCTAssertTrue(app.noDialogAppears(for: 1), row)
        }
    }

    /// Part 1, chapter 6, on the model of the sample's D22: requested while Control Center is over the app, the
    /// dialog is shown, and it is answered once Control Center is closed. The state in the line says it was
    /// really called that way. Simulator only: Control Center is reached by a drag at fixed coordinates.
    func testAnAlertRequestedUnderControlCenterIsShown() throws {
        let app = try launchApp(section: .dialog)
        try app.startAfterDelay("dialog.alert")
        try app.openControlCenter()
        _ = try app.alert("Alert", timeout: CApiUITestApp.timeout + CApiUITestApp.backgroundWait)
        try app.closeControlCenter()
        try app.press("Got it", inAlert: "Alert")
        XCTAssertEqual(try app.waitForLine(ofRow: "dialog.alert"), dialogLine("alert", answered(DialogButton.positive, "Got it"), state: "foregroundInactive"))
    }

    func testDetectingValuesTheUserDenies() throws {
        let app = try launchApp(section: .clipboard)
        UIPasteboard.general.string = "https://example.com/ntk"
        try app.start("clipboard.detectValues")
        try answerPaste(.deny)
        XCTAssertEqual(try app.waitForLine(ofRow: "clipboard.detectValues"), line("detectValues", "\(ClipboardError.detectionFailed) 0 json=NULL"))
    }

    // MARK: - Notification.h: the permission and the order of the operations (part 2, 12.2; TB-7)

    // This class runs after CApiFreshInstallUITests, whose tests run each on a new install
    // (`CAPI_UI_CLASSES` in `scripts/ios_ui_runner.py`), and keeps the install of the last of them: the
    // permission is undetermined unless that test allowed it, and the test below asks for it only then. The
    // permission dialog itself is in CApiFreshInstallUITests.

    /// Reads the row until its line holds `value`: the system updates the lists after the completion.
    private func waitForList(_ app: CApiUITestApp, _ row: String, _ value: String, timeout: TimeInterval = 10) throws -> String {
        let deadline = Date().addingTimeInterval(timeout)
        var last = ""
        repeat {
            last = try app.run("notification.\(row)")
            if last == notificationLine(row, value) {
                return last
            }
            Thread.sleep(forTimeInterval: 0.5)
        } while Date() < deadline
        return last
    }

    /// 12.2, "通知の順序と許可の後": with the permission the three adds stay, `update` replaces the request of its
    /// identifier, and the request added in the completion of `cancel_all_scheduled_async` stays (M6). A missing
    /// attachment fails in the completion (M4). The three removals take "" and remove nothing (6.3). Every other
    /// operation completes once.
    func testTheNotificationOperationsInOrderAfterThePermission() throws {
        let app = try launchApp(section: .notification)
        if try app.run("notification.status") == notificationLine("status", "0 0 status=\(NotificationStatus.notDetermined)") {
            try app.start("notification.requestPermission")
            try app.allowNotifications()
            XCTAssertEqual(try app.waitForLine(ofRow: "notification.requestPermission"), notificationLine("requestPermission", "0 0 granted=1"))
        }
        let done = "0 0"
        XCTAssertEqual(try app.run("notification.cancelAll"), notificationLine("cancelAll", done))
        XCTAssertEqual(try app.run("notification.removeAll"), notificationLine("removeAll", done))
        XCTAssertEqual(try app.run("notification.scheduleFirst"), notificationLine("scheduleFirst", done))
        XCTAssertEqual(try waitForList(app, "scheduled", "0 0 count=1 [ntk.order|First|NULL|NULL||0]"),
                       notificationLine("scheduled", "0 0 count=1 [ntk.order|First|NULL|NULL||0]"))
        XCTAssertEqual(try app.run("notification.updateSecond"), notificationLine("updateSecond", done))
        XCTAssertEqual(try waitForList(app, "scheduled", "0 0 count=1 [ntk.order|Second|NULL|NULL||0]"),
                       notificationLine("scheduled", "0 0 count=1 [ntk.order|Second|NULL|NULL||0]"))
        XCTAssertEqual(try app.run("notification.showLater"), notificationLine("showLater", done))
        let both = "0 0 count=2 [ntk.later|Later|NULL|NULL||0][ntk.order|Second|NULL|NULL||0]"
        XCTAssertEqual(try waitForList(app, "scheduled", both), notificationLine("scheduled", both))
        XCTAssertEqual(try app.run("notification.cancelLater"), notificationLine("cancelLater", done))
        XCTAssertEqual(try waitForList(app, "scheduled", "0 0 count=1 [ntk.order|Second|NULL|NULL||0]"),
                       notificationLine("scheduled", "0 0 count=1 [ntk.order|Second|NULL|NULL||0]"))

        try app.start("notification.cancelAllThenSchedule")
        XCTAssertEqual(try app.waitForLine(ofRow: "notification.cancelAllThenSchedule"), notificationLine("cancelAllThenSchedule", "0 0 schedule=0"))
        XCTAssertEqual(try app.waitForLine(ofRow: "notification.cancelAllThenSchedule", occurrence: 1), notificationLine("cancelAllThenSchedule", done))
        XCTAssertEqual(try waitForList(app, "scheduled", "0 0 count=1 [ntk.after|After|NULL|NULL||0]"),
                       notificationLine("scheduled", "0 0 count=1 [ntk.after|After|NULL|NULL||0]"))

        XCTAssertEqual(try app.run("notification.showMissingAttachment"),
                       notificationLine("showMissingAttachment", "\(NotificationError.attachmentLoadFailed) 0"))
        XCTAssertEqual(try app.run("notification.showNow"), notificationLine("showNow", done))
        XCTAssertEqual(try waitForList(app, "delivered", "0 0 count=1 [ntk.now|Now|NULL|Body||set]"),
                       notificationLine("delivered", "0 0 count=1 [ntk.now|Now|NULL|Body||set]"))
        XCTAssertEqual(try app.run("notification.removeNow"), notificationLine("removeNow", done))
        XCTAssertEqual(try waitForList(app, "delivered", "0 0 count=0 "), notificationLine("delivered", "0 0 count=0 "))

        XCTAssertEqual(try app.run("notification.removeEmpty"), notificationLine("removeEmpty", done))
        XCTAssertEqual(try app.run("notification.cancelScheduledEmpty"), notificationLine("cancelScheduledEmpty", done))
        XCTAssertEqual(try app.run("notification.removeCategoryEmpty"), notificationLine("removeCategoryEmpty", done))
        XCTAssertEqual(try waitForList(app, "scheduled", "0 0 count=1 [ntk.after|After|NULL|NULL||0]"),
                       notificationLine("scheduled", "0 0 count=1 [ntk.after|After|NULL|NULL||0]"), "\"\" removed nothing")
        XCTAssertEqual(try app.run("notification.badge"), notificationLine("badge", done))
        XCTAssertEqual(try app.run("notification.registerCategory"), notificationLine("registerCategory", done))
        XCTAssertEqual(try app.run("notification.removeCategory"), notificationLine("removeCategory", done))
        XCTAssertEqual(try app.run("notification.cancelAll"), notificationLine("cancelAll", done))
        XCTAssertEqual(try app.run("notification.removeAll"), notificationLine("removeAll", done))
        XCTAssertEqual(try waitForList(app, "scheduled", "0 0 count=0 "), notificationLine("scheduled", "0 0 count=0 "))
    }

    // MARK: - Notification.h: the events (part 2, 12.2, "通知のイベント"; TB-8)

    // The event notification of the app ("Event", category `ntk.events` with `Open` and `Reply`) is shown 3 seconds
    // after the row, so that the test can leave the app first. The app's listener registered inside the launch
    // writes each event as a `launch.interaction` line (`LaunchShape` in the app).

    private func ensureNotificationPermission(_ app: CApiUITestApp) throws {
        if try app.run("notification.status") == notificationLine("status", "0 0 status=\(NotificationStatus.notDetermined)") {
            try app.start("notification.requestPermission")
            try app.allowNotifications()
            XCTAssertEqual(try app.waitForLine(ofRow: "notification.requestPermission"), notificationLine("requestPermission", "0 0 granted=1"))
        }
        XCTAssertEqual(try app.run("notification.status"), notificationLine("status", "0 0 status=\(NotificationStatus.authorized)"),
                       "the events need the permission")
    }

    /// The scheduled and delivered notifications go when the test ends, also when it failed on the way.
    private func removeTheNotificationsAtTheEnd(_ app: CApiUITestApp) {
        // The block runs on the test's thread, after the test body, like the body itself.
        nonisolated(unsafe) let app = app
        addTeardownBlock {
            _ = try? app.activate()
            _ = try? app.run("notification.cancelAll")
            _ = try? app.run("notification.removeAll")
        }
    }

    private func showTheEventSoon(_ app: CApiUITestApp) throws {
        XCTAssertEqual(try app.run("notification.registerEventCategory"), notificationLine("registerEventCategory", "0 0"))
        XCTAssertEqual(try app.run("notification.showEventSoon"), notificationLine("showEventSoon", "0 0"))
    }

    private func interaction(kind: Int, action: String, text: String = "NULL", launch: Int = 0) -> String {
        "kind=\(kind) id=ntk.event action=\(action) category=ntk.events text=\(text) userInfo={\"k\":1} launch=\(launch)"
    }

    private let bodyTapAction = "com.apple.UNNotificationDefaultActionIdentifier"

    /// A tap on the banner, the `Open` action and a reply, each reaching the C listener once with its kind.
    func testNotificationEventsReachTheListenerOfC() throws {
        let app = try launchApp(section: .notification, listensAtLaunch: true)
        XCTAssertEqual(try app.waitForLine(ofRow: "launch.shape"), "[launch.shape@none] source=environment section=notification listen=1 saved=1")
        removeTheNotificationsAtTheEnd(app)
        try ensureNotificationPermission(app)

        try showTheEventSoon(app)
        try app.pressHome()
        try app.eventBanner().tap()
        XCTAssertEqual(try app.waitForLine(ofRow: "launch.interaction", timeout: 15),
                       "[launch.interaction@none] \(interaction(kind: NotificationEventKind.bodyTap, action: bodyTapAction))")

        try showTheEventSoon(app)
        try app.pressHome()
        try app.expandEventBanner()
        try app.tapEventAction("Open")
        XCTAssertEqual(try app.waitForLine(ofRow: "launch.interaction", occurrence: 1, timeout: 15),
                       "[launch.interaction@none] \(interaction(kind: NotificationEventKind.action, action: "ntk.open"))")

        try showTheEventSoon(app)
        try app.pressHome()
        try app.expandEventBanner()
        try app.tapEventAction("Reply")
        try app.sendEventReply("hello from C")
        try app.activate()
        XCTAssertEqual(try app.waitForLine(ofRow: "launch.interaction", occurrence: 2, timeout: 15),
                       "[launch.interaction@none] \(interaction(kind: NotificationEventKind.textInput, action: "ntk.reply", text: "hello from C"))")
        XCTAssertFalse(app.isDrawnLine(ofRow: "launch.interaction", occurrence: 3), "one event per response")
    }

    /// 12.2 "通知のイベント" (TB-10): clearing the event notification in Notification Center reaches the C listener once as
    /// DISMISS, with the system's dismiss action identifier (the category asks for the custom dismiss action).
    func testClearingTheNotificationReachesCAsDismiss() throws {
        let app = try launchApp(section: .notification, listensAtLaunch: true)
        XCTAssertEqual(try app.waitForLine(ofRow: "launch.shape"), "[launch.shape@none] source=environment section=notification listen=1 saved=1")
        removeTheNotificationsAtTheEnd(app)
        try ensureNotificationPermission(app)
        try showTheEventSoon(app)
        try app.pressHome()
        try app.clearEventInNotificationCenter()
        try app.pressHome()
        try app.activate()
        XCTAssertEqual(try app.waitForLine(ofRow: "launch.interaction", timeout: 15),
                       "[launch.interaction@none] \(interaction(kind: NotificationEventKind.dismiss, action: "com.apple.UNNotificationDismissActionIdentifier"))")
        Thread.sleep(forTimeInterval: 1)
        XCTAssertFalse(app.isDrawnLine(ofRow: "launch.interaction", occurrence: 1), "one event for the clear")
    }

    /// A banner tapped after the app was terminated starts it: the listener registered inside that launch gets
    /// the tap with `_is_launch`, and `get_launch_response_async` gives the same response, also when asked again
    /// (P2-19).
    func testATapThatStartsTheAppReachesCAsTheLaunch() throws {
        let app = try launchApp(section: .notification, listensAtLaunch: true)
        // The cold start reads what this launch saved.
        XCTAssertEqual(try app.waitForLine(ofRow: "launch.shape"), "[launch.shape@none] source=environment section=notification listen=1 saved=1")
        removeTheNotificationsAtTheEnd(app)
        try ensureNotificationPermission(app)
        try showTheEventSoon(app)
        try app.terminate()
        try app.eventBanner().tap()
        XCTAssertEqual(try app.waitForLine(ofRow: "launch.shape", timeout: 20), "[launch.shape@none] source=file section=notification listen=1 saved=-")
        let launched = interaction(kind: NotificationEventKind.bodyTap, action: bodyTapAction, launch: 1)
        XCTAssertEqual(try app.waitForLine(ofRow: "launch.interaction", timeout: 15), "[launch.interaction@none] \(launched)")
        XCTAssertEqual(try app.run("notification.launchResponse"), notificationLine("launchResponse", "0 0 response=\(launched)"))
        XCTAssertEqual(try app.run("notification.launchResponse"), notificationLine("launchResponse", "0 0 response=\(launched)"))
        XCTAssertFalse(app.isDrawnLine(ofRow: "launch.interaction", occurrence: 1), "one event for the tap")
        XCTAssertFalse(app.isDrawnLine(ofRow: "launch.settings", occurrence: 0), "the settings listener was not rejected")
    }

    // MARK: - Share.h (part 2, 12.1 "前面" and 12.2 "Share"; TB-9)

    // The sheet is opened from C and closed, or its copy action is chosen: nothing is sent to another app.

    private func shareLine(_ row: String, _ value: String, state: String = "foregroundActive") -> String {
        "[share.\(row)@\(state)] \(value)"
    }

    /// The sheet opens from C, and closing it completes with NONE and `completed` 0 and no activity.
    func testTheShareSheetFromC() throws {
        let app = try launchApp(section: .share)
        try app.start("share.text")
        XCTAssertTrue(try app.waitForShareSheet(), "the share sheet did not open")
        try app.closeShareSheet()
        XCTAssertEqual(try app.waitForLine(ofRow: "share.text"), shareLine("text", "0 0 result=completed=0,activity=NULL"))
    }

    /// 12.2, "Share": the copy action of the sheet opened from C completes with `completed` 1 and its activity type.
    /// The text goes to the simulator's pasteboard only (Simulator.app stays closed; part 2, 12.2, Clipboard).
    func testCopyingFromTheShareSheetFromC() throws {
        let app = try launchApp(section: .share)
        try app.start("share.text")
        XCTAssertTrue(try app.waitForShareSheet(), "the share sheet did not open")
        try app.copyInShareSheet()
        XCTAssertEqual(try app.waitForLine(ofRow: "share.text"),
                       shareLine("text", "0 0 result=completed=1,activity=com.apple.UIKit.activity.CopyToPasteboard"))
        XCTAssertTrue(app.noShareSheetAppears(for: 1))
    }

    /// 12.1, "前面": from the background the share ends with NOT_FOREGROUND and shows nothing.
    func testAShareFromTheBackgroundIsNotForeground() throws {
        let app = try launchApp(section: .share)
        XCTAssertEqual(try app.runInTheBackground("share.text"),
                       shareLine("text", "\(ShareError.notForeground) 0 result=NULL", state: "background"))
        XCTAssertTrue(app.noShareSheetAppears(for: 2))
    }

    /// AP-19: no item is the return value; a file that is not there is the completion, with no sheet.
    func testShareFailuresComeWhereTheDesignSays() throws {
        let app = try launchApp(section: .share)
        XCTAssertEqual(try app.run("share.empty"), shareLine("empty", "rejected \(ShareError.emptyContent)"))
        XCTAssertEqual(try app.run("share.missingFile"), shareLine("missingFile", "\(ShareError.fileNotFound) 0 result=NULL"))
        XCTAssertTrue(app.noShareSheetAppears(for: 2))
    }
}

/// The numbers of `ntk_dialog_button` and `ntk_dialog_error` (`Dialog.h`, `scripts/c_abi_error_numbers.json`).
private enum DialogButton {
    static let positive = 0
    static let negative = 1
    static let destructive = 2
    static let option = 3
}

private enum DialogError {
    static let none = 0
    static let canceled = 6
    static let notForeground = 8
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
