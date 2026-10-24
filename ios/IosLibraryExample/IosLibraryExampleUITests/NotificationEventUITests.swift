//
//  NotificationEventUITests.swift
//  IosLibraryExampleUITests
//
//  N23〜N29 of the UI test design (3.3): the category's actions and the events the sample
//  receives (the last event of design 5.2). Banners only (U-5): tap, a 1.5-second long press and
//  the expanded notification's actions and reply. The category is registered and removed by the
//  library in separate tasks, so every change is observed through a 5-second notification before
//  the next step (N23, N24). Every test leaves the category registered (U-15).
//
//  The last event shows `userText=-` for an action without text (the sample prints `-` for nil;
//  design 3.3 wrote `userText=nil`).
//

import XCTest
import Foundation

final class NotificationEventUITests: SampleUITestCase {

    private var sample: SampleApp!

    private static let title = "5s Notification"
    private static let body = "Will be shown after 5 seconds"
    private static let actions = ["Open", "Delete", "Reply"]
    private static let registered = "[registerCategory] Registered. Send a notification and long-press to see the actions (Open, Delete, Reply)."

    override func setUpAfterGate() throws {
        sample = try launchSample()
        try sample.open(.notification)
        try NotificationPrecondition.requireAuthorized(sample, in: self)
        try NotificationCleanup.inApp(sample)
    }

    override func tearDownAfterGate() throws {
        defer { sample = nil }
        try NotificationCleanup.inApp(sample)
        XCTAssertEqual(try sample.press(.registerCategory), success(Self.registered))
    }

    // MARK: - Category

    /// The category is first removed and observed absent, then registered and observed present:
    /// the difference shows the effect of registering (a category left in the OS alone would pass
    /// a check of "present").
    @MainActor
    func testN23_registerCategoryAddsActions() throws {
        let springboard = Springboard(try systemUIToken())
        XCTAssertEqual(try sample.press(.removeCategory), success("[removeCategory] id: sample-category"))
        try assertActions(present: false, springboard)

        XCTAssertEqual(try sample.press(.registerCategory), success(Self.registered))
        try assertActions(present: true, springboard)
    }

    /// Removed (absent) -> registered (present) -> removed again (absent), then registered.
    @MainActor
    func testN24_removeCategoryRemovesActions() throws {
        let springboard = Springboard(try systemUIToken())
        XCTAssertEqual(try sample.press(.removeCategory), success("[removeCategory] id: sample-category"))
        try assertActions(present: false, springboard)

        XCTAssertEqual(try sample.press(.registerCategory), success(Self.registered))
        try assertActions(present: true, springboard)

        XCTAssertEqual(try sample.press(.removeCategory), success("[removeCategory] id: sample-category"))
        try assertActions(present: false, springboard)

        XCTAssertEqual(try sample.press(.registerCategory), success(Self.registered))
    }

    // MARK: - Events

    /// Tapping the banner on the home screen opens the sample; exactly one default action.
    @MainActor
    func testN25_bannerTapReportsDefaultAction() throws {
        let token = try systemUIToken()
        let springboard = Springboard(token)
        XCTAssertEqual(try sample.press(.showTimeInterval, token), success("[showTimeInterval] error: nil"))
        try springboard.goHome()
        XCTAssertTrue(try springboard.waitForBanner(title: Self.title, body: Self.body, timeout: 20))
        try springboard.tapBanner(title: Self.title, body: Self.body)
        XCTAssertTrue(try sample.waitForForeground(timeout: 10), "the sample did not come to the foreground")
        XCTAssertTrue(sample.isShowing(.notification), "the sample is not on the Notification screen")
        try assertSingleEvent(kind: "action", actionId: "com.apple.UNNotificationDefaultActionIdentifier", userText: "-")
    }

    /// Tapping the foreground banner delivers the same event (stage 0c).
    @MainActor
    func testN26_foregroundBannerTapReportsDefaultAction() throws {
        let token = try systemUIToken()
        let springboard = Springboard(token)
        XCTAssertEqual(try sample.press(.showImmediate, token), success("[showImmediate] error: nil"))
        XCTAssertTrue(try springboard.waitForBanner(title: "Immediate Notification", body: "Displayed now", timeout: 10))
        try springboard.tapBanner(title: "Immediate Notification", body: "Displayed now")
        try assertSingleEvent(kind: "action", actionId: "com.apple.UNNotificationDefaultActionIdentifier", userText: "-")
    }

