//
//  NavigationUITests.swift
//  IosLibraryExampleUITests
//
//  M1 and M2 of the UI test design (3.1): the menu opens the Dialog, Notification and Share
//  screens and the navigation bar's back button returns to it (M1), and a screen opened again
//  starts from its initial state because the state lives in the screen's `@State` (M2). The
//  Clipboard screen needs the `clipboard` category and is opened by U1〜U21, not here.
//

import XCTest
import Foundation

final class NavigationUITests: SampleUITestCase {

    private var sample: SampleApp!

    /// The screens M1 opens. Clipboard is left out (3.1).
    private static let openedScreens: [SampleScreen] = [.dialog, .notification, .share]

    override func setUpAfterGate() throws {
        sample = try launchSample()
    }

    override func tearDownAfterGate() throws {
        sample = nil
    }

    // MARK: - M1

    @MainActor
    func testM1_menuOpensEachScreenAndBackReturnsToTheMenu() throws {
        try assertMenuShown()
        for screen in Self.openedScreens {
            try sample.open(screen)
            XCTAssertTrue(sample.isShowing(screen), "the result line of \(screen) is not shown")
            XCTAssertEqual(try sample.resultText(screen), ResultLine.initial, "result line of \(screen)")

            try sample.goBackToMenu()
            try waitUntil("the \(screen) screen closes") { !sample.isShowing(screen) }
            try assertMenuShown()
        }
    }

    // MARK: - M2

    @MainActor
    func testM2_reopenedScreensStartFromTheirInitialState() throws {
        // Dialog: ShowAlert -> OK changes the result line and both counts.
        try sample.open(.dialog)
        try assertDialogInitial()
        try sample.tap(.showAlert)
        let alert = sample.alert("Hello from iOS")
        try alert.waitShown()
        try alert.tapButton("OK")
        try sample.waitForDialogCounts(DialogCounts(completion: 1, callback: 1))
        XCTAssertEqual(try sample.resultText(.dialog), success("[showAlert][onButton] buttonText: OK, isSuccess: true, errorMessage: nil"))
        try alert.waitGone()

        try sample.goBackToMenu()
        try waitUntil("the dialog screen closes") { !sample.isShowing(.dialog) }
        try sample.open(.dialog)
        try assertDialogInitial()
        try sample.goBackToMenu()

        // Notification: HasPermission only reads the permission state, so either answer is a
        // valid change of the result line; what matters is that it changed and then reset.
        try sample.open(.notification)
        try assertNotificationInitial()
        let answer = try sample.press(.hasPermission)
        XCTAssertTrue(
            [success("[hasPermission] true"), success("[hasPermission] false")].contains(answer),
            "unexpected HasPermission result: \(answer)"
        )
        XCTAssertEqual(try sample.updateCount(.notification), 1)

        try sample.goBackToMenu()
        try waitUntil("the notification screen closes") { !sample.isShowing(.notification) }
        try sample.open(.notification)
        try assertNotificationInitial()
    }

    // MARK: - Helpers

    @MainActor
    private func assertMenuShown() throws {
        for screen in SampleScreen.allCases {
            XCTAssertTrue(sample.menuCardExists(screen), "the menu card of \(screen) is not shown")
        }
        for screen in Self.openedScreens {
            XCTAssertFalse(sample.isShowing(screen), "the \(screen) screen is still shown on the menu")
        }
    }

    @MainActor
    private func assertDialogInitial() throws {
        XCTAssertEqual(try sample.resultText(.dialog), ResultLine.initial)
        XCTAssertEqual(try sample.dialogCounts(), DialogCounts(completion: 0, callback: 0))
    }

    @MainActor
    private func assertNotificationInitial() throws {
        XCTAssertEqual(try sample.resultText(.notification), ResultLine.initial)
        XCTAssertEqual(try sample.updateCount(.notification), 0)
    }

    /// Polls `condition` every 0.2 s until it holds, for up to the element timeout (U-14). The
    /// pop animation keeps the closing screen in the hierarchy for a moment.
    private func waitUntil(_ what: String, _ condition: () -> Bool) throws {
        let deadline = Date().addingTimeInterval(SampleApp.elementTimeout)
        while !condition() {
            guard Date() < deadline else {
                throw SampleUITestError("\(what) did not happen in \(SampleApp.elementTimeout)s")
            }
            Thread.sleep(forTimeInterval: 0.2)
        }
    }

    private func success(_ body: String) -> String {
        ResultLine.expected(success: true, body)
    }
}
