//
//  NotificationPermissionUITests.swift
//  MacLibraryExampleUITests
//
//  NP1〜NP3 of the UI test design (5.3, U-7): the permission prompt. VM only (`ncsettings`): the
//  runner resets the sample's notification setting in the VM before each test (in the order NP2,
//  NP3, NP1, ending with the permission granted). Each test first reads `notDetermined` and stops
//  with `NTK-PRECONDITION:notNotDetermined` otherwise. No ordinary cleanup; the sample is not
//  stopped before the prompt is answered (an unanswered prompt becomes a denial. M-2).
//

import XCTest
import Foundation

final class NotificationPermissionUITests: SampleUITestCase {

    private var sample: SampleApp!
    private var screen: NotificationScreen!

    private static let deniedText = "[requestPermission] denied. Permission dialog will not appear again. Please enable notifications in Settings."
    private static let promptTimeout: TimeInterval = 10

    override func setUpAfterGate() throws {
        sample = try launchSample()
        try sample.open(.notification)
        screen = NotificationScreen(sample)
    }

    override func tearDownAfterGate() throws {
        sample = nil
        screen = nil
    }

    private func ok(_ body: String) -> String { ResultLine.expected(success: true, body) }
    private func failed(_ body: String) -> String { ResultLine.expected(success: false, body) }

    private func requireNotDetermined() throws {
        guard try screen.run(.authorizationStatus, quiet: false) == ok("[authorizationStatus] notDetermined") else {
            throw SampleUITestError(.precondition, "NTK-PRECONDITION:notNotDetermined the permission was not reset")
        }
    }

    /// Presses `button`, answers the prompt and returns the result of the button. With `banner`, the
    /// banner the button shows is waited for before the 2-second check for an extra result.
    private func pressAndAnswer(_ button: NotificationButton, allow: Bool, _ token: NotificationToken,
                                _ settings: NCSettingsToken, center: NotificationCenterUI,
                                banner: BannerAnchor? = nil) throws -> String {
        let before = try sample.resultSequence(.notification)
        try sample.tap(button, token)
        let prompt = try center.waitForPermissionPrompt(settings, timeout: Self.promptTimeout)
        try center.answerPermissionPrompt(prompt, allow: allow, settings)
        let text = try sample.waitForNextResult(.notification, after: before, marker: button.resultMarker)
        if let banner {
            _ = try center.waitForRoot(banner, timeout: SampleApp.elementTimeout)
        }
        try sample.expectNoFurtherResult(.notification, sequence: before + 1)
        return text
    }

    /// Don’t Allow, then no prompt again; a notification is refused and no banner comes.
    @MainActor
    func testNP2_requestPermissionDontAllow() throws {
        let token = try notificationToken()
        let settings = try ncSettingsToken()
        let center = NotificationCenterUI(sample, token)
        try requireNotDetermined()
        XCTAssertEqual(try screen.run(.hasPermission), ok("[hasPermission] false"))
        XCTAssertEqual(try pressAndAnswer(.requestPermission, allow: false, token, settings, center: center),
                       failed(Self.deniedText))
        XCTAssertEqual(try screen.run(.authorizationStatus), ok("[authorizationStatus] denied"))
        XCTAssertEqual(try screen.run(.requestPermission, token), failed(Self.deniedText))
        try center.expectNoPermissionPrompt(for: 5)
        XCTAssertEqual(try screen.run(.showImmediate, token, marker: NotificationButton.notGrantedText),
                       failed(NotificationButton.notGrantedText))
        try center.expectNoRoot(.immediate, until: Date().addingTimeInterval(5))
    }

    /// ShowImmediate asks first; after Allow the banner comes.
    @MainActor
    func testNP3_showImmediateAsksThenShows() throws {
        let token = try notificationToken()
        let settings = try ncSettingsToken()
        let center = NotificationCenterUI(sample, token)
        try requireNotDetermined()
        XCTAssertEqual(try pressAndAnswer(.showImmediate, allow: true, token, settings, center: center, banner: .immediate),
                       ok("[showImmediate] success"))
    }

    /// Allow; the state reads authorized. The last of the three, so the VM ends authorized.
    @MainActor
    func testNP1_requestPermissionAllow() throws {
        let token = try notificationToken()
        let settings = try ncSettingsToken()
        let center = NotificationCenterUI(sample, token)
        try requireNotDetermined()
        XCTAssertEqual(try pressAndAnswer(.requestPermission, allow: true, token, settings, center: center),
                       ok("[requestPermission] granted"))
        XCTAssertEqual(try screen.run(.authorizationStatus), ok("[authorizationStatus] authorized"))
        XCTAssertEqual(try screen.run(.hasPermission), ok("[hasPermission] true"))
    }
}
