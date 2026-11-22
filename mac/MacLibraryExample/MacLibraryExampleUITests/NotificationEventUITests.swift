//
//  NotificationEventUITests.swift
//  MacLibraryExampleUITests
//
//  N20〜N24 of the UI test design (5.3): the category and the events the sample receives from its
//  banner. Only the sample's banner root is operated: its body, its `Options` and the items of the
//  menu that `Options` opened, and the reply field inside it (U-2, U-5). The event is read from
//  `notification.lastEvent` (U-4) and must not be followed by another one for 2 seconds.
//

import XCTest
import Foundation

final class NotificationEventUITests: SampleUITestCase {

    private var sample: SampleApp!
    private var screen: NotificationScreen!
    private var token: NotificationToken?
    /// N20 removes the category; it is registered again at the end even when the test fails.
    private var categoryRemoved = false

    private static let tenSecondBanner: TimeInterval = 25
    /// The banner hides itself after about 5 seconds.
    private static let bannerGone: TimeInterval = 15

    override func setUpAfterGate() throws {
        sample = try launchSample()
        try sample.open(.notification)
        screen = NotificationScreen(sample)
        let token = try notificationToken()
        self.token = token
        try NotificationCleanup.prepare(screen, token)
    }

    override func tearDownAfterGate() throws {
        if let token, let screen {
            if categoryRemoved, sample.state != .notRunning {
                try sample.activate()
                try screen.run(.registerCategory)
            }
            try NotificationCleanup.finish(screen, token)
        }
        sample = nil
        screen = nil
        token = nil
    }

    private func requireToken() throws -> NotificationToken {
        guard let token else {
            throw SampleUITestError(.gate, "the test holds no notification token")
        }
        return token
    }

    private func ok(_ body: String) -> String {
        ResultLine.expected(success: true, body)
    }

    // MARK: - Category

    /// Without the category the root shows no `Options`; with it, `Options` opens a menu with
    /// `Open` and `Reply` once each. The category is registered again at the end.
    @MainActor
    func testN20_categoryAddsOptions() throws {
        let token = try requireToken()
        let center = NotificationCenterUI(sample, token)

        XCTAssertEqual(try screen.run(.removeCategory), ok("[removeCategory] success"))
        categoryRemoved = true
        XCTAssertEqual(try screen.run(.showTimeInterval, token), ok("[showTimeInterval] success"))
        var pressed = try screen.lastClickTime()
        let first = try center.waitForRoot(.tenSeconds,
                                           timeout: NotificationScreen.timeLeft(since: pressed, total: Self.tenSecondBanner))
        try center.expectNoOptions(first, for: 2, sampleIs: .foreground)
        try sample.activate()
        try sample.hoverOnResult(.notification)
        try center.waitRootGone(first, timeout: Self.bannerGone)
        XCTAssertEqual(try screen.run(.removeAllDelivered), ok("[removeAllDelivered] called"))
        XCTAssertEqual(try screen.run(.registerCategory), ok(SampleNotification.registeredText))
        categoryRemoved = false

        XCTAssertEqual(try screen.run(.showTimeInterval, token), ok("[showTimeInterval] success"))
        pressed = try screen.lastClickTime()
        let second = try center.waitForRoot(.tenSeconds,
                                            timeout: NotificationScreen.timeLeft(since: pressed, total: Self.tenSecondBanner))
        try center.openOptions(second, sampleIs: .foreground)
        XCTAssertEqual(try center.menuItemCount(SampleNotification.openTitle), 1)
        XCTAssertEqual(try center.menuItemCount(SampleNotification.replyTitle), 1)
        try center.escapeMenu(of: second, anyItemTitle: SampleNotification.openTitle)
        try sample.activate()
        XCTAssertEqual(try screen.run(.registerCategory), ok(SampleNotification.registeredText))
        XCTAssertEqual(try sample.lastEvent().sequence, 0, "an event arrived")
    }

    // MARK: - Body

