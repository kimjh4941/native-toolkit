//
//  ShareUITests.swift
//  MacLibraryExampleUITests
//
//  S1〜S17 of the UI test design (5.4): `ShareSampleView`. The picker is closed with Escape; on
//  macOS 26 only, Copy is pressed (S2, S4). No service is opened from the picker; the three buttons
//  that name a service run on the VM only (`realservice`. U-13). Each operation must add exactly
//  one result, compared in full, and no further result may arrive for 2 seconds (U-1, U-3).
//
//  Replaces the 17 tests of `ShareSampleViewUITests` (design 5.6), which found buttons by their
//  text, compared with `CONTAINS`, and passed on macOS 15 without the success path.
//

import XCTest
import Foundation

final class ShareUITests: SampleUITestCase {

    private var sample: SampleApp!

    /// What `.text` and `.url` put on the pasteboard through Copy (S2, S4).
    private static let sharedText = "Shared from MacLibraryExample"
    private static let sharedURL = "https://www.apple.com"

    /// Mail can take a while to start on the VM (stage 0b 4.1).
    private static let mailTimeout: TimeInterval = 30

    override func setUpAfterGate() throws {
        sample = try launchSample()
        try sample.open(.share)
    }

    override func tearDownAfterGate() throws {
        sample = nil
    }

    // MARK: - Picker, closed with Escape

    @MainActor
    func testS1_shareTextPickerEscape() throws {
        try assertCancelled(.shareText)
    }

    @MainActor
    func testS3_shareURLPickerEscape() throws {
        try assertCancelled(.shareURL)
    }

    /// The image in the picker's header is HC5.
    @MainActor
    func testS5_shareImagePickerEscape() throws {
        try assertCancelled(.shareImage)
    }

    @MainActor
    func testS6_shareFilePickerEscape() throws {
        try assertCancelled(.shareFile)
    }

    @MainActor
    func testS7_shareMultipleImagesPickerEscape() throws {
        try assertCancelled(.shareMultipleImages)
    }

    @MainActor
    func testS8_shareMultipleFilesPickerEscape() throws {
        try assertCancelled(.shareMultipleFiles)
    }

    @MainActor
    func testS9_shareTextAndURLPickerEscape() throws {
        try assertCancelled(.shareTextAndURL)
    }

    /// `Add to Reading List` stays out of the picker for 2 seconds. On the 15.8.3 VM the picker of
    /// ShareURL (the same URL without the exclusion) lists it (stage 0c), so this sees the
    /// exclusion work there.
    @MainActor
    func testS10_shareExcludingServicesHidesReadingList() throws {
        try assertCancelled(.shareExcludingServices) { picker in
            let deadline = Date().addingTimeInterval(2)
            repeat {
                XCTAssertEqual(try picker.serviceCount(named: SystemLabels.addToReadingList), 0,
                               "the excluded service is in the picker")
                Thread.sleep(forTimeInterval: 0.2)
            } while Date() < deadline
        }
    }

    // MARK: - Picker, Copy (macOS 26 only)

    @MainActor
    func testS2_shareTextCopy() throws {
        try assertCopy(.shareText, expectedPasteboard: Self.sharedText, marker: "ntk-s2")
    }

    @MainActor
    func testS4_shareURLCopy() throws {
        try assertCopy(.shareURL, expectedPasteboard: Self.sharedURL, marker: "ntk-s4")
    }

    // MARK: - Named service (VM only)

    @MainActor
    func testS11_shareViaMailCompletes() throws {
        let token = try realServiceToken()
        let others = OtherApps(token)
        let mailWasRunning = others.isMailRunning
        let before = try sample.resultSequence(.share)
        try sample.tap(.shareViaMail, token)
        let text = try sample.waitForNextResult(.share, after: before, marker: ShareButton.shareViaMail.resultMarker,
                                                timeout: Self.mailTimeout)
        let expected = SystemLabels.mailServiceName.map {
            ResultLine.expected(success: true, "[shareViaMail] completed=true, service=\($0)")
        }
        XCTAssertTrue(expected.contains(text), "result: \(text)")
        try sample.expectNoFurtherResult(.share, sequence: before + 1)
        try others.stopMail(wasRunning: mailWasRunning)
    }

    /// `canPerform=true` on the VM (stage 0c).
    @MainActor
    func testS12_canPerformMail() throws {
        let token = try realServiceToken()
        try assertServiceResult(.canPerformMail, token, success: true, "[canPerformMail] canPerform=true",
                                timeout: Self.mailTimeout)
    }

