//
//  NotificationColdStartUITests.swift
//  IosLibraryExampleUITests
//
//  N30〜N33 of the UI test design (3.3): the sample is terminated before its notification fires,
//  and the banner (tap, Open, Reply, Delete) starts it again. The event must reach the receivers
//  set at launch (D-7) and is read on the Notification screen from the app-wide store (U-4).
//  Reply and Delete start the sample in the background; it stays alive until `activate`
//  (stage 0c, iOS 26.2 simulator).
//
//  Stage 1b C5 (Swift API design 13.2): N30〜N33 now reach the sample through the library's
//  `responses` hub (the expectations are unchanged; the route `path=hub` is checked as well). The
//  process the system starts from the banner gets no launch arguments and reads the test shape
//  the last launch wrote (SA-18, MS-14): N36 with the delayed listener (the hub keeps the launch
//  response), N37 reads `launchResponse()`, N45 runs N30 on the deprecated receivers.
//

import XCTest
import Foundation

final class NotificationColdStartUITests: SampleUITestCase {

    private var sample: SampleApp!

    private static let title = "5s Notification"
    private static let body = "Will be shown after 5 seconds"
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
    }

    @MainActor
    func testN30_bannerTapColdStart() throws {
        let springboard = try showAndTerminate(registerCategory: false)
        try springboard.tapBanner(title: Self.title, body: Self.body)
        XCTAssertTrue(try sample.waitForForeground(timeout: 15), "the sample did not start")
        try openNotificationFromMenu()
        try assertEvent(kind: "action", actionId: "com.apple.UNNotificationDefaultActionIdentifier", userText: "-")
    }

    @MainActor
    func testN31_openActionColdStart() throws {
        let springboard = try showAndTerminate(registerCategory: true)
        try springboard.expandBanner(title: Self.title, body: Self.body)
        try springboard.tapAction("Open", title: Self.title, body: Self.body)
        XCTAssertTrue(try sample.waitForForeground(timeout: 15), "the sample did not start")
        try openNotificationFromMenu()
        try assertEvent(kind: "action", actionId: "open", userText: "-")
        // H2-1: an action with the foreground option is the launch response on every OS.
        XCTAssertEqual(try route()["launch"], "true", "the Open action was not the launch response")
    }

    @MainActor
    func testN32_replyColdStart() throws {
        let springboard = try showAndTerminate(registerCategory: true)
        try springboard.expandBanner(title: Self.title, body: Self.body)
        try springboard.tapAction("Reply", title: Self.title, body: Self.body)
        try springboard.sendReply("cold reply", title: Self.title, body: Self.body)
        Thread.sleep(forTimeInterval: Self.backgroundActionSettle)
        try sample.activate()
        try openNotificationFromMenu()
        try assertEvent(kind: "textInput", actionId: "reply", userText: "cold reply")
        try assertBackgroundActionIsNotTheLaunchResponse("Reply")
    }

    @MainActor
    func testN33_deleteColdStart() throws {
        let springboard = try showAndTerminate(registerCategory: true)
        try springboard.expandBanner(title: Self.title, body: Self.body)
        try springboard.tapAction("Delete", title: Self.title, body: Self.body)
        Thread.sleep(forTimeInterval: Self.backgroundActionSettle)
        try sample.activate()
        try openNotificationFromMenu()
        try assertEvent(kind: "action", actionId: "delete", userText: "-")
        try assertBackgroundActionIsNotTheLaunchResponse("Delete")
    }

    // MARK: - Swift API (stage 1b C5)

    /// N36: the listener is added 5 seconds after launch (`delayListener`); the hub keeps the
    /// launch response and hands it to the listener inside `addListener`, once, as the launch
    /// response.
    @MainActor
    func testN36_aDelayedListenerReceivesTheKeptLaunchResponse() throws {
        sample = try launchSample(.delayListener)
        try sample.open(.notification)
        let springboard = try showAndTerminate(registerCategory: false)
        try springboard.tapBanner(title: Self.title, body: Self.body)
        XCTAssertTrue(try sample.waitForForeground(timeout: 15), "the sample did not start")
        try openNotificationFromMenu()
        try assertEvent(kind: "action", actionId: "com.apple.UNNotificationDefaultActionIdentifier", userText: "-",
                        path: "hub", mode: "delayListener")
        let fields = try route()
        XCTAssertEqual(fields["delivery"], "held", "the listener did not get the kept response inside addListener: \(fields)")
        XCTAssertEqual(fields["launch"], "true", "route: \(fields)")
        sample.observeQuietly(for: 2)
        XCTAssertEqual(try sample.lastEventLabel("sequence"), "sequence=1", "the response arrived twice")
    }

    /// N37: `launchResponse()` is `nil` after an ordinary launch, and the tapped notification after
    /// a cold start from its banner (also marked on the event).
    @MainActor
    func testN37_launchResponseIsTheTappedNotification() throws {
        XCTAssertEqual(try sample.press(.readLaunchResponse), success("[launchResponse] nil"))
        let springboard = try showAndTerminate(registerCategory: false)
        try springboard.tapBanner(title: Self.title, body: Self.body)
        XCTAssertTrue(try sample.waitForForeground(timeout: 15), "the sample did not start")
        try openNotificationFromMenu()
        try assertEvent(kind: "action", actionId: "com.apple.UNNotificationDefaultActionIdentifier", userText: "-")
        XCTAssertEqual(try route()["launch"], "true")
        XCTAssertEqual(try sample.press(.readLaunchResponse),
                       success("[launchResponse] notificationId=sample-notification, actionId=com.apple.UNNotificationDefaultActionIdentifier, isLaunchResponse=true"))
    }

    /// N45: N30 on the deprecated receivers. The process the system starts reads
    /// `legacyReceivers` from the file the test's launch wrote (SA-18; MS-14 records where it read
    /// the shape from).
    @MainActor
    func testN45_legacyReceiversColdStart() throws {
        sample = try launchSample(.legacyReceivers)
        try sample.open(.notification)
        let springboard = try showAndTerminate(registerCategory: false)
        try springboard.tapBanner(title: Self.title, body: Self.body)
        XCTAssertTrue(try sample.waitForForeground(timeout: 15), "the sample did not start")
        try openNotificationFromMenu()
        try assertEvent(kind: "action", actionId: "com.apple.UNNotificationDefaultActionIdentifier", userText: "-",
                        path: "legacy", mode: "legacyReceivers")
        let source = try route()["source"] ?? "-"
        XCTContext.runActivity(named: "MS-14: the process the system started read the test shape from \(source)") { _ in }
    }

    // MARK: - Helpers

    /// How long N32 and N33 wait after a background action before they bring the app forward. The
    /// state was read about 0.5 s before `didBecomeActive` without this wait, and N32 and N33
    /// failed with `launch=true` in two full runs (1b working notes, chapter 23.3).
    private static let backgroundActionSettle: TimeInterval = 3

    /// A background action (Reply, Delete) is not the launch response (H2-1). The library reads
    /// the application state in a main-queue block, so the value depends on whether that block
    /// runs before the app comes forward. N32 and N33 wait ``backgroundActionSettle`` before they
    /// bring it forward. On iOS 26 the block then runs while the app is still in the background,
    /// so `launch=false`. On iOS 18 the block can run after the test has brought the app to the
    /// foreground (MS-05), so the value is only recorded there (U-16).
    @MainActor
    private func assertBackgroundActionIsNotTheLaunchResponse(_ action: String) throws {
        let launch = try route()["launch"] ?? "-"
        if Self.osMajorVersion >= 26 {
            XCTAssertEqual(launch, "false", "the \(action) action was taken for the launch response")
        } else {
            XCTContext.runActivity(named: "MS-05: on iOS \(Self.osMajorVersion), the cold-start \(action) action has launch=\(launch)") { _ in }
        }
    }

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

    /// (RegisterCategory,) ShowTimeInterval(5s), terminate the sample and wait for the banner.
    @MainActor
    private func showAndTerminate(registerCategory: Bool) throws -> Springboard {
        let token = try systemUIToken()
        let springboard = Springboard(token)
        if registerCategory {
            XCTAssertEqual(try sample.press(.registerCategory), success(Self.registered))
        }
        XCTAssertEqual(try sample.press(.showTimeInterval, token), success("[showTimeInterval] error: nil"))
        try sample.terminate()
        XCTAssertTrue(try springboard.waitForBanner(title: Self.title, body: Self.body, timeout: 20))
        return springboard
    }

    /// A new process starts on the menu.
    @MainActor
    private func openNotificationFromMenu() throws {
        XCTAssertTrue(sample.menuCardExists(.notification), "the restarted sample is not on the menu")
        try sample.open(.notification)
    }

    /// The last event, and the route it came by in the shape `mode` (1b SA-18; the hub and the
    /// standard shape unless told).
    @MainActor
    private func assertEvent(kind: String, actionId: String, userText: String,
                             path: String = "hub", mode: String = "none") throws {
        try sample.waitForEventSequence(1)
        let expected = ["sequence=1", "kind=\(kind)", "notificationId=sample-notification", "actionId=\(actionId)", "userText=\(userText)"]
        XCTAssertEqual(try sample.lastEvent(), expected)
        let fields = try route()
        XCTAssertEqual(fields["path"], path, "route: \(fields)")
        XCTAssertEqual(fields["mode"], mode, "route: \(fields)")
    }
}