    @MainActor
    func testN21_bodyClickInTheBackground() throws {
        let token = try requireToken()
        let center = NotificationCenterUI(sample, token)
        let before = try showImmediate(token)
        try FinderFront(token).bringToFront(behind: sample)
        let root = try center.waitForRoot(.immediate, timeout: SampleApp.elementTimeout)
        try center.clickBody(root, sampleIs: .background)
        try sample.waitForState(.runningForeground, timeout: SampleApp.elementTimeout, step: .notificationState)
        try assertEvent(kind: "action", actionId: ExpectedEvent.defaultAction, userText: "-", resultBefore: before)
    }

    @MainActor
    func testN22_bodyClickInTheForeground() throws {
        let token = try requireToken()
        let center = NotificationCenterUI(sample, token)
        let before = try showImmediate(token)
        let root = try center.waitForRoot(.immediate, timeout: SampleApp.elementTimeout)
        try center.clickBody(root, sampleIs: .foreground)
        try assertEvent(kind: "action", actionId: ExpectedEvent.defaultAction, userText: "-", resultBefore: before)
    }

    // MARK: - Actions

    @MainActor
    func testN23_openAction() throws {
        let token = try requireToken()
        let center = NotificationCenterUI(sample, token)
        XCTAssertEqual(try screen.run(.registerCategory), ok(SampleNotification.registeredText))
        let before = try showImmediate(token)
        try FinderFront(token).bringToFront(behind: sample)
        let root = try center.waitForRoot(.immediate, timeout: SampleApp.elementTimeout)
        try center.openOptions(root, sampleIs: .background)
        try center.choose(SampleNotification.openTitle, of: root, sampleIs: .background)
        try sample.waitForState(.runningForeground, timeout: SampleApp.elementTimeout, step: .notificationState)
        try assertEvent(kind: "action", actionId: SampleNotification.openAction, userText: "-", resultBefore: before)
    }

    /// After Return the sample stays behind (stage 0a 5.1); it is activated only after the event.
    @MainActor
    func testN24_replyAction() throws {
        let token = try requireToken()
        let center = NotificationCenterUI(sample, token)
        XCTAssertEqual(try screen.run(.registerCategory), ok(SampleNotification.registeredText))
        let before = try showImmediate(token)
        try FinderFront(token).bringToFront(behind: sample)
        let root = try center.waitForRoot(.immediate, timeout: SampleApp.elementTimeout)
        try center.openOptions(root, sampleIs: .background)
        try center.choose(SampleNotification.replyTitle, of: root, sampleIs: .background)
        try center.reply("hello reply", in: root)
        try screen.waitForEvent(expected(kind: "textInput", actionId: SampleNotification.replyAction,
                                         userText: "hello reply"))
        XCTAssertEqual(sample.state, .runningBackground, "the sample came to the front after the reply")
        try sample.activate()
        try assertEvent(kind: "textInput", actionId: SampleNotification.replyAction, userText: "hello reply",
                        resultBefore: before)
    }

    // MARK: - Helpers

    /// Presses ShowImmediate and returns the result number before it. The 2-second check for an
    /// extra completion is made at the end, after the event (`assertEvent`), so that the banner is
    /// still shown when the test reaches it.
    private func showImmediate(_ token: NotificationToken) throws -> Int {
        let before = try sample.resultSequence(.notification)
        XCTAssertEqual(try screen.run(.showImmediate, token, quiet: false), ok("[showImmediate] success"))
        return before
    }

    private func expected(kind: String, actionId: String, userText: String) -> ExpectedEvent {
        ExpectedEvent(sequence: 1, kind: kind, notificationId: .immediate, actionId: actionId, userText: userText)
    }

    /// The last event is the expected one and stays the only one for 2 seconds; the result line holds
    /// ShowImmediate's result and then the event's line (the screen shows each event), with nothing
    /// after it for 2 seconds.
    private func assertEvent(kind: String, actionId: String, userText: String, resultBefore: Int) throws {
        try screen.waitForEvent(expected(kind: kind, actionId: actionId, userText: userText))
        let eventLine = kind == "textInput" ? "[textActionReceived] " : "[actionReceived] "
        try sample.waitForNextResult(.notification, after: resultBefore + 1, marker: eventLine)
        try screen.expectNoFurtherEvent(sequence: 1)
        try sample.expectNoFurtherResult(.notification, sequence: resultBefore + 2)
    }
}
