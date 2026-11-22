//
//  DialogUITests.swift
//  MacLibraryExampleUITests
//
//  D1〜D17 of the UI test design (5.2): the alert and the five panels of `DialogSampleView`. The
//  result line is read as `#<n> <text>`; each operation must add exactly one result, compared in
//  full (paths of the fixture as `<fixture>`), and no further result may arrive for 2 seconds (U-1,
//  U-3). The panels move to the runner's fixture before anything is chosen (U-11).
//

import XCTest
import Foundation

final class DialogUITests: SampleUITestCase {

    private var sample: SampleApp!

    private static let ok = "ShowDialog - result: DialogResult(buttonIndex: 0, buttonTitle: \"OK\", suppressionButtonState: false, helpButtonPressed: false, isSuccess: true)"
    private static let cancel = "ShowDialog - result: DialogResult(buttonIndex: 1, buttonTitle: \"Cancel\", suppressionButtonState: false, helpButtonPressed: false, isSuccess: true)"
    private static let delete = "ShowDialog - result: DialogResult(buttonIndex: 2, buttonTitle: \"Delete\", suppressionButtonState: false, helpButtonPressed: false, isSuccess: true)"
    private static let help = "ShowDialog - result: DialogResult(buttonIndex: -1, buttonTitle: \"\", suppressionButtonState: false, helpButtonPressed: true, isSuccess: true)"

    private static func cancelledOpen(_ button: DialogButton) -> String {
        "\(button.rawValue) - result: OpenDialogResult(filePaths: [], fileCount: 0, directoryURL: \"\", isCancelled: true, isSuccess: true)"
    }

    private static let cancelledSave = "ShowSaveFileDialog - result: SaveDialogResult(filePath: \"\", fileCount: 0, directoryURL: \"\", isCancelled: true, isSuccess: true)"

    override func setUpAfterGate() throws {
        sample = try launchSample()
        try sample.open(.dialog)
    }

    override func tearDownAfterGate() throws {
        sample = nil
    }

    // MARK: - Alert

    @MainActor
    func testD1_showDialogOK() throws {
        let before = try sample.resultSequence(.dialog)
        try sample.tap(.showDialog)
        let alert = sample.alert()
        try alert.waitShown()
        XCTAssertEqual(try alert.texts(), ["Hello from macOS", "This is a native macOS dialog!"])
        XCTAssertEqual(try alert.buttonTitle(1), "OK")
        XCTAssertEqual(try alert.buttonTitle(2), "Cancel")
        XCTAssertEqual(try alert.buttonTitle(3), "Delete")
        XCTAssertEqual(try alert.helpButtonCount(), 1)
        let checkbox = try alert.suppressionCheckbox()
        XCTAssertEqual(checkbox.title, "Don't show this again")
        XCTAssertEqual(checkbox.value as? Int, 0)

        try alert.press(1)
        try expectResult(after: before, .showDialog, Self.ok)
        try alert.waitGone()
    }

    @MainActor
    func testD2_showDialogCancel() throws {
        try runAlert(pressing: 2, expecting: Self.cancel)
    }

    @MainActor
    func testD3_showDialogDelete() throws {
        try runAlert(pressing: 3, expecting: Self.delete)
    }

    @MainActor
    func testD4_showDialogSuppressionChecked() throws {
        let before = try sample.resultSequence(.dialog)
        try sample.tap(.showDialog)
        let alert = sample.alert()
        try alert.waitShown()
        try alert.toggleSuppression()
        try sample.waitUntil("the suppression checkbox turning on", timeout: SampleApp.systemUITimeout, step: .alert) {
            (try alert.suppressionCheckbox().value as? Int) == 1
        }
        try alert.press(1)
        try expectResult(after: before, .showDialog,
                         "ShowDialog - result: DialogResult(buttonIndex: 0, buttonTitle: \"OK\", suppressionButtonState: true, helpButtonPressed: false, isSuccess: true)")
        try alert.waitGone()
    }

    /// Today the help button completes once and `OK` completes again (U-28). Both results are read
    /// from `dialog.resultHistory`, numbered and in order; 1b replaces this with DH1.
    @MainActor
    func testD5_showDialogHelpThenOK() throws {
        let before = try sample.resultSequence(.dialog)
        XCTAssertEqual(before, 0)
        try sample.tap(.showDialog)
        let alert = sample.alert()
        try alert.waitShown()
        try alert.pressHelp()
        try sample.waitForNextResult(.dialog, after: before, marker: DialogButton.showDialog.resultMarker)
        XCTAssertEqual(alert.count, 1, "the help button closed the alert")
        try alert.press(1)
        try sample.waitForNextResult(.dialog, after: before + 1, marker: DialogButton.showDialog.resultMarker)
        try sample.expectNoFurtherResult(.dialog, sequence: before + 2)

        let expected = "#\(before + 2) \(ResultLine.expected(success: true, Self.ok))"
            + " / #\(before + 1) \(ResultLine.expected(success: true, Self.help))"
        XCTAssertEqual(try sample.dialogResultHistory(), expected)
        try alert.waitGone()
    }

