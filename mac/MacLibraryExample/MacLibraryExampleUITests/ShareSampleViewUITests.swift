//
//  ShareSampleViewUITests.swift
//  MacLibraryExampleUITests
//
//  Created by Kim Jong Hyun on 2026/07/11.
//

import XCTest

/// UI tests for `ShareSampleView`, driving `MacShareManager` through real button clicks.
///
/// ## mouseDown Verification
/// `MacShareManager.share(content:completion:)`'s picker path was flagged as unverified in
/// implementation result v2 / design doc §12,§14: it hops through `Task { @MainActor in ... }`
/// before calling `NSSharingServicePicker.show(...)`, and Swift does not guarantee that hop
/// preserves the caller's `mouseDown` event context.
///
/// XCUITest's `.click()` dispatches genuine synthetic OS-level mouse events (distinct from
/// AppleScript/System Events UI scripting, which requires separate Accessibility trust and was
/// unavailable when this risk was first documented). A passing picker-mode test here is real
/// evidence — captured via the accessibility tree — that the picker appears and its delegate
/// callbacks resolve correctly when the button is triggered by a real click.
final class ShareSampleViewUITests: XCTestCase {

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    // MARK: - Navigation

    @MainActor
    private func openShareExample(_ app: XCUIApplication) {
        app.launch()
        app.buttons.matching(NSPredicate(format: "label CONTAINS %@", "Share Example")).firstMatch.click()
    }

    private func waitForResult(_ app: XCUIApplication, containing text: String, timeout: TimeInterval = 5) -> Bool {
        let predicate = NSPredicate(format: "value CONTAINS %@", text)
        return app.staticTexts.matching(predicate).firstMatch.waitForExistence(timeout: timeout)
    }

    /// Clicks a picker-mode button, selects the side-effect-free "Copy" service if the picker
    /// appears, otherwise dismisses with Escape, and asserts the result resolved (did not hang).
    @MainActor
    private func runPickerButtonAndResolve(_ app: XCUIApplication, buttonLabel: String, resultContains: String) {
        app.buttons[buttonLabel].click()
        let copyButton = app.buttons["Copy"]
        if copyButton.waitForExistence(timeout: 3) {
            copyButton.click()
        } else {
            app.typeKey(.escape, modifierFlags: [])
        }
        XCTAssertTrue(waitForResult(app, containing: resultContains, timeout: 5),
                       "Expected result containing '\(resultContains)' after clicking \(buttonLabel)")
    }

    // MARK: - Navigation

    @MainActor
    func testShareExampleCardNavigatesToShareScreen() throws {
        let app = XCUIApplication()
        openShareExample(app)
        XCTAssertTrue(app.staticTexts["Share Example"].waitForExistence(timeout: 3))
    }

    // MARK: - Picker mode: appearance / cancel / complete (mouseDown verification)

    /// Verifies the picker actually appears on a real click, and that dismissing it with Escape
    /// resolves the call as `completed=false` (cancelled), matching `didChoose(nil)` handling.
    @MainActor
    func testShareTextPickerAppearsAndCancelResolves() throws {
        let app = XCUIApplication()
        openShareExample(app)
        app.buttons["ShareText"].click()

        XCTAssertTrue(app.buttons["Copy"].waitForExistence(timeout: 3),
                       "Expected the sharing picker to appear with at least the Copy service")

        app.typeKey(.escape, modifierFlags: [])

        XCTAssertTrue(waitForResult(app, containing: "completed=false (cancelled)"))
    }

    /// Selects the "Copy" service from the picker to verify the `completed=true` path resolves
    /// with the chosen service name.
    @MainActor
    func testShareTextPickerCopyServiceCompletes() throws {
        let app = XCUIApplication()
        openShareExample(app)
        app.buttons["ShareText"].click()

        let copyButton = app.buttons["Copy"]
        XCTAssertTrue(copyButton.waitForExistence(timeout: 3), "Expected the sharing picker's Copy service button to appear")
        copyButton.click()

        XCTAssertTrue(waitForResult(app, containing: "completed=true, service=Copy"))
    }

    // MARK: - Picker mode: item conversion (Text / URL / Image / File / Multiple)

    @MainActor
    func testShareURLPickerResolves() throws {
        let app = XCUIApplication()
        openShareExample(app)
        runPickerButtonAndResolve(app, buttonLabel: "ShareURL", resultContains: "shareURL")
    }

    /// Verifies the `test-image` asset -> temp PNG -> `.imageFile(path:)` bridging (design doc
    /// §4.3) does not throw `imageLoadFailed` and the picker reaches a resolved state.
    @MainActor
    func testShareImagePickerResolves() throws {
        let app = XCUIApplication()
        openShareExample(app)
        runPickerButtonAndResolve(app, buttonLabel: "ShareImage", resultContains: "shareImage")
    }

