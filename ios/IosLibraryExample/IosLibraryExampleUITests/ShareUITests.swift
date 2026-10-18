//
//  ShareUITests.swift
//  IosLibraryExampleUITests
//
//  S1〜S16 of the UI test design (3.4): the share sheet of `ShareSampleView`. Only Copy, Save to
//  Files (into On My iPhone) and closing the sheet are pressed; no other share target is touched
//  (U-13). The result line is compared in full after `updates=<n>` grew by one (U-1, U-3).
//

import XCTest
import Foundation

final class ShareUITests: SampleUITestCase {

    private var sample: SampleApp!

    private static let copyActivity = "com.apple.UIKit.activity.CopyToPasteboard"
    private static let saveToFilesActivity = "com.apple.DocumentManagerUICore.SaveToFiles"

    override func setUpAfterGate() throws {
        sample = try launchSample()
        try sample.open(.share)
    }

    override func tearDownAfterGate() throws {
        sample = nil
    }

    // MARK: - Copy

    @MainActor
    func testS1_shareTextCopy() throws {
        try assertCopy(.shareText, label: "shareText")
    }

    @MainActor
    func testS4_shareURLCopy() throws {
        try assertCopy(.shareURL, label: "shareURL")
    }

    /// The image itself is HC7.
    @MainActor
    func testS6_shareImageCopy() throws {
        try assertCopy(.shareImage, label: "shareImage")
    }

    /// Both the text and the URL reaching the receiver is HC8.
    @MainActor
    func testS10_shareMultipleCopy() throws {
        try assertCopy(.shareMultiple, label: "shareMultiple")
    }

    // MARK: - Close

    /// Closing reports `completed=false` with no error message (manual check #15).
    @MainActor
    func testS2_shareTextClose() throws {
        try assertClose(.shareText, label: "shareText")
    }

    @MainActor
    func testS3_shareURLDragDown() throws {
        let sheet = try open(.shareURL)
        let before = try sample.updateCount(.share)
        try sheet.dragHeaderDown()
        try assertResult(before, "[shareURL] completed=false (cancelled)")
        XCTAssertTrue(try sheet.waitClosed(), "the sheet stayed open")
    }

    /// The preview title is `Apple` from the moment the sheet shows, and does not change within
    /// 2 seconds (manual check #4; no network wait).
    @MainActor
    func testS5_shareURLWithPreviewShowsTitle() throws {
        let sheet = try open(.shareURLWithPreview)
        let titles = sheet.observeHeaderTitle(for: 2)
        XCTAssertEqual(titles.filter { !$0.isEmpty }, ["Apple"], "header titles seen after the sheet opened: \(titles)")
        XCTAssertEqual(titles.last, "Apple")
        let before = try sample.updateCount(.share)
        try sheet.close()
        try assertResult(before, "[shareURLWithPreview] completed=false (cancelled)")
    }

    /// Two images reaching the receiver is HC7.
    @MainActor
    func testS7_shareMultipleImagesClose() throws {
        try assertClose(.shareMultipleImages, label: "shareMultipleImages")
    }

    /// The subject itself is out of scope (design 1).
    @MainActor
    func testS11_shareWithSubjectClose() throws {
        try assertClose(.shareWithSubject, label: "shareWithSubject")
    }

    /// The excluded Copy is absent 2 seconds after the sheet showed (U-14).
    @MainActor
    func testS12_excludedCopyIsAbsent() throws {
        let sheet = try open(.shareExcludingActivities)
        sample.observeQuietly(for: 2)
        XCTAssertEqual(sheet.copyCount, 0, "Copy is shown although it is excluded")
        let before = try sample.updateCount(.share)
        try sheet.close()
        try assertResult(before, "[shareExcludingActivities] completed=false (cancelled)")
    }

    // MARK: - Save to Files

    @MainActor
    func testS8_shareFileSaveToFiles() throws {
        try assertSaveToFiles(.shareFile, label: "shareFile")
    }

