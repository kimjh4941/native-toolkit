//
//  DialogUITests.swift
//  IosLibraryExampleUITests
//
//  D1〜D15 of the UI test design (3.2): the six dialogs of `DialogSampleView`. The result line is
//  compared in full (U-1) after its counts `completion=<n>,callback=<n>` reached the expected
//  value (U-3).
//
//  D16〜D23 of the Swift API design (13.2): the "Swift API (2.0.0)" section, whose results are
//  counted as callbacks (`[show.<kind>] success ...` / `[show.<kind>] failure <case>`).
//

import XCTest
import Foundation

final class DialogUITests: SampleUITestCase {

    private var sample: SampleApp!

    override func setUpAfterGate() throws {
        sample = try launchSample()
        try sample.open(.dialog)
    }

    override func tearDownAfterGate() throws {
        sample = nil
    }

    // MARK: - Alert, confirm, destructive

    @MainActor
    func testD1_showAlertOK() throws {
        try sample.tap(.showAlert)
        let alert = sample.alert("Hello from iOS")
        try alert.waitShown()
        XCTAssertEqual(try alert.staticTextLabels(), ["Hello from iOS", "This is a native iOS dialog!"])
        XCTAssertEqual(try alert.buttonLabels(), ["OK"])

        // While the alert is shown, the completion has been reported once (design 8.1).
        try sample.waitForDialogCounts(DialogCounts(completion: 1, callback: 0))
        XCTAssertEqual(try sample.resultText(.dialog), success("[showAlert][completion] isSuccess: true, errorMessage: nil"))

        try alert.tapButton("OK")
        try sample.waitForDialogCounts(DialogCounts(completion: 1, callback: 1))
        XCTAssertEqual(try sample.resultText(.dialog), success("[showAlert][onButton] buttonText: OK, isSuccess: true, errorMessage: nil"))
        try alert.waitGone()
    }

    @MainActor
    func testD2_showConfirmDialogYes() throws {
        try sample.tap(.showConfirmDialog)
        let alert = sample.alert("Confirm Action")
        try alert.waitShown()
        XCTAssertEqual(try alert.staticTextLabels(), ["Confirm Action", "Are you sure you want to proceed?"])
        XCTAssertEqual(Set(try alert.buttonLabels()), ["Yes", "No"])
        XCTAssertEqual(try alert.buttonLabels().count, 2)

        try sample.waitForDialogCounts(DialogCounts(completion: 1, callback: 0))
        XCTAssertEqual(try sample.resultText(.dialog), success("[showConfirmDialog][completion] isSuccess: true, errorMessage: nil"))

        try alert.tapButton("Yes")
        try sample.waitForDialogCounts(DialogCounts(completion: 1, callback: 1))
        XCTAssertEqual(try sample.resultText(.dialog), success("[showConfirmDialog][onConfirm] confirmButtonText: Yes, isSuccess: true, errorMessage: nil"))
        try alert.waitGone()
    }

    @MainActor
    func testD3_showConfirmDialogNo() throws {
        try sample.tap(.showConfirmDialog)
        let alert = sample.alert("Confirm Action")
        try alert.waitShown()
        try alert.tapButton("No")
        try sample.waitForDialogCounts(DialogCounts(completion: 1, callback: 1))
        XCTAssertEqual(try sample.resultText(.dialog), success("[showConfirmDialog][onCancel] cancelButtonText: No, isSuccess: true, errorMessage: nil"))
        try alert.waitGone()
    }

    @MainActor
    func testD4_showDestructiveDialogDelete() throws {
        try sample.tap(.showDestructiveDialog)
        let alert = sample.alert("Delete File")
        try alert.waitShown()
        XCTAssertEqual(try alert.staticTextLabels(), ["Delete File", "This action cannot be undone. Are you sure?"])
        XCTAssertEqual(Set(try alert.buttonLabels()), ["Delete", "Cancel"])
        XCTAssertEqual(try alert.buttonLabels().count, 2)

        try alert.tapButton("Delete")
        try sample.waitForDialogCounts(DialogCounts(completion: 1, callback: 1))
        XCTAssertEqual(try sample.resultText(.dialog), success("[showDestructiveDialog][onDestructive] destructiveButtonText: Delete, isSuccess: true, errorMessage: nil"))
        try alert.waitGone()
    }