    /// Return presses the default `OK`, Escape `Cancel` (`\u{1b}`), and `d` `Delete`.
    @MainActor
    func testD6_showDialogKeys() throws {
        let alert = sample.alert()
        let cases: [(key: String, expected: String)] = [
            (XCUIKeyboardKey.return.rawValue, Self.ok),
            (XCUIKeyboardKey.escape.rawValue, Self.cancel),
            ("d", Self.delete)
        ]
        for (key, expected) in cases {
            let before = try sample.resultSequence(.dialog)
            try sample.tap(.showDialog)
            try alert.waitShown()
            try alert.typeKey(key)
            try expectResult(after: before, .showDialog, expected)
            try alert.waitGone()
        }
    }

    // MARK: - Open panels

    @MainActor
    func testD7_showFileDialogCancel() throws {
        let panels = try Panels(sample, try panelsToken())
        try cancelPanel(.showFileDialog, panels)
    }

    @MainActor
    func testD8_showFileDialogChoosesAFile() throws {
        let token = try panelsToken()
        let panels = try Panels(sample, token)
        let before = try sample.resultSequence(.dialog)
        try sample.tap(.showFileDialog, token)
        try panels.waitShown(.open)
        try panels.goToFixture(.open)
        try panels.choose("a.txt")
        try panels.confirm(.open)
        try expectResult(after: before, .showFileDialog,
                         "ShowFileDialog - result: OpenDialogResult(filePaths: [\"<fixture>/a.txt\"], fileCount: 1, directoryURL: \"<fixture>\", isCancelled: false, isSuccess: true)",
                         panels.fixture)
        try panels.waitGone(.open)
    }

    /// That `note.md` cannot be chosen is not readable (its row reads enabled. 9.0 3), so it is HC7.
    /// Here only the move to the fixture is checked, then the panel is cancelled.
    @MainActor
    func testD9_showFileDialogMovesToTheFixture() throws {
        let token = try panelsToken()
        let panels = try Panels(sample, token)
        let before = try sample.resultSequence(.dialog)
        try sample.tap(.showFileDialog, token)
        try panels.waitShown(.open)
        try panels.goToFixture(.open)
        XCTAssertTrue(try panels.isAtFixture(.open))
        try panels.cancel(.open)
        try expectResult(after: before, .showFileDialog, Self.cancelledOpen(.showFileDialog))
        try panels.waitGone(.open)
    }

    @MainActor
    func testD10_showMultiFileDialogChoosesTwoFiles() throws {
        let token = try panelsToken()
        let panels = try Panels(sample, token)
        let before = try sample.resultSequence(.dialog)
        try sample.tap(.showMultiFileDialog, token)
        try panels.waitShown(.open)
        try panels.goToFixture(.open)
        try panels.choose("a.txt")
        try panels.choose("pic.png", adding: true)
        try panels.confirm(.open)
        try expectResult(after: before, .showMultiFileDialog, oneOf: orders(["a.txt", "pic.png"]).map {
            "ShowMultiFileDialog - result: OpenDialogResult(filePaths: [\($0)], fileCount: 2, directoryURL: \"<fixture>\", isCancelled: false, isSuccess: true)"
        }, panels.fixture)
        try panels.waitGone(.open)
    }

    @MainActor
    func testD11_showFolderDialogChoosesAFolder() throws {
        let token = try panelsToken()
        let panels = try Panels(sample, token)
        let before = try sample.resultSequence(.dialog)
        try sample.tap(.showFolderDialog, token)
        try panels.waitShown(.open)
        try panels.goToFixture(.open)
        try panels.choose("dirA")
        try panels.confirm(.open)
        try expectResult(after: before, .showFolderDialog,
                         "ShowFolderDialog - result: OpenDialogResult(filePaths: [\"<fixture>/dirA\"], fileCount: 1, directoryURL: \"<fixture>/dirA\", isCancelled: false, isSuccess: true)",
                         panels.fixture)
        try panels.waitGone(.open)
    }

    @MainActor
    func testD12_showMultiFolderDialogChoosesTwoFolders() throws {
        let token = try panelsToken()
        let panels = try Panels(sample, token)
        let before = try sample.resultSequence(.dialog)
        try sample.tap(.showMultiFolderDialog, token)
        try panels.waitShown(.open)
        try panels.goToFixture(.open)
        try panels.choose("dirA")
        try panels.choose("dirB", adding: true)
        try panels.confirm(.open)
        try expectResult(after: before, .showMultiFolderDialog, oneOf: orders(["dirA", "dirB"]).map {
            "ShowMultiFolderDialog - result: OpenDialogResult(filePaths: [\($0)], fileCount: 2, directoryURL: \"<fixture>\", isCancelled: false, isSuccess: true)"
        }, panels.fixture)
        try panels.waitGone(.open)
    }

    // MARK: - Save panel

