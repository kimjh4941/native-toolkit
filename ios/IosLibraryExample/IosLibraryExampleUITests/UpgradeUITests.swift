//
//  UpgradeUITests.swift
//  IosLibraryExampleUITests
//
//  The upgrade test from the 1.13.0 sample (IosLibrary 1.3.0) to 2.0.0 (README chapter 7 and the
//  DoD; the upgrade test design `artifact/topics/ios-c-abi/designs/2026-11-21-ios-c-abi-upgrade-test-design.md`).
//  Three groups of two halves: the 1.x half (UA1, UB1, UC1) runs against the 1.x sample, the 2.0.0
//  half (UA2, UB2, UC2) against 2.0.0 installed over it. Only `scripts/test_ios_upgrade.sh` runs
//  them, one half per xcodebuild call, on the simulator; the runner never selects the class, and a
//  half the script did not ask for skips (`UpgradeStep`).
//
//  Neither half cleans the notifications up (`NotificationCleanup.inApp` would remove what 1.x
//  left), and the 2.0.0 half does not fix the permission: it must still be authorized (U-11, 3).
//  The interruption monitor presses nothing (the permission alert is pressed explicitly).
//

import XCTest
import Foundation

final class UpgradeUITests: SampleUITestCase {

    private static let scheduledId = "scheduled-notification"
    private static let deliveredId = "sample-notification"
    private static let locationTitle = "Scheduled Location"
    private static let locationBody = "You arrived at Tokyo Station"
    private static let timeIntervalTitle = "5s Notification"
    private static let timeIntervalBody = "Will be shown after 5 seconds"
    private static let actions = ["Open", "Delete", "Reply"]
    private static let registered = "[registerCategory] Registered. Send a notification and long-press to see the actions (Open, Delete, Reply)."
    private static let scheduled = "[scheduleLocation] Registered. Notification will fire when entering Tokyo Station (radius: 100m)."
    private static let defaultAction = "com.apple.UNNotificationDefaultActionIdentifier"

    // MARK: - Group A: the lists and removal

    /// UA1 (1.x): show one notification and schedule one by location.
    @MainActor
    func testUA1_legacySchedulesAndShows() throws {
        try UpgradeStep.ua1.require()
        let (legacy, token) = try openLegacyWithPermission()
        try legacy.tap(.showImmediate, token)
        try legacy.waitForResult(success("[showImmediate] error: nil"))
        // The interruption monitor presses nothing, so no tap may land on the banner (review K3-3).
        XCTAssertTrue(try Springboard(token).waitForBannerToVanish(title: "Immediate Notification", body: "Displayed now", timeout: 15),
                      "the 1.x banner did not go away")
        try legacy.tap(.scheduleLocation, token)
        try legacy.waitForResult(success(Self.scheduled))
        try waitForLegacyList(legacy, .getScheduled, "[getScheduled] count: 1, ids: [\(Self.scheduledId)]")
        try waitForLegacyList(legacy, .getDelivered, "[getDelivered] count: 1, ids: [\(Self.deliveredId)]")
    }

    /// UA2 (2.0.0): the permission, the scheduled and the delivered notification 1.x left are there,
    /// and are removed by their identifiers (S-P17).
    @MainActor
    func testUA2_upgradedListsAndCancels() throws {
        try UpgradeStep.ua2.require()
        let sample = try launchSample()
        try sample.open(.notification)
        XCTAssertEqual(try sample.press(.authorizationStatus), success("[authorizationStatus] authorized"))
        try requireLegacyScheduled(sample)
        try sample.waitForNotificationIDs(.getDelivered, [Self.deliveredId])
        try sample.press(.cancelScheduledById)
        try sample.waitForNotificationIDs(.getScheduled, [])
        try sample.press(.removeDeliveredById)
        try sample.waitForNotificationIDs(.getDelivered, [])
    }

    // MARK: - Group B: firing in the background and the tap

