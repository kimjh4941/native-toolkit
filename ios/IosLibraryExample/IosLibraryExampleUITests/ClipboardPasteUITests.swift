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
        try springboard.tapAlertButton(SystemLabels.allowPaste)
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