    @MainActor
    func testN27_openActionBringsTheSample() throws {
        let springboard = try showAndExpand()
        try springboard.tapAction("Open", title: Self.title, body: Self.body)
        XCTAssertTrue(try sample.waitForForeground(timeout: 10), "the sample did not come to the foreground")
        try assertSingleEvent(kind: "action", actionId: "open", userText: "-")
    }

    /// Delete is destructive without `.foreground`: the sample stays in the background for
    /// 2 seconds (U-14); after activating it the event is there.
    @MainActor
    func testN28_deleteActionStaysInBackground() throws {
        let springboard = try showAndExpand()
        try springboard.tapAction("Delete", title: Self.title, body: Self.body)
        sample.observeQuietly(for: 2)
        XCTAssertNotEqual(sample.state, .runningForeground, "the sample came to the foreground after Delete")
        try sample.activate()
        try assertSingleEvent(kind: "action", actionId: "delete", userText: "-")
    }

    @MainActor
    func testN29_replyReportsText() throws {
        let springboard = try showAndExpand()
        try springboard.tapAction("Reply", title: Self.title, body: Self.body)
        try springboard.sendReply("hello reply", title: Self.title, body: Self.body)
        try sample.activate()
        try assertSingleEvent(kind: "textInput", actionId: "reply", userText: "hello reply")
    }

    // MARK: - Helpers

    private func success(_ body: String) -> String {
        ResultLine.expected(success: true, body)
    }

    /// RegisterCategory, ShowTimeInterval(5s), home, then long-press the banner until it expands.
    @MainActor
    private func showAndExpand() throws -> Springboard {
        let token = try systemUIToken()
        let springboard = Springboard(token)
        XCTAssertEqual(try sample.press(.registerCategory), success(Self.registered))
        XCTAssertEqual(try sample.press(.showTimeInterval, token), success("[showTimeInterval] error: nil"))
        try springboard.goHome()
        XCTAssertTrue(try springboard.waitForBanner(title: Self.title, body: Self.body, timeout: 20))
        try springboard.expandBanner(title: Self.title, body: Self.body)
        return springboard
    }

    /// ShowTimeInterval(5s), home, expand the banner, and observe the actions: present within
    /// 5 s, or absent 3 s after the expanded view appeared (U-14). Then back to the sample.
    @MainActor
    private func assertActions(present: Bool, _ springboard: Springboard) throws {
        let token = try systemUIToken()
        XCTAssertEqual(try sample.press(.showTimeInterval, token), success("[showTimeInterval] error: nil"))
        try springboard.goHome()
        XCTAssertTrue(try springboard.waitForBanner(title: Self.title, body: Self.body, timeout: 20))
        try springboard.expandBanner(title: Self.title, body: Self.body)
        if present {
            try springboard.waitForActions(Self.actions, title: Self.title, body: Self.body)
        } else {
            sample.observeQuietly(for: 3)
            XCTAssertTrue(springboard.isExpanded, "the expanded notification closed while observing")
            XCTAssertEqual(try springboard.actionCount(Self.actions, title: Self.title, body: Self.body), 0, "actions shown without the category")
        }
        try springboard.goHome()
        try sample.activate()
        try NotificationCleanup.inApp(sample)
    }

    /// The last event is the only one (sequence 1), also 2 seconds later (U-14).
    @MainActor
    private func assertSingleEvent(kind: String, actionId: String, userText: String) throws {
        try sample.waitForEventSequence(1)
        let expected = ["sequence=1", "kind=\(kind)", "notificationId=sample-notification", "actionId=\(actionId)", "userText=\(userText)"]
        XCTAssertEqual(try sample.lastEvent(), expected)
        sample.observeQuietly(for: 2)
        XCTAssertEqual(try sample.lastEventLabel("sequence"), "sequence=1", "another event arrived")
    }
}