    @MainActor
    func testD5_showDestructiveDialogCancel() throws {
        try sample.tap(.showDestructiveDialog)
        let alert = sample.alert("Delete File")
        try alert.waitShown()
        try alert.tapButton("Cancel")
        try sample.waitForDialogCounts(DialogCounts(completion: 1, callback: 1))
        XCTAssertEqual(try sample.resultText(.dialog), success("[showDestructiveDialog][onCancel] cancelButtonText: Cancel, isSuccess: true, errorMessage: nil"))
        try alert.waitGone()
    }

    // MARK: - Action sheet

    @MainActor
    func testD6_showActionSheetEachOption() throws {
        let options = ["Camera", "Photo Library", "Documents"]
        var expected = DialogCounts(completion: 0, callback: 0)
        for option in options {
            try sample.tap(.showActionSheet)
            let sheet = sample.actionSheet()
            try sheet.waitShown(option: option)
            XCTAssertEqual(sheet.textCount("Please select"), 1)
            XCTAssertEqual(sheet.textCount("Please choose an option"), 1)
            for each in options {
                XCTAssertEqual(sheet.optionCount(each), 1, "option \(each)")
            }

            expected = DialogCounts(completion: expected.completion + 1, callback: expected.callback)
            try sample.waitForDialogCounts(expected)
            XCTAssertEqual(try sample.resultText(.dialog), success("[showActionSheet][completion] isSuccess: true, errorMessage: nil"))

            try sheet.tapOption(option)
            expected = DialogCounts(completion: expected.completion, callback: expected.callback + 1)
            try sample.waitForDialogCounts(expected)
            XCTAssertEqual(try sample.resultText(.dialog), success("[showActionSheet][onAction] action: \(option), isSuccess: true, errorMessage: nil"))
            try sheet.waitGone(option: option)
        }
    }

    /// iOS 18: a sheet with a Cancel button. iOS 26.2: a popover without a usable Cancel, closed by
    /// `PopoverDismissRegion` (stage 0a 3.1, R-5).
    @MainActor
    func testD7_showActionSheetCancel() throws {
        try sample.tap(.showActionSheet)
        let sheet = sample.actionSheet()
        try sheet.waitShown(option: "Camera")
        try sample.waitForDialogCounts(DialogCounts(completion: 1, callback: 0))
        if Self.osMajorVersion >= 26 {
            XCTAssertFalse(sheet.hasHittableCancel, "iOS 26 popover should have no usable Cancel")
            try sheet.tapPopoverDismissRegion()
        } else {
            XCTAssertTrue(sheet.hasHittableCancel, "iOS 18 sheet should have a Cancel button")
            try sheet.tapCancel()
        }
        try sample.waitForDialogCounts(DialogCounts(completion: 1, callback: 1))
        XCTAssertEqual(try sample.resultText(.dialog), success("[showActionSheet][onAction] action: Cancel, isSuccess: true, errorMessage: nil"))
        try sheet.waitGone(option: "Camera")
    }

    // MARK: - Text input

    @MainActor
    func testD8_textInputConfirmFollowsInput() throws {
        try sample.tap(.showTextInputDialog)
        let alert = sample.alert("Enter Name")
        try alert.waitShown()
        XCTAssertEqual(try alert.staticTextLabels(), ["Enter Name", "Please enter your name"])
        XCTAssertEqual(alert.textFieldCount, 1)
        XCTAssertEqual(try alert.textFieldPlaceholder(at: 0), "Your name here")

        XCTAssertFalse(try alert.isButtonEnabled("OK"), "OK must be disabled while empty")
        try alert.typeText("a", intoTextFieldAt: 0)
        XCTAssertTrue(try alert.isButtonEnabled("OK"), "OK must be enabled with one character")
        try alert.deleteCharacters(1, fromTextFieldAt: 0)
        XCTAssertFalse(try alert.isButtonEnabled("OK"), "OK must be disabled again after deleting")

        try alert.tapButton("Cancel")
        try sample.waitForDialogCounts(DialogCounts(completion: 1, callback: 1))
        try alert.waitGone()
    }

