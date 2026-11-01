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
//  Stage 1b C5 (Swift API design 13.2): N25〜N29 now reach the sample through the library's
//  `responses` hub (the expectations are unchanged; the route `path=hub` is checked as well),
//  N35 adds a second listener, N41 launches with a host delegate before the library's, and N43 /
//  N44 run N25 / N29 on the deprecated receivers (`path=legacy`).
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

    // MARK: - Swift API (stage 1b C5)

    /// N35: with a second listener both listeners receive the tap once; after it is removed only
    /// the first receives the next one.
    @MainActor
    func testN35_twoListenersReceiveOnceEach() throws {
        let token = try systemUIToken()
        let springboard = Springboard(token)
        XCTAssertEqual(try sample.press(.addSecondListener), success("[addSecondListener] added"))
        XCTAssertEqual(try sample.press(.showTimeInterval, token), success("[showTimeInterval] error: nil"))
        try springboard.goHome()
        XCTAssertTrue(try springboard.waitForBanner(title: Self.title, body: Self.body, timeout: 20))
        try springboard.tapBanner(title: Self.title, body: Self.body)
        XCTAssertTrue(try sample.waitForForeground(timeout: 10), "the sample did not come to the foreground")
        try assertSingleEvent(kind: "action", actionId: "com.apple.UNNotificationDefaultActionIdentifier", userText: "-")
        XCTAssertEqual(try sample.statusLine(.listenerCounts), "first=1, second=1, secondListener=added")

        XCTAssertEqual(try sample.press(.removeSecondListener), success("[removeSecondListener] removed"))
        XCTAssertEqual(try sample.press(.showImmediate, token), success("[showImmediate] error: nil"))
        XCTAssertTrue(try springboard.waitForBanner(title: "Immediate Notification", body: "Displayed now", timeout: 10))
        try springboard.tapBanner(title: "Immediate Notification", body: "Displayed now")
        try sample.waitForEventSequence(2)
        try sample.waitForStatusLine(.listenerCounts, "first=2, second=1, secondListener=removed")
        sample.observeQuietly(for: 2)
        XCTAssertEqual(try sample.statusLine(.listenerCounts), "first=2, second=1, secondListener=removed", "another event arrived")
    }

    /// N41: launched with a host delegate set before the library's. The host's notification goes
    /// to the host delegate only (willPresent and didReceive), the library's to the library's
    /// listener only.
    @MainActor
    func testN41_eachNotificationGoesToItsOwnDelegate() throws {
        let token = try systemUIToken()
        let springboard = Springboard(token)
        sample = try launchSample(.hostDelegate)
        try sample.open(.notification)
        XCTAssertEqual(try sample.statusLine(.launchStatus), "install=installed, isDelegateInstalled=true, mode=none, source=arguments, hostDelegate=on")

        XCTAssertEqual(try sample.press(.showHostNotification, token), success("[showHostNotification] error: nil"))
        XCTAssertTrue(try springboard.waitForBanner(title: "Host Notification", body: "Posted without the library", timeout: 10))
        try springboard.tapBanner(title: "Host Notification", body: "Posted without the library")
        try sample.waitForStatusLine(.hostEvent,
                                     "hostWillPresent=1, hostDidReceive=1, notificationId=sample-host-notification, actionId=com.apple.UNNotificationDefaultActionIdentifier")
        sample.observeQuietly(for: 2)
        XCTAssertEqual(try sample.lastEventLabel("sequence"), "sequence=0", "the host's notification reached the library's listener")

        XCTAssertEqual(try sample.press(.showImmediate, token), success("[showImmediate] error: nil"))
        XCTAssertTrue(try springboard.waitForBanner(title: "Immediate Notification", body: "Displayed now", timeout: 10))
        try springboard.tapBanner(title: "Immediate Notification", body: "Displayed now")
        try assertSingleEvent(kind: "action", actionId: "com.apple.UNNotificationDefaultActionIdentifier", userText: "-")
        XCTAssertEqual(try sample.statusLine(.hostEvent),
                       "hostWillPresent=1, hostDidReceive=1, notificationId=sample-host-notification, actionId=com.apple.UNNotificationDefaultActionIdentifier",
                       "the library's notification reached the host delegate")
    }

    /// N43: N25 on the deprecated receivers (`legacyReceivers`).
    @MainActor
    func testN43_legacyReceiversReportABannerTap() throws {
        let token = try systemUIToken()
        let springboard = Springboard(token)
        sample = try launchSample(.legacyReceivers)
        try sample.open(.notification)
        XCTAssertEqual(try sample.press(.showTimeInterval, token), success("[showTimeInterval] error: nil"))
        try springboard.goHome()
        XCTAssertTrue(try springboard.waitForBanner(title: Self.title, body: Self.body, timeout: 20))
        try springboard.tapBanner(title: Self.title, body: Self.body)
        XCTAssertTrue(try sample.waitForForeground(timeout: 10), "the sample did not come to the foreground")
        XCTAssertTrue(sample.isShowing(.notification), "the sample is not on the Notification screen")
        try assertSingleEvent(kind: "action", actionId: "com.apple.UNNotificationDefaultActionIdentifier", userText: "-",
                              path: "legacy", mode: "legacyReceivers")
    }

    /// N44: N29 on the deprecated receivers (`legacyReceivers`).
    @MainActor
    func testN44_legacyReceiversReportAReply() throws {
        sample = try launchSample(.legacyReceivers)
        try sample.open(.notification)
        let springboard = try showAndExpand()
        try springboard.tapAction("Reply", title: Self.title, body: Self.body)
        try springboard.sendReply("hello reply", title: Self.title, body: Self.body)
        try sample.activate()
        try assertSingleEvent(kind: "textInput", actionId: "reply", userText: "hello reply", path: "legacy", mode: "legacyReceivers")
    }

    // MARK: - Helpers

    private func success(_ body: String) -> String {
        ResultLine.expected(success: true, body)
    }

    /// `path=…,launch=…,delivery=…,mode=…,source=…` of the last event (1b SA-18) as fields.
    private func route() throws -> [String: String] {
        var fields: [String: String] = [:]
        for part in try sample.lastEventRoute().split(separator: ",") {
            let pair = part.split(separator: "=", maxSplits: 1)
            if pair.count == 2 { fields[String(pair[0])] = String(pair[1]) }
        }
        return fields
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

    /// The last event is the only one (sequence 1), also 2 seconds later (U-14), and came by
    /// `path` in the shape `mode` (1b SA-18; the hub and the standard shape unless told). Every
    /// event here arrives after the sample has been active, so none is the launch response (P1-22).
    @MainActor
    private func assertSingleEvent(kind: String, actionId: String, userText: String,
                                   path: String = "hub", mode: String = "none") throws {
        try sample.waitForEventSequence(1)
        let expected = ["sequence=1", "kind=\(kind)", "notificationId=sample-notification", "actionId=\(actionId)", "userText=\(userText)"]
        XCTAssertEqual(try sample.lastEvent(), expected)
        let fields = try route()
        XCTAssertEqual(fields["path"], path, "route: \(fields)")
        XCTAssertEqual(fields["mode"], mode, "route: \(fields)")
        XCTAssertEqual(fields["launch"], "false", "route: \(fields)")
        sample.observeQuietly(for: 2)
        XCTAssertEqual(try sample.lastEventLabel("sequence"), "sequence=1", "another event arrived")
    }
}