    /// UB1 (1.x): schedule one by location.
    @MainActor
    func testUB1_legacySchedulesALocationNotification() throws {
        try UpgradeStep.ub1.require()
        let (legacy, token) = try openLegacyWithPermission()
        try legacy.tap(.scheduleLocation, token)
        try legacy.waitForResult(success(Self.scheduled))
        try waitForLegacyList(legacy, .getScheduled, "[getScheduled] count: 1, ids: [\(Self.scheduledId)]")
    }

    /// UB2 (2.0.0): the 1.x notification fires while the sample is in the background (the system
    /// shows the banner); its tap reaches the library's listener (5.12.3: no previous delegate).
    @MainActor
    func testUB2_upgradedReceivesTheTapInTheBackground() throws {
        try UpgradeStep.ub2.require()
        let sample = try launchSample()
        try sample.open(.notification)
        let springboard = Springboard(try systemUIToken())
        let status = try sample.statusLine(.launchStatus)
        XCTAssertTrue(status.hasPrefix("install=installed,"), "launch status: \(status)")
        XCTAssertTrue(status.hasSuffix(", hostDelegate=off"), "launch status: \(status)")
        try requireLegacyScheduled(sample)
        XCTAssertEqual(try sample.lastEventLabel("sequence"), "sequence=0")
        try springboard.goHome()
        try UpgradeStep.ub2.signalReady()
        XCTAssertTrue(try springboard.waitForBanner(title: Self.locationTitle, body: Self.locationBody, timeout: 60),
                      "the 1.x notification did not fire after the location change")
        try springboard.tapBanner(title: Self.locationTitle, body: Self.locationBody)
        XCTAssertTrue(try sample.waitForForeground(timeout: 10), "the sample did not come to the foreground")
        try assertSingleEvent(sample, kind: "action", actionId: Self.defaultAction, userText: "-")
    }

    // MARK: - Group C: firing in the foreground and a text input action of the 1.x category

    /// UC1 (1.x): register the category and see its actions on a 1.x notification, then schedule
    /// one by location.
    @MainActor
    func testUC1_legacyRegistersTheCategoryAndSchedules() throws {
        try UpgradeStep.uc1.require()
        let (legacy, token) = try openLegacyWithPermission()
        let springboard = Springboard(token)
        try legacy.tap(.registerCategory)
        try legacy.waitForResult(success(Self.registered))
        try legacy.tap(.showTimeInterval, token)
        try legacy.waitForResult(success("[showTimeInterval] error: nil"))
        try springboard.goHome()
        XCTAssertTrue(try springboard.waitForBanner(title: Self.timeIntervalTitle, body: Self.timeIntervalBody, timeout: 20))
        try springboard.expandBanner(title: Self.timeIntervalTitle, body: Self.timeIntervalBody)
        try springboard.waitForActions(Self.actions, title: Self.timeIntervalTitle, body: Self.timeIntervalBody)
        try springboard.goHome()
        try legacy.activate()
        try legacy.tap(.scheduleLocation, token)
        try legacy.waitForResult(success(Self.scheduled))
        try waitForLegacyList(legacy, .getScheduled, "[getScheduled] count: 1, ids: [\(Self.scheduledId)]")
    }

    /// UC2 (2.0.0): the 1.x notification fires with the sample in the foreground (the library's
    /// `willPresent` shows it: no previous delegate), shows the 1.x category's actions, and a reply
    /// through the 1.x reply field reaches the library's listener.
    @MainActor
    func testUC2_upgradedRepliesThroughTheLegacyCategoryInTheForeground() throws {
        try UpgradeStep.uc2.require()
        let sample = try launchSample()
        try sample.open(.notification)
        let springboard = Springboard(try systemUIToken())
        try requireLegacyScheduled(sample)
        XCTAssertEqual(try sample.lastEventLabel("sequence"), "sequence=0")
        try UpgradeStep.uc2.signalReady()
        XCTAssertTrue(try springboard.waitForBanner(title: Self.locationTitle, body: Self.locationBody, timeout: 60),
                      "the 1.x notification was not shown in the foreground after the location change")
        // Shown by the library's willPresent: the sample was in the foreground, the same process (K3-1).
        XCTAssertTrue(sample.isForeground, "the sample was not in the foreground when the banner came")
        try springboard.expandBanner(title: Self.locationTitle, body: Self.locationBody)
        try springboard.waitForActions(Self.actions, title: Self.locationTitle, body: Self.locationBody)
        try springboard.tapAction("Reply", title: Self.locationTitle, body: Self.locationBody)
        try springboard.sendReply("upgraded", title: Self.locationTitle, body: Self.locationBody,
                                  placeholder: SystemLabels.legacySampleReplyPlaceholder)
        try sample.activate()
        try assertSingleEvent(sample, kind: "textInput", actionId: "reply", userText: "upgraded")
    }