    @MainActor
    func testD9_textInputConfirmReportsInput() throws {
        try sample.tap(.showTextInputDialog)
        let alert = sample.alert("Enter Name")
        try alert.waitShown()
        try alert.typeText("Taro 太郎", intoTextFieldAt: 0)
        try alert.tapButton("OK")
        try sample.waitForDialogCounts(DialogCounts(completion: 1, callback: 1))
        XCTAssertEqual(try sample.resultText(.dialog), success("[showTextInputDialog][onConfirm] confirmButtonText: OK, inputText: Taro 太郎, isSuccess: true, errorMessage: nil"))
        try alert.waitGone()
    }

    @MainActor
    func testD10_textInputCancelDropsInput() throws {
        try sample.tap(.showTextInputDialog)
        let alert = sample.alert("Enter Name")
        try alert.waitShown()
        try alert.typeText("abc", intoTextFieldAt: 0)
        try alert.tapButton("Cancel")
        try sample.waitForDialogCounts(DialogCounts(completion: 1, callback: 1))
        XCTAssertEqual(try sample.resultText(.dialog), success("[showTextInputDialog][onCancel] cancelButtonText: Cancel, isSuccess: true, errorMessage: nil"))
        try alert.waitGone()
    }

    // MARK: - Login (credentials)

    @MainActor
    func testD11_loginButtonFollowsBothFields() throws {
        try sample.tap(.showLoginDialog, try credentialsToken())
        let alert = sample.alert("Login Required")
        try alert.waitShown()
        XCTAssertEqual(try alert.staticTextLabels(), ["Login Required", "Please enter your credentials"])
        XCTAssertEqual(alert.textFieldCount, 1)
        XCTAssertEqual(alert.secureTextFieldCount, 1)
        XCTAssertEqual(try alert.textFieldPlaceholder(at: 0), "Username")
        XCTAssertEqual(try alert.secureTextFieldPlaceholder(at: 0), "Password")

        XCTAssertFalse(try alert.isButtonEnabled("Login"), "Login must be disabled while both are empty")
        try alert.typeText("taro", intoTextFieldAt: 0)
        XCTAssertFalse(try alert.isButtonEnabled("Login"), "Login must be disabled with only the username")
        try alert.typeText("secret1", intoSecureTextFieldAt: 0)
        XCTAssertTrue(try alert.isButtonEnabled("Login"), "Login must be enabled with both fields")

        try alert.tapButton("Cancel")
        try sample.waitForDialogCounts(DialogCounts(completion: 1, callback: 1))
        try alert.waitGone()
    }

    /// The result line shows the username and only the length of the password (1b SA-16; before
    /// 1b the password was in plain text, UI test design 8.5).
    @MainActor
    func testD12_loginReportsCredentials() throws {
        try sample.tap(.showLoginDialog, try credentialsToken())
        let alert = sample.alert("Login Required")
        try alert.waitShown()
        try alert.typeText("taro", intoTextFieldAt: 0)
        try alert.typeText("secret1", intoSecureTextFieldAt: 0)
        try alert.tapButton("Login")
        try sample.waitForDialogCounts(DialogCounts(completion: 1, callback: 1))
        XCTAssertEqual(try sample.resultText(.dialog), success("[showLoginDialog][onLogin] loginButtonText: Login, username: taro, password: <length=7>, isSuccess: true, errorMessage: nil"))
        try alert.waitGone()
    }

    @MainActor
    func testD13_loginCancel() throws {
        try sample.tap(.showLoginDialog, try credentialsToken())
        let alert = sample.alert("Login Required")
        try alert.waitShown()
        try alert.tapButton("Cancel")
        try sample.waitForDialogCounts(DialogCounts(completion: 1, callback: 1))
        XCTAssertEqual(try sample.resultText(.dialog), success("[showLoginDialog][onCancel] cancelButtonText: Cancel, isSuccess: true, errorMessage: nil"))
        try alert.waitGone()
    }

    // MARK: - Exactly one completion and one callback

