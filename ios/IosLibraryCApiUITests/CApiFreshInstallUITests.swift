//
//  CApiFreshInstallUITests.swift
//  IosLibraryCApiUITests
//

import XCTest

/// The tests that start from a new install, where the notification permission is undetermined. The
/// runner deletes the app before each test of this class and runs them one per xcodebuild
/// (`CAPI_UI_CLASSES` in `scripts/ios_ui_runner.py`). The deletion is what returns the permission
/// (stage 2 working notes, chapter 5).
final class CApiFreshInstallUITests: CApiUITestCase {

    /// The second launch says that the first one's `true` means something: the marker survives a
    /// launch, so only the deletion can have removed it.
    func testTheRunnerDeletedTheApp() throws {
        let app = try launchApp(section: .common)
        XCTAssertEqual(try app.waitForLine(ofRow: "launch.freshInstall"), "[launch.freshInstall@none] true", "the app was not deleted before this test")
        try app.terminate()
        try app.launch()
        XCTAssertEqual(try app.waitForLine(ofRow: "launch.freshInstall"), "[launch.freshInstall@none] false")
    }
}
