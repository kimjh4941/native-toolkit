//
//  ClipboardPasteDenyUITests.swift
//  IosLibraryExampleUITests
//
//  CB2 of the UI test design (3.5, U-12): Don't Allow Paste makes Load Text fail. Run alone in its
//  own xcodebuild invocation. On the iOS 26.2 simulator the paste alert appears for every new
//  content the runner writes, whatever was answered before and without deleting the sample
//  (stage 0c), so the class does not declare `reinstall`. Its interruption monitor presses
//  nothing (U-8).
//

import XCTest
import Foundation

final class ClipboardPasteDenyUITests: SampleUITestCase {

    private var sample: SampleApp!

    override func setUpAfterGate() throws {
        sample = try launchSample()
    }

    override func tearDownAfterGate() throws {
        sample = nil
    }

    @MainActor
    func testCB2_denyPasteFailsLoadText() throws {
        let clip = try clipboardToken()
        let springboard = Springboard(try systemUIToken())
        let pasteboard = RunnerPasteboard(clip)
        let written = pasteboard.write("ntk-cb2-\(Int(Date().timeIntervalSince1970))")
        try sample.openClipboard(clip)
        let scopeSequence = try sample.clipboardSequence(clip)
        try sample.tap(.useGeneral, clip)
        XCTAssertEqual(try sample.waitForClipboardResult(clip, sequence: scopeSequence + 1), "✅ #\(scopeSequence + 1) [useGeneral] scope=general")

        try pasteboard.requireUnchanged(since: written)
        let sequence = try sample.clipboardSequence(clip)
        try sample.tap(.loadText, clip)
        XCTAssertTrue(springboard.waitForAlert(), "the paste alert did not appear")
        XCTAssertTrue(try springboard.alertNamesSample(), "the paste alert does not name the sample")
        try springboard.tapAlertButton(SystemLabels.dontAllowPaste)
        let result = try sample.waitForClipboardResult(clip, sequence: sequence + 1)
        XCTAssertTrue(
            result.hasPrefix("❌ #\(sequence + 1) [loadText] errorCode=CLIPBOARD_LOAD_FAILED, "),
            "unexpected result: \(result)"
        )
        XCTAssertEqual(sample.remainingAlertCount, 0, "alerts left after the paste")
    }
}