    @MainActor
    func testShareFilePickerResolves() throws {
        let app = XCUIApplication()
        openShareExample(app)
        runPickerButtonAndResolve(app, buttonLabel: "ShareFile", resultContains: "shareFile")
    }

    @MainActor
    func testShareMultipleImagesPickerResolves() throws {
        let app = XCUIApplication()
        openShareExample(app)
        runPickerButtonAndResolve(app, buttonLabel: "ShareMultipleImages", resultContains: "shareMultipleImages")
    }

    @MainActor
    func testShareMultipleFilesPickerResolves() throws {
        let app = XCUIApplication()
        openShareExample(app)
        runPickerButtonAndResolve(app, buttonLabel: "ShareMultipleFiles", resultContains: "shareMultipleFiles")
    }

    @MainActor
    func testShareTextAndURLPickerResolves() throws {
        let app = XCUIApplication()
        openShareExample(app)
        runPickerButtonAndResolve(app, buttonLabel: "ShareTextAndURL", resultContains: "shareTextAndURL")
    }

    // MARK: - Picker mode: service filtering

    /// Exercises `excludedServiceTitles` (best-effort filtering). Note: in this environment
    /// "Add to Reading List" was not among the picker's proposed services even without
    /// exclusion, so this test can only confirm the picker still resolves normally with the
    /// exclusion list applied — it does not by itself prove the filter removed a candidate
    /// service. See implement-sample-app result for details.
    @MainActor
    func testShareExcludingServicesPickerResolves() throws {
        let app = XCUIApplication()
        openShareExample(app)
        app.buttons["ShareExcludingServices"].click()
        XCTAssertTrue(app.buttons["Copy"].waitForExistence(timeout: 3))
        app.typeKey(.escape, modifierFlags: [])
        XCTAssertTrue(waitForResult(app, containing: "shareExcludingServices", timeout: 5))
    }

    // MARK: - Direct service (no picker UI)

    /// Direct service execution (Mail compose). Opens Mail.app's compose window; closes it via
    /// Cmd+W afterward to avoid leaving state behind.
    @MainActor
    func testShareViaMailCompletesWithMailService() throws {
        let app = XCUIApplication()
        openShareExample(app)
        app.buttons["ShareViaMail"].click()
        XCTAssertTrue(waitForResult(app, containing: "completed=true, service=Mail", timeout: 8))
        // Best-effort cleanup: close the Mail compose window if one is frontmost.
        app.typeKey("w", modifierFlags: .command)
    }

    @MainActor
    func testCanPerformMailReturnsResult() throws {
        let app = XCUIApplication()
        openShareExample(app)
        app.buttons["CanPerformMail"].click()
        XCTAssertTrue(waitForResult(app, containing: "canPerformMail"))
    }

    // MARK: - Error paths (errorCode / errorMessage contract)

    @MainActor
    func testShareEmptyReturnsNoValidItemsError() throws {
        let app = XCUIApplication()
        openShareExample(app)
        app.buttons["ShareEmpty"].click()
        XCTAssertTrue(waitForResult(app, containing: "errorCode=1401"))
    }

    @MainActor
    func testShareInvalidURLReturnsInvalidURLError() throws {
        let app = XCUIApplication()
        openShareExample(app)
        app.buttons["ShareInvalidURL"].click()
        XCTAssertTrue(waitForResult(app, containing: "errorCode=1402"))
    }

    @MainActor
    func testShareMissingFileReturnsFileNotFoundError() throws {
        let app = XCUIApplication()
        openShareExample(app)
        app.buttons["ShareMissingFile"].click()
        XCTAssertTrue(waitForResult(app, containing: "errorCode=1404"))
    }

    @MainActor
    func testShareMissingImageReturnsImageLoadFailedError() throws {
        let app = XCUIApplication()
        openShareExample(app)
        app.buttons["ShareMissingImage"].click()
        XCTAssertTrue(waitForResult(app, containing: "errorCode=1403"))
    }

    @MainActor
    func testShareUnknownServiceReturnsServiceUnavailableError() throws {
        let app = XCUIApplication()
        openShareExample(app)
        app.buttons["ShareUnknownService"].click()
        XCTAssertTrue(waitForResult(app, containing: "errorCode=1406"))
    }

    // MARK: - Concurrency (busy-guard)
    //
    // A UI-level test for the busy-guard (ShareError.alreadyInProgress, errorCode 1408) was
    // attempted by clicking a second picker button while the first picker's popover was still
    // open. It is not included here: NSPopover is transient by default and consumes the first
    // outside click to dismiss itself, so the second click never reaches the underlying button
    // and no genuine concurrent invocation is reproduced at the UI layer. The busy-guard itself
    // is verified at the unit level in MacLibraryTests/Share/SharePickerPresenterTests.swift,
    // using AppKit-independent test hooks (beginInFlightForTesting/resumeInFlightForTesting).
}