    /// For each dialog except login: the counts grow by exactly one completion and one callback,
    /// and nothing more arrives in 2 seconds (fixed wait. U-14).
    @MainActor
    func testD14_eachDialogReportsCompletionAndCallbackOnce() throws {
        try assertOneEach("ShowAlert") {
            try sample.tap(.showAlert)
            let alert = sample.alert("Hello from iOS")
            try alert.waitShown()
            try alert.tapButton("OK")
            try alert.waitGone()
        }
        try assertOneEach("ShowConfirmDialog") {
            try sample.tap(.showConfirmDialog)
            let alert = sample.alert("Confirm Action")
            try alert.waitShown()
            try alert.tapButton("Yes")
            try alert.waitGone()
        }
        try assertOneEach("ShowDestructiveDialog") {
            try sample.tap(.showDestructiveDialog)
            let alert = sample.alert("Delete File")
            try alert.waitShown()
            try alert.tapButton("Delete")
            try alert.waitGone()
        }
        try assertOneEach("ShowActionSheet") {
            try sample.tap(.showActionSheet)
            let sheet = sample.actionSheet()
            try sheet.waitShown(option: "Camera")
            try sheet.tapOption("Camera")
            try sheet.waitGone(option: "Camera")
        }
        try assertOneEach("ShowTextInputDialog") {
            try sample.tap(.showTextInputDialog)
            let alert = sample.alert("Enter Name")
            try alert.waitShown()
            try alert.typeText("abc", intoTextFieldAt: 0)
            try alert.tapButton("OK")
            try alert.waitGone()
        }
    }

    @MainActor
    func testD15_loginReportsCompletionAndCallbackOnce() throws {
        let token = try credentialsToken()
        try assertOneEach("ShowLoginDialog") {
            try sample.tap(.showLoginDialog, token)
            let alert = sample.alert("Login Required")
            try alert.waitShown()
            try alert.typeText("taro", intoTextFieldAt: 0)
            try alert.typeText("secret1", intoSecureTextFieldAt: 0)
            try alert.tapButton("Login")
            try alert.waitGone()
        }
    }

    // MARK: - Swift API (2.0.0): D16〜D23

    /// D16: the six requests of SA-01 once each; the input is reported by its lengths only.
    @MainActor
    func testD16_requestsReportOneResultEach() throws {
        var callbacks = 0
        func expectResult(_ body: String, success isSuccess: Bool = true) throws {
            callbacks += 1
            try sample.waitForDialogCounts(DialogCounts(completion: 0, callback: callbacks))
            XCTAssertEqual(try sample.resultText(.dialog), ResultLine.expected(success: isSuccess, body))
        }

        try sample.tap(.showRequestAlert)
        var alert = sample.alert("Request Alert")
        try alert.waitShown()
        XCTAssertEqual(try alert.buttonLabels(), ["OK"])
        try alert.tapButton("OK")
        try expectResult("[show.alert] success button=primary title=OK input=nil")
        try alert.waitGone()

        for (button, expected) in [("Yes", "button=primary title=Yes"), ("No", "button=cancel title=No")] {
            try sample.tap(.showRequestConfirm)
            alert = sample.alert("Request Confirm")
            try alert.waitShown()
            try alert.tapButton(button)
            try expectResult("[show.confirm] success \(expected) input=nil")
            try alert.waitGone()
        }

        try sample.tap(.showRequestDestructive)
        alert = sample.alert("Request Delete")
        try alert.waitShown()
        try alert.tapButton("Delete")
        try expectResult("[show.destructive] success button=destructive title=Delete input=nil")
        try alert.waitGone()

        try sample.tap(.showRequestActionSheet)
        let sheet = sample.actionSheet()
        try sheet.waitShown(option: "Green")
        try sheet.tapOption("Green")
        try expectResult("[show.actionSheet] success button=option(1) title=Green input=nil")
        try sheet.waitGone(option: "Green")

        try sample.tap(.showRequestTextInput)
        alert = sample.alert("Request Name")
        try alert.waitShown()
        XCTAssertFalse(try alert.isButtonEnabled("OK"), "OK must be disabled while empty")
        try alert.typeText("abc", intoTextFieldAt: 0)
        try alert.tapButton("OK")
        try expectResult("[show.textInput] success button=primary title=OK input=text(length: 3)")
        try alert.waitGone()

        try sample.tap(.showRequestLogin, try credentialsToken())
        alert = sample.alert("Request Login")
        try alert.waitShown()
        try alert.typeText("taro", intoTextFieldAt: 0)
        try alert.typeText("secret1", intoSecureTextFieldAt: 0)
        try alert.tapButton("Login")
        try expectResult("[show.login] success button=primary title=Login input=login(username: length 4, password: length 7)")
        try alert.waitGone()
    }