    // MARK: - Helpers

    private func success(_ body: String) -> String {
        ResultLine.expected(success: true, body)
    }

    /// Launches the 1.x sample, checks that it is the 1.x one (no identifier of 2.0.0. U-4), opens
    /// its Notification screen and allows the permission alert (each group starts from a fresh
    /// install).
    @MainActor
    private func openLegacyWithPermission() throws -> (LegacySampleApp, SystemUIToken) {
        _ = try reinstallToken()
        let token = try systemUIToken()
        let legacy = LegacySampleApp(token)
        try legacy.launch()
        try legacy.openNotification()
        XCTAssertEqual(legacy.newSampleIdentifierCount, 0, "the app in the foreground is not the 1.x sample")
        let springboard = Springboard(token)
        try legacy.tap(.requestPermission, token)
        XCTAssertTrue(springboard.waitForAlert(), "the permission alert did not appear")
        try springboard.tapAlertButton(SystemLabels.allow)
        try legacy.waitForResult(success("[requestPermission] granted"))
        return (legacy, token)
    }

    /// Presses a 1.x list button every 0.5 s until its line is `body` (10 s at most): a notification
    /// just shown can be missing from the first reading.
    private func waitForLegacyList(_ legacy: LegacySampleApp, _ button: LegacyNotificationButton, _ body: String) throws {
        let expected = success(body)
        let deadline = Date().addingTimeInterval(10)
        while true {
            try legacy.tap(button)
            Thread.sleep(forTimeInterval: 0.5)
            let text = try legacy.resultText()
            if text == expected { return }
            guard Date() < deadline else {
                throw SampleUITestError("the 1.x line did not become '\(body)': '\(text)'")
            }
        }
    }

    /// The scheduled request 1.x left must be listed before anything else is done. When it is
    /// not, the cause (fired early, filtered, removed) is not decided here (C-6).
    @MainActor
    private func requireLegacyScheduled(_ sample: SampleApp) throws {
        do {
            try sample.waitForNotificationIDs(.getScheduled, [Self.scheduledId])
        } catch {
            throw SampleUITestError("the scheduled request 1.x left is not listed: \(error)")
        }
    }

    /// `path=…,launch=…,…` of the last event as fields.
    private func route(_ sample: SampleApp) throws -> [String: String] {
        var fields: [String: String] = [:]
        for part in try sample.lastEventRoute().split(separator: ",") {
            let pair = part.split(separator: "=", maxSplits: 1)
            if pair.count == 2 { fields[String(pair[0])] = String(pair[1]) }
        }
        return fields
    }

    /// Exactly one event, from the 1.x scheduled notification, through the library's listener, in
    /// the process that was running when the notification came (`launch=false`. K3-1).
    private func assertSingleEvent(_ sample: SampleApp, kind: String, actionId: String, userText: String) throws {
        try sample.waitForEventSequence(1)
        let expected = ["sequence=1", "kind=\(kind)", "notificationId=\(Self.scheduledId)", "actionId=\(actionId)",
                        "userText=\(userText)"]
        XCTAssertEqual(try sample.lastEvent(), expected)
        let fields = try route(sample)
        XCTAssertEqual(fields["path"], "hub", "route: \(fields)")
        XCTAssertEqual(fields["launch"], "false", "route: \(fields)")
        sample.observeQuietly(for: 2)
        XCTAssertEqual(try sample.lastEventLabel("sequence"), "sequence=1", "another event arrived")
    }
}
