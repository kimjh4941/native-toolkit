//
//  MacQualificationProbeTests.swift
//  MacLibraryExampleUITests
//
//  U-30 `mac26`: the qualification probes of macOS 26, run in the 26 VM only (`--where vm26 --qualification
//  mac26`; D-21 revised 2026-11-28). One method per candidate; passing means the candidate holds, and only the
//  result (passed or failed) leaves the run. The steps that lead to a candidate are done as the test that presses it
//  does them (Q2 presses the root's `Options`, Q3 the share button), and the candidate itself (`Open`, Copy, the
//  `PasteButton`) is found and checked before the press but never pressed. A pass says the candidate's owner is the
//  allowed one, not how the press behaves. A target that passed is copied by hand, after its record is read, into the
//  runner's `MAC_VERIFIED_TARGETS`, which lets the tests deferred on 26 (`MAC_DEFERRED_TESTS`) run there (vm26 review
//  v1 C-1). `replyInBanner` is the separate
//  `mac26-reply` stage. The runner's `QUALIFICATION_ONLY_TESTS` keeps this class out of normal runs and baselines.
//

import XCTest
import Foundation

final class MacQualificationProbeTests: SampleUITestCase {

    private var sample: SampleApp?
    private var notification: (screen: NotificationScreen, token: NotificationToken)?

    override func setUpAfterGate() throws {}

    override func tearDownAfterGate() throws {
        if let notification {
            try NotificationCleanup.finish(notification.screen, notification.token)
        }
        notification = nil
        sample = nil
    }

    /// `windowOwnersReadableOn26`: the window list gives the owner and frame of the sample's window and of a window
    /// of another process, which the checks before every press read (design 5.0, U-31).
    @MainActor
    func testQ1_windowOwnersAreReadable() throws {
        let sample = try launchSample()
        self.sample = sample
        let windows = try OverlayCheck.readWindows()
        let own = windows.filter { $0.owner == SystemLabels.sampleBundleIdentifier && $0.bounds.width > 0 && $0.bounds.height > 0 }
        let others = windows.filter { $0.owner != nil && $0.owner != SystemLabels.sampleBundleIdentifier && $0.bounds.width > 0 }
        XCTAssertFalse(own.isEmpty, "no window of the sample with its owner and frame")
        XCTAssertFalse(others.isEmpty, "no window of another process with its owner and frame")
    }

    /// `notificationMenuItem`: the `Open` item of the menu the sample's root opens passes the check before the press.
    @MainActor
    func testQ2_notificationMenuItemPassesTheCheck() throws {
        let sample = try launchSample()
        self.sample = sample
        try sample.open(.notification)
        let screen = NotificationScreen(sample)
        let token = try notificationToken()
        notification = (screen, token)
        try NotificationCleanup.prepare(screen, token)
        let center = NotificationCenterUI(sample, token)
        XCTAssertEqual(try screen.run(.registerCategory), ResultLine.expected(success: true, SampleNotification.registeredText))
        XCTAssertEqual(try screen.run(.showImmediate, token, quiet: false), ResultLine.expected(success: true, "[showImmediate] success"))
        let root = try center.waitForRoot(.immediate, timeout: SampleApp.elementTimeout)
        try center.openOptions(root, sampleIs: .foreground)
        try center.checkMenuItemWithoutPressing(SampleNotification.openTitle, of: root, sampleIs: .foreground)
        try center.escapeMenu(of: root, anyItemTitle: SampleNotification.openTitle)
    }

    /// `mac26-reply` (`replyInBanner`): `Reply` of the sample's root is pressed (the VM has no private notification)
    /// and the windows and fields say whether the list opened (`ReplyStateRule`). Passes only for `banner`; `list` and
    /// `unknown` keep N24 and NC3 deferred (U-5, U-30).
    @MainActor
    func testR1_replyStaysInTheBanner() throws {
        let sample = try launchSample()
        self.sample = sample
        try sample.open(.notification)
        let screen = NotificationScreen(sample)
        let token = try notificationToken()
        notification = (screen, token)
        try NotificationCleanup.prepare(screen, token)
        let center = NotificationCenterUI(sample, token)
        XCTAssertEqual(try screen.run(.registerCategory), ResultLine.expected(success: true, SampleNotification.registeredText))
        XCTAssertEqual(try screen.run(.showImmediate, token, quiet: false), ResultLine.expected(success: true, "[showImmediate] success"))
        let root = try center.waitForRoot(.immediate, timeout: SampleApp.elementTimeout)
        try center.openOptions(root, sampleIs: .foreground)
        let state = try center.replyStateAfterChoosingReply(of: root, sampleIs: .foreground, margin: 8)
        XCTAssertEqual(state, .banner, "Reply: \(state)")
        if state == .banner {
            try center.escapeReply(of: root)
        }
    }

    /// `pickerCopy`: Copy of the share picker passes the check before the press.
    @MainActor
    func testQ3_pickerCopyPassesTheCheck() throws {
        let sample = try launchSample()
        self.sample = sample
        try sample.open(.share)
        let token = try sharePickerToken()
        let picker = SharePicker(sample, token)
        try sample.tap(.shareText, token)
        try picker.waitShown()
        try picker.checkCopyWithoutPressing()
        try picker.escape()
        try picker.waitGone()
    }

    /// `pasteButton`: the Clipboard screen's `PasteButton` passes the check before the press. The runner's text is
    /// written first, as CB1 does, so that the button is enabled when the screen is built.
    @MainActor
    func testQ4_pasteButtonPassesTheCheck() throws {
        let clipboard = try clipboardToken()
        _ = try RunnerPasteboard(clipboard).write("ntk-q4-\(Int(Date().timeIntervalSince1970))")
        let sample = try launchSample()
        self.sample = sample
        try sample.open(.clipboard)
        try sample.checkPasteButtonWithoutPressing(clipboard)
    }
}
