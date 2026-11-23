//
//  ClipboardPrivacyUITests.swift
//  MacLibraryExampleUITests
//
//  CB2〜CB6 of the UI test design (5.5): the paste confirmation of the pasteboard privacy preview.
//  VM only (`pasteprivacy`): the runner puts `EnablePasteboardPrivacyDeveloperPreview` into the
//  sample's container before this class and restores it after (U-12). Each case writes new text
//  (a content allowed once is not asked again. Stage 0a 4.3) before the sample starts (the
//  `PasteButton` is disabled when the pasteboard is empty as the screen is built. Stage 0c 3.4), so
//  the confirmation appears for the read that follows. The results are today's behaviour on the 15.8.3 VM (stage 0c 3.3), compared
//  in full; each operation adds exactly one result and no further result arrives for 2 seconds
//  (U-1, U-3).
//

import XCTest
import Foundation

final class ClipboardPrivacyUITests: SampleUITestCase {

    private var sample: SampleApp!
    private var clipboard: ClipboardToken!
    private var prompt: PrivacyPrompt!
    private var pasteboard: RunnerPasteboard!
    /// The runner's text of this case and the change count right after it was written.
    private var writtenText = ""
    private var written = 0

    /// With the preview, the general pasteboard's access behavior reads `ask` (without it,
    /// `alwaysAllow` on the 15.8.3 VM. Stage 0c 3.3).
    private static let accessBehaviorWithPreview = "ask"

    override func setUpAfterGate() throws {
        clipboard = try clipboardToken()
        pasteboard = RunnerPasteboard(clipboard)
        writtenText = "ntk-cbp-\(Int(Date().timeIntervalSince1970))"
        written = try pasteboard.write(writtenText)
        sample = try launchSample()
        try sample.open(.clipboard)
        prompt = PrivacyPrompt(sample, try pastePrivacyToken())

        // The preview must be on before anything reads; otherwise every case below would fail for
        // the setting, not for the confirmation. Reading the access behavior reads no content.
        let before = try sample.resultSequence(.clipboard)
        try sample.pressClipboardButton("AccessBehavior", clipboard)
        let text = try sample.waitForNextClipboardResult(after: before, label: "accessBehavior")
        guard text == ClipboardWaitRule.expected(success: true, label: "accessBehavior", Self.accessBehaviorWithPreview) else {
            throw SampleUITestError(.precondition, "NTK-PRECONDITION:pastePrivacyPreview the access behavior is not \(Self.accessBehaviorWithPreview): \(text)")
        }
        try sample.expectNoFurtherResult(.clipboard, sequence: before + 1)
    }

    override func tearDownAfterGate() throws {
        sample = nil
        prompt = nil
    }

    // MARK: - PasteButton

    @MainActor
    func testCB2_pasteButtonAllowPaste() throws {
        let before = try pressAfterCheck { try sample.pressPasteButton(clipboard) }
        try prompt.waitShown()
        try prompt.allow()
        try expectResult(after: before, label: "onPaste", "items=1, failures=0, partial=false")
    }

    /// Today's behaviour: the denied paste is reported through `onPaste` as one failure, shown as a
    /// success line.
    @MainActor
    func testCB3_pasteButtonDontAllowPaste() throws {
        let before = try pressAfterCheck { try sample.pressPasteButton(clipboard) }
        try prompt.waitShown()
        try prompt.deny()
        try expectResult(after: before, label: "onPaste", "items=0, failures=1, partial=false")
    }

    // MARK: - Read

    /// `Read` in the general scope reads the runner's text (it does not write first). Today's
    /// behaviour: the denied read succeeds with one item that has no representation, and no error
    /// code is reached.
    @MainActor
    func testCB4_readDontAllowPaste() throws {
        let before = try pressAfterCheck { try sample.pressClipboardButton("Read", clipboard) }
        try prompt.waitShown()
        try prompt.deny()
        try expectResult(after: before, label: "read", "items=1, bytes=0, [0:text=none ]")
    }

    /// Allowed once, the same content is read again without a confirmation.
    @MainActor
    func testCB5_readAllowPasteThenReadAgain() throws {
        let before = try pressAfterCheck { try sample.pressClipboardButton("Read", clipboard) }
        let bytes = writtenText.utf8.count
        let detail = "items=1, bytes=\(bytes), [0:text=\(bytes)B public.utf8-plain-text]"
        try prompt.waitShown()
        try prompt.allow()
        try expectResult(after: before, label: "read", detail)

        try sample.pressClipboardButton("Read", clipboard)
        try sample.expectNoPasteConfirmation(for: SampleApp.quietPeriod)
        try expectResult(after: before + 1, label: "read", detail)
    }

    // MARK: - Access behavior and detection

    /// `DetectPatterns` and `DetectValues` write their own detection text first
    /// (`arrangeDetectionText`), so they read no outside content: no confirmation. Outside content
    /// for `detectValues` cannot be made without changing the sample (design 5.5).
    @MainActor
    func testCB6_accessBehaviorAndDetectionAskNothing() throws {
        var before = try sample.resultSequence(.clipboard)
        try sample.pressClipboardButton("AccessBehavior", clipboard)
        try expectResult(after: before, label: "accessBehavior", Self.accessBehaviorWithPreview)

        before = try sample.resultSequence(.clipboard)
        try sample.pressClipboardButton("DetectPatterns", clipboard)
        try sample.expectNoPasteConfirmation(for: SampleApp.quietPeriod)
        try expectResult(after: before, label: "detectPatterns", "found=[emailAddresses, links, probableWebURL]")

        before = try sample.resultSequence(.clipboard)
        try sample.pressClipboardButton("DetectValues", clipboard)
        try sample.expectNoPasteConfirmation(for: SampleApp.quietPeriod)
        try expectResult(after: before, label: "detectValues", "patterns=3, links=1, emails=1, probableWebURL=true")
    }

    // MARK: - Helpers

    /// The sample reads the runner's text through `press`, once nothing else wrote the pasteboard
    /// since the runner (U-10). Returns the result number before the press.
    private func pressAfterCheck(_ press: () throws -> Void) throws -> Int {
        let before = try sample.resultSequence(.clipboard)
        XCTAssertEqual(sample.pasteConfirmations.count, 0, "a paste confirmation is open before the press")
        try pasteboard.requireUnchanged(since: written)
        try press()
        return before
    }

    /// The next result in full, the confirmation gone, and no further result for 2 seconds.
    private func expectResult(after before: Int, label: String, _ detail: String) throws {
        let text = try sample.waitForNextClipboardResult(after: before, label: label)
        XCTAssertEqual(text, ClipboardWaitRule.expected(success: true, label: label, detail))
        try prompt.waitGone()
        try sample.expectNoFurtherResult(.clipboard, sequence: before + 1)
    }
}