    /// D17: two requests in the same turn are both shown, the second over the first (P1-12), and
    /// each reports once.
    @MainActor
    func testD17_twoRequestsInOneTurnAreBothShown() throws {
        try sample.tap(.showTwoInOneTurn)
        let second = sample.alert("Second")
        try second.waitShown()
        try second.tapButton("Second OK")
        try sample.waitForDialogCounts(DialogCounts(completion: 0, callback: 1))
        XCTAssertEqual(try sample.resultText(.dialog), success("[show.alert] success button=primary title=Second OK input=nil"))
        try second.waitGone()

        let first = sample.alert("First")
        try first.waitShown()
        try first.tapButton("First OK")
        try sample.waitForDialogCounts(DialogCounts(completion: 0, callback: 2))
        XCTAssertEqual(try sample.resultText(.dialog), success("[show.alert] success button=primary title=First OK input=nil"))
        try first.waitGone()
        sample.observeQuietly(for: 2)
        XCTAssertEqual(try sample.dialogCounts(), DialogCounts(completion: 0, callback: 2))
    }

    /// D18: cancelled 3 seconds after the tap: the dialog goes away and `canceled` comes once. The
    /// sample notes that the dialog was shown when it cancelled it (`shown=true`), so the test does
    /// not have to find the dialog before the timer ends it.
    @MainActor
    func testD18_cancelDismissesTheDialog() throws {
        try sample.tap(.showThenCancel)
        let alert = sample.alert("Cancel Me")
        try sample.waitForDialogCounts(DialogCounts(completion: 0, callback: 1))
        XCTAssertEqual(try sample.resultText(.dialog), failure("[show.alert] failure canceled shown=true"), "cancelled while shown")
        try alert.waitGone()
        sample.observeQuietly(for: 2)
        XCTAssertEqual(try sample.dialogCounts(), DialogCounts(completion: 0, callback: 1))
    }

    /// D19: cancelled while another screen covers it: both stay, `canceled` comes once, and the
    /// dialog's button then does nothing (P1-24). The sample notes that the cover was over the
    /// dialog when it cancelled it (`covered=true`); once the sample has closed the cover, the
    /// dialog is still there (dismissing the dialog would have taken the cover with it).
    @MainActor
    func testD19_aCoveredDialogStaysWhenCancelled() throws {
        try sample.tap(.showCoverThenCancel)
        let alert = sample.alert("Covered")
        try sample.waitForDialogCounts(DialogCounts(completion: 0, callback: 1))
        XCTAssertEqual(try sample.resultText(.dialog), failure("[show.confirm] failure canceled covered=true"),
                       "cancelled while the cover was over the dialog")

        // The sample closes the cover 3 seconds after the cancellation.
        let deadline = Date().addingTimeInterval(8)
        while sample.dialogCoverExists && Date() < deadline {
            Thread.sleep(forTimeInterval: 0.2)
        }
        XCTAssertFalse(sample.dialogCoverExists, "the sample closes the cover")
        try alert.waitShown()
        try alert.tapButton("Yes")
        try alert.waitGone()
        sample.observeQuietly(for: 2)
        XCTAssertEqual(try sample.dialogCounts(), DialogCounts(completion: 0, callback: 1), "the button of a cancelled dialog does nothing")
        XCTAssertEqual(try sample.resultText(.dialog), failure("[show.confirm] failure canceled covered=true"))
    }

