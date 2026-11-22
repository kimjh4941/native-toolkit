//
//  ClipboardPasteUITests.swift
//  IosLibraryExampleUITests
//
//  CB1, CB3 and CB4 of the UI test design (3.5): the test runner (another app) writes the
//  general pasteboard, and the sample reads it as content from another app. CB1 allows the paste
//  alert explicitly through springboard; its interruption monitor presses nothing (U-8). CB3 and
//  CB4 use the system paste control, which reads without the alert. The pasteboard's
//  `changeCount` must not change between the runner's write and the sample's read (U-10).
//
//  CB5 and CB6 (Swift API design 13.2, stage 1b C4) load through a `RequestBox` and cancel it
//  (sample SA-15). CB5 loads the sample's own text, so the started load raises no paste alert.
//  CB6 cancels the box before the load over the runner's text: a load that read the pasteboard
//  would raise the paste alert, so no alert means nothing was read.
//

import XCTest
import Foundation

final class ClipboardPasteUITests: SampleUITestCase {

    private var sample: SampleApp!

    override func setUpAfterGate() throws {
        sample = try launchSample()
    }

    override func tearDownAfterGate() throws {
        sample = nil
    }

    /// CB1: Load Text -> the paste alert -> Allow Paste -> the text's length.
    @MainActor
    func testCB1_allowPasteLoadsText() throws {
        let clip = try clipboardToken()
        let springboard = Springboard(try systemUIToken())
        let text = "ntk-cb1-\(Int(Date().timeIntervalSince1970))"
        let pasteboard = RunnerPasteboard(clip)
        let written = pasteboard.write(text)
        try sample.openClipboard(clip)
        try useGeneral(clip)

        try pasteboard.requireUnchanged(since: written)
        let sequence = try sample.clipboardSequence(clip)
        try sample.tap(.loadText, clip)
        XCTAssertTrue(springboard.waitForAlert(), "the paste alert did not appear")
        XCTAssertTrue(try springboard.alertNamesSample(), "the paste alert does not name the sample")
        try springboard.tapPasteAlertFromKnownSource(SystemLabels.allowPaste)
        XCTAssertEqual(
            try sample.waitForClipboardResult(clip, sequence: sequence + 1),
            "✅ #\(sequence + 1) [loadText] textLength=\(text.count)"
        )
        XCTAssertEqual(sample.remainingAlertCount, 0, "alerts left after the paste")
    }

    /// CB3: the paste control reads text without an alert (2 seconds. U-14).
    @MainActor
    func testCB3_pasteControlReadsText() throws {
        let clip = try clipboardToken()
        let pasteboard = RunnerPasteboard(clip)
        let written = pasteboard.write("ntk-cb3-\(Int(Date().timeIntervalSince1970))")
        try assertPasteControl(clip, pasteboard, written)
    }

    /// CB4: the paste control reads an image-only pasteboard (`public.image` is accepted).
    @MainActor
    func testCB4_pasteControlReadsImageOnly() throws {
        let clip = try clipboardToken()
        let pasteboard = RunnerPasteboard(clip)
        let written = pasteboard.writeImageOnly()
        try assertPasteControl(clip, pasteboard, written)
    }

    /// CB5: Load Text through a box cancelled right after the call: `CLIPBOARD_CANCELLED`, once.
    /// The box was closed when `cancelLoad` returned (the sample's result line), and no second
    /// completion and no alert come within 2 seconds (U-14).
    @MainActor
    func testCB5_aLoadCancelledAtOnceReportsCancelledOnce() throws {
        let clip = try clipboardToken()
        try sample.openClipboard(clip)
        try useGeneral(clip)
        let copied = try sample.clipboardSequence(clip) + 1
        try sample.tap(.copyPlainText, clip)
        XCTAssertEqual(try sample.waitForClipboardResult(clip, sequence: copied),
                       "✅ #\(copied) [copyPlainText] copied kind=plainText, scope=general")

        try sample.tap(.loadTextThenCancel, clip)
        XCTAssertEqual(
            try sample.waitForClipboardResult(clip, sequence: copied + 1),
            "ℹ️ #\(copied + 1) [loadTextThenCancel] Cancellation completed (CLIPBOARD_CANCELLED), calls=1, closedAtCancel=true"
        )
        sample.observeQuietly(for: 2)
        XCTAssertEqual(try sample.clipboardSequence(clip), copied + 1, "a second completion arrived")
        XCTAssertEqual(sample.remainingAlertCount, 0, "an alert appeared for a cancelled load")
    }

    /// CB6: Load Text with a box cancelled before the call, over the runner's text:
    /// `CLIPBOARD_CANCELLED`, once, and no paste alert within 2 seconds (nothing was read. U-14).
    @MainActor
    func testCB6_aBoxCancelledBeforeTheLoadReadsNothing() throws {
        let clip = try clipboardToken()
        let pasteboard = RunnerPasteboard(clip)
        let written = pasteboard.write("ntk-cb6-\(Int(Date().timeIntervalSince1970))")
        try sample.openClipboard(clip)
        try useGeneral(clip)

        try pasteboard.requireUnchanged(since: written)
        let sequence = try sample.clipboardSequence(clip)
        try sample.tap(.loadTextWithCancelledBox, clip)
        XCTAssertEqual(
            try sample.waitForClipboardResult(clip, sequence: sequence + 1),
            "ℹ️ #\(sequence + 1) [loadTextWithCancelledBox] Cancellation completed (CLIPBOARD_CANCELLED), calls=1, closedAtCancel=true"
        )
        sample.observeQuietly(for: 2)
        XCTAssertEqual(try sample.clipboardSequence(clip), sequence + 1, "a second completion arrived")
        XCTAssertEqual(sample.remainingAlertCount, 0, "an alert appeared: the load read the pasteboard")
    }

    // MARK: - Helpers

    @MainActor
    private func useGeneral(_ clip: ClipboardToken) throws {
        let sequence = try sample.clipboardSequence(clip)
        try sample.tap(.useGeneral, clip)
        XCTAssertEqual(try sample.waitForClipboardResult(clip, sequence: sequence + 1), "✅ #\(sequence + 1) [useGeneral] scope=general")
    }

    @MainActor
    private func assertPasteControl(_ clip: ClipboardToken, _ pasteboard: RunnerPasteboard, _ written: Int) throws {
        try sample.openClipboard(clip)
        try sample.tap(.mountPasteControl, clip)
        XCTAssertEqual(try sample.pasteSummary(clip), "Paste result: -")
        try pasteboard.requireUnchanged(since: written)
        try sample.tapPasteControl(clip)
        try sample.waitForPasteSummary(clip, "Paste result: items=1, failures=0")
        sample.observeQuietly(for: 2)
        XCTAssertEqual(sample.remainingAlertCount, 0, "an alert appeared for the paste control")
    }
}
