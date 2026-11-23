//
//  ClipboardPasteUITests.swift
//  MacLibraryExampleUITests
//
//  CB1 of the UI test design (5.5): the Clipboard screen's `PasteButton` without the pasteboard
//  privacy preview. The runner writes its own text to the general pasteboard first (the user's
//  content is never read. U-10) -- before the sample starts, because the button is disabled when
//  the pasteboard is empty as the screen is built (stage 0c 3.4) -- checks that nothing wrote in
//  between, and presses the button. The result line is compared in full, no confirmation may appear
//  and no further result may arrive for 2 seconds (U-1, U-3). On this Mac CB1 waits until U-30
//  checks the button's window owner (`MAC_DEFERRED_TESTS`).
//

import XCTest
import Foundation

final class ClipboardPasteUITests: SampleUITestCase {

    private var sample: SampleApp!
    private var clipboard: ClipboardToken!
    private var pasteboard: RunnerPasteboard!
    /// The change count right after the runner's write.
    private var written = 0

    override func setUpAfterGate() throws {
        clipboard = try clipboardToken()
        pasteboard = RunnerPasteboard(clipboard)
        written = try pasteboard.write("ntk-cb1-\(Int(Date().timeIntervalSince1970))")
        sample = try launchSample()
        try sample.open(.clipboard)
    }

    override func tearDownAfterGate() throws {
        sample = nil
    }

    @MainActor
    func testCB1_pasteButtonPastesWithoutConfirmation() throws {
        let before = try sample.resultSequence(.clipboard)
        try pasteboard.requireUnchanged(since: written)
        try sample.pressPasteButton(clipboard)
        let text = try sample.waitForNextClipboardResult(after: before, label: "onPaste")
        XCTAssertEqual(text, ClipboardWaitRule.expected(success: true, label: "onPaste",
                                                        "items=1, failures=0, partial=false"))
        try sample.expectNoPasteConfirmation(for: SampleApp.quietPeriod)
        try sample.expectNoFurtherResult(.clipboard, sequence: before + 1)
    }
}