    /// D20: dismissed by the sample from outside the library: `dismissedBySystem` comes once (the
    /// release watch). The sample notes that the dialog was shown when it dismissed it.
    @MainActor
    func testD20_aDialogDismissedFromOutsideReportsDismissedBySystem() throws {
        try sample.tap(.showThenDismissFromOutside)
        let alert = sample.alert("Dismissed From Outside")
        try sample.waitForDialogCounts(DialogCounts(completion: 0, callback: 1))
        XCTAssertEqual(try sample.resultText(.dialog), failure("[show.alert] failure dismissedBySystem shown=true"),
                       "dismissed while shown")
        try alert.waitGone()
        sample.observeQuietly(for: 2)
        XCTAssertEqual(try sample.dialogCounts(), DialogCounts(completion: 0, callback: 1))
    }

    /// D21: shown while the sample is in the background: `notForeground` once, and no dialog.
    @MainActor
    func testD21_aRequestInTheBackgroundReportsNotForeground() throws {
        let springboard = Springboard(try systemUIToken())
        try sample.tap(.showAfter3Seconds)
        try springboard.goHome()
        // A fixed wait (U-14 exception): the request comes 3 seconds after the tap while the
        // sample is in the background, where its result line cannot be read.
        Thread.sleep(forTimeInterval: 5)
        try sample.activate()
        try sample.waitForDialogCounts(DialogCounts(completion: 0, callback: 1))
        XCTAssertEqual(try sample.resultText(.dialog), failure("[show.alert@background] failure notForeground"))
        XCTAssertFalse(sample.alert("Delayed").exists, "no dialog")
    }

    /// D22: shown while Control Center is over the sample (`foregroundInactive`): the dialog is
    /// shown (G-6, MS-02) and answers once Control Center is closed.
    @MainActor
    func testD22_aRequestUnderControlCenterIsShown() throws {
        let springboard = Springboard(try systemUIToken())
        try sample.tap(.showAfter3Seconds)
        try springboard.openControlCenter()
        let alert = sample.alert("Delayed")
        // The request comes 3 seconds after the tap.
        try alert.waitShown(timeout: SampleApp.dialogTimeout + 3)
        XCTAssertEqual(try sample.dialogCounts(), DialogCounts(completion: 0, callback: 0))
        try springboard.closeControlCenter()
        try alert.waitShown()
        try alert.tapButton("OK")
        try sample.waitForDialogCounts(DialogCounts(completion: 0, callback: 1))
        XCTAssertEqual(try sample.resultText(.dialog), success("[show.alert@foregroundInactive] success button=primary title=OK input=nil"),
                       "requested while Control Center was over the sample")
    }

    /// D23: both kinds of action sheet present without crashing, with the popover anchored (the
    /// iPad with iOS 18 raised `NSGenericException` for an action sheet without an anchor; P1-20).
    @MainActor
    func testD23_actionSheetsPresentWithAnAnchor() throws {
        try sample.tap(.showActionSheet)
        var sheet = sample.actionSheet()
        try sheet.waitShown(option: "Documents")
        try sheet.tapOption("Documents")
        try sample.waitForDialogCounts(DialogCounts(completion: 1, callback: 1))
        try sheet.waitGone(option: "Documents")

        try sample.tap(.showRequestActionSheet)
        sheet = sample.actionSheet()
        try sheet.waitShown(option: "Red")
        try sheet.tapOption("Red")
        try sample.waitForDialogCounts(DialogCounts(completion: 1, callback: 2))
        XCTAssertEqual(try sample.resultText(.dialog), success("[show.actionSheet] success button=option(0) title=Red input=nil"))
        try sheet.waitGone(option: "Red")
    }

    // MARK: - Helpers

    private func success(_ body: String) -> String {
        ResultLine.expected(success: true, body)
    }

    private func failure(_ body: String) -> String {
        ResultLine.expected(success: false, body)
    }

    /// Runs `operation` and checks that the counts grew by exactly (+1, +1), also after 2 seconds.
    @MainActor
    private func assertOneEach(_ name: String, _ operation: () throws -> Void) throws {
        let before = try sample.dialogCounts()
        try operation()
        let expected = DialogCounts(completion: before.completion + 1, callback: before.callback + 1)
        try sample.waitForDialogCounts(expected)
        sample.observeQuietly(for: 2)
        XCTAssertEqual(try sample.dialogCounts(), expected, "\(name): counts after 2 seconds")
    }
}