    /// The panel only returns the path (the library writes nothing); the runner checks that the
    /// fixture did not change.
    @MainActor
    func testD13_showSaveFileDialogReplacesDefault() throws {
        let token = try panelsToken()
        let panels = try Panels(sample, token)
        let before = try sample.resultSequence(.dialog)
        try sample.tap(.showSaveFileDialog, token)
        try panels.waitShown(.save)
        try panels.goToFixture(.save)
        try panels.confirm(.save)
        try panels.confirmReplace()
        try expectResult(after: before, .showSaveFileDialog,
                         "ShowSaveFileDialog - result: SaveDialogResult(filePath: \"<fixture>/default.txt\", fileCount: 1, directoryURL: \"<fixture>\", isCancelled: false, isSuccess: true)",
                         panels.fixture)
        try panels.waitGone(.save)
    }

    @MainActor
    func testD14_showSaveFileDialogCancel() throws {
        let token = try panelsToken()
        let panels = try Panels(sample, token)
        let before = try sample.resultSequence(.dialog)
        try sample.tap(.showSaveFileDialog, token)
        try panels.waitShown(.save)
        try panels.cancel(.save)
        try expectResult(after: before, .showSaveFileDialog, Self.cancelledSave)
        try panels.waitGone(.save)
    }

    /// A new name: no replace confirmation, and the panel adds the extension.
    @MainActor
    func testD15_showSaveFileDialogNewName() throws {
        let token = try panelsToken()
        let panels = try Panels(sample, token)
        let before = try sample.resultSequence(.dialog)
        try sample.tap(.showSaveFileDialog, token)
        try panels.waitShown(.save)
        try panels.goToFixture(.save)
        try panels.setSaveName("new-file")
        try panels.confirm(.save)
        let text = try sample.waitForNextResult(.dialog, after: before, marker: DialogButton.showSaveFileDialog.resultMarker)
        XCTAssertEqual(panels.fixture.normalized(text), ResultLine.expected(success: true,
            "ShowSaveFileDialog - result: SaveDialogResult(filePath: \"<fixture>/new-file.txt\", fileCount: 1, directoryURL: \"<fixture>\", isCancelled: false, isSuccess: true)"))
        // The replace confirmation stays away while no further result arrives (2 seconds).
        try sample.expectNoFurtherResult(.dialog, sequence: before + 1)
        XCTAssertEqual(panels.replaceButtonCount, 0, "a replace confirmation appeared for a new name")
        try panels.waitGone(.save)
    }

    // MARK: - Once per operation

    @MainActor
    func testD16_eachAlertButtonCompletesOnce() throws {
        let alert = sample.alert()
        for (number, expected) in [(1, Self.ok), (2, Self.cancel), (3, Self.delete)] {
            let before = try sample.resultSequence(.dialog)
            try sample.tap(.showDialog)
            try alert.waitShown()
            try alert.press(number)
            try expectResult(after: before, .showDialog, expected)
            try alert.waitGone()
        }
    }

    @MainActor
    func testD17_eachPanelCancelCompletesOnce() throws {
        let panels = try Panels(sample, try panelsToken())
        for button in DialogButton.allCases where button != .showDialog {
            try cancelPanel(button, panels)
        }
    }

    // MARK: - Helpers

    private func runAlert(pressing number: Int, expecting expected: String) throws {
        let before = try sample.resultSequence(.dialog)
        try sample.tap(.showDialog)
        let alert = sample.alert()
        try alert.waitShown()
        try alert.press(number)
        try expectResult(after: before, .showDialog, expected)
        try alert.waitGone()
    }

    private func cancelPanel(_ button: DialogButton, _ panels: Panels) throws {
        let kind: Panels.Kind = button == .showSaveFileDialog ? .save : .open
        let before = try sample.resultSequence(.dialog)
        try sample.tap(button, try panelsToken())
        try panels.waitShown(kind)
        try panels.cancel(kind)
        try expectResult(after: before, button,
                         kind == .save ? Self.cancelledSave : Self.cancelledOpen(button))
        try panels.waitGone(kind)
    }

    /// The next result after `before` is `body` in full, and nothing further arrives for 2 seconds.
    private func expectResult(after before: Int, _ button: DialogButton, _ body: String,
                              _ fixture: PanelFixture? = nil) throws {
        try expectResult(after: before, button, oneOf: [body], fixture)
    }

    private func expectResult(after before: Int, _ button: DialogButton, oneOf bodies: [String],
                              _ fixture: PanelFixture? = nil) throws {
        let text = try sample.waitForNextResult(.dialog, after: before, marker: button.resultMarker)
        let shown = fixture?.normalized(text) ?? text
        let expected = bodies.map { ResultLine.expected(success: true, $0) }
        XCTAssertTrue(expected.contains(shown), "result: \(shown)\nexpected one of: \(expected)")
        try sample.expectNoFurtherResult(.dialog, sequence: before + 1)
    }

    /// The quoted paths of two fixture items in both orders (`"<fixture>/a", "<fixture>/b"`).
    private func orders(_ items: [String]) -> [String] {
        let quoted = items.map { "\"<fixture>/\($0)\"" }
        return [quoted.joined(separator: ", "), quoted.reversed().joined(separator: ", ")]
    }
}