    @MainActor
    func testS17_shareUnknownServiceFails() throws {
        let token = try realServiceToken()
        try assertServiceResult(.shareUnknownService, token, success: false,
                                "[shareUnknownService] errorCode=1406, errorMessage=Sharing service unavailable: invalid.service.")
    }

    // MARK: - Errors (the picker must not appear)

    @MainActor
    func testS13_shareEmptyFails() throws {
        try assertError(.shareEmpty, "[shareEmpty] errorCode=1401, errorMessage=No shareable items were provided.")
    }

    @MainActor
    func testS14_shareInvalidURLFails() throws {
        try assertError(.shareInvalidURL, "[shareInvalidURL] errorCode=1402, errorMessage=Invalid URL: not a valid url.")
    }

    @MainActor
    func testS15_shareMissingFileFails() throws {
        try assertError(.shareMissingFile,
                        "[shareMissingFile] errorCode=1404, errorMessage=File not found at path: /nonexistent/share-missing.txt.")
    }

    @MainActor
    func testS16_shareMissingImageFails() throws {
        try assertError(.shareMissingImage,
                        "[shareMissingImage] errorCode=1403, errorMessage=Failed to load image at path: /nonexistent/share-missing.png.")
    }

    // MARK: - Helpers

    /// Opens the picker, checks it lists at least one service (names are not read), runs `whileOpen`,
    /// closes it with Escape and expects `completed=false (cancelled)` once.
    private func assertCancelled(_ button: ShareButton, whileOpen: (SharePicker) throws -> Void = { _ in }) throws {
        let token = try sharePickerToken()
        let picker = SharePicker(sample, token)
        let before = try sample.resultSequence(.share)
        try sample.tap(button, token)
        try picker.waitShown()
        XCTAssertGreaterThan(try picker.serviceCount(), 0, "the picker lists no service")
        try whileOpen(picker)
        try picker.escape()
        let text = try sample.waitForNextResult(.share, after: before, marker: button.resultMarker)
        XCTAssertEqual(text, ResultLine.expected(success: true, "[\(button.label)] completed=false (cancelled)"))
        try picker.waitGone()
        try sample.expectNoFurtherResult(.share, sequence: before + 1)
    }

    /// The error result once, and no picker and no further result for 2 seconds.
    private func assertError(_ button: ShareButton, _ body: String) throws {
        let token = try sharePickerToken()
        let picker = SharePicker(sample, token)
        let before = try sample.resultSequence(.share)
        try sample.tap(button, token)
        let text = try sample.waitForNextResult(.share, after: before, marker: button.resultMarker)
        XCTAssertEqual(text, ResultLine.expected(success: false, body))
        try picker.expectNotShown(for: 2)
        try sample.expectNoFurtherResult(.share, sequence: before + 1)
        XCTAssertEqual(picker.count, 0, "a share picker appeared")
    }

    /// A button that names a service (no picker): the result once, and no further result.
    private func assertServiceResult(_ button: ShareButton, _ token: RealServiceToken, success: Bool, _ body: String,
                                     timeout: TimeInterval = SampleApp.elementTimeout) throws {
        let before = try sample.resultSequence(.share)
        try sample.tap(button, token)
        let text = try sample.waitForNextResult(.share, after: before, marker: button.resultMarker, timeout: timeout)
        XCTAssertEqual(text, ResultLine.expected(success: success, body))
        try sample.expectNoFurtherResult(.share, sequence: before + 1)
    }

    /// The runner writes its own text first (the user's content is never read. U-10), the sample
    /// shares through Copy, and the pasteboard then holds what the sample shared.
    private func assertCopy(_ button: ShareButton, expectedPasteboard: String, marker: String) throws {
        let token = try sharePickerToken()
        let clipboard = try clipboardToken()
        let pasteboard = RunnerPasteboard(clipboard)
        let picker = SharePicker(sample, token)
        let written = try pasteboard.write("\(marker)-\(Int(Date().timeIntervalSince1970))")
        let before = try sample.resultSequence(.share)
        try sample.tap(button, token)
        try picker.waitShown()
        try pasteboard.requireUnchanged(since: written)
        try picker.copy(clipboard)
        let text = try sample.waitForNextResult(.share, after: before, marker: button.resultMarker)
        let expected = SystemLabels.copy.map {
            ResultLine.expected(success: true, "[\(button.label)] completed=true, service=\($0)")
        }
        XCTAssertTrue(expected.contains(text), "result: \(text)")
        try sample.expectNoFurtherResult(.share, sequence: before + 1)
        XCTAssertEqual(try pasteboard.readAfterWrite(since: written), expectedPasteboard)
    }
}