    /// Both files are saved into On My iPhone (the success path; stage 0c on the iOS 26.2
    /// simulator).
    @MainActor
    func testS9_shareMultipleFilesSaveToFiles() throws {
        try assertSaveToFiles(.shareMultipleFiles, label: "shareMultipleFiles")
    }

    // MARK: - Errors (no sheet)

    @MainActor
    func testS13_shareEmptyFails() throws {
        try assertError(.shareEmpty, "[shareEmpty] errorMessage=No shareable items were provided.")
    }

    @MainActor
    func testS14_shareInvalidURLFails() throws {
        try assertError(.shareInvalidURL, "[shareInvalidURL] errorMessage=Invalid URL: not a valid url.")
    }

    @MainActor
    func testS15_shareMissingFileFails() throws {
        try assertError(.shareMissingFile, "[shareMissingFile] errorMessage=File not found at path: /nonexistent/share-missing.txt.")
    }

    @MainActor
    func testS16_shareMissingImageFails() throws {
        try assertError(.shareMissingImage, "[shareMissingImage] errorMessage=Failed to load image at path: /nonexistent/share-missing.png.")
    }

    // MARK: - Helpers

    /// Presses `button` and waits for the sheet. Opening the sheet does not change the result
    /// line; the result arrives when the sheet finishes.
    @MainActor
    private func open(_ button: ShareButton) throws -> ShareSheet {
        let token = try shareSheetToken()
        let sheet = ShareSheet(token)
        let before = try sample.updateCount(.share)
        try sample.tap(button, token)
        XCTAssertTrue(try sheet.waitOpen(), "the share sheet did not open")
        XCTAssertEqual(try sample.updateCount(.share), before, "the result changed while the sheet opened")
        return sheet
    }

    @MainActor
    private func assertResult(_ before: Int, _ body: String, success: Bool = true) throws {
        try sample.waitForUpdateCount(.share, before + 1, timeout: 15)
        XCTAssertEqual(try sample.resultText(.share), ResultLine.expected(success: success, body))
    }

    @MainActor
    private func assertCopy(_ button: ShareButton, label: String) throws {
        let sheet = try open(button)
        let before = try sample.updateCount(.share)
        try sheet.copy(try clipboardToken())
        try assertResult(before, "[\(label)] completed=true, activityType=\(Self.copyActivity)")
        XCTAssertTrue(try sheet.waitClosed(), "the sheet stayed open")
        XCTAssertEqual(sample.remainingAlertCount, 0, "alerts left after Copy")
    }

    @MainActor
    private func assertClose(_ button: ShareButton, label: String) throws {
        let sheet = try open(button)
        let before = try sample.updateCount(.share)
        try sheet.close()
        try assertResult(before, "[\(label)] completed=false (cancelled)")
        XCTAssertTrue(try sheet.waitClosed(), "the sheet stayed open")
    }

    @MainActor
    private func assertSaveToFiles(_ button: ShareButton, label: String) throws {
        let sheet = try open(button)
        let before = try sample.updateCount(.share)
        try sheet.saveToFiles(try filesToken()) { try sample.updateCount(.share) > before }
        try assertResult(before, "[\(label)] completed=true, activityType=\(Self.saveToFilesActivity)")
        XCTAssertTrue(try sheet.waitClosed(), "the sheet stayed open")
        XCTAssertEqual(sample.remainingAlertCount, 0, "alerts left after Save to Files")
    }

    /// The error result arrives and no sheet opens within 2 seconds (U-14).
    @MainActor
    private func assertError(_ button: ShareButton, _ body: String) throws {
        let token = try shareSheetToken()
        let sheet = ShareSheet(token)
        let before = try sample.updateCount(.share)
        try sample.tap(button, token)
        try assertResult(before, body, success: false)
        XCTAssertFalse(try sheet.waitOpen(timeout: 2), "a share sheet opened for an error")
    }
}
