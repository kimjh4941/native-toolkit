//
//  NotificationUITests.swift
//  IosLibraryExampleUITests
//
//  N1〜N22 and N34 of the UI test design (3.3): permission state, showing, updating, cancelling,
//  removing, scheduling, queries and the badge. Lists are read with GetScheduled / GetDelivered and
//  compared as count, number of ids, no duplicates and the set of ids, polled every 0.5 s for up to
//  10 s (U-6). Banners are read only through `Springboard` (U-5).
//

import XCTest
import Foundation

final class NotificationUITests: SampleUITestCase {

    private var sample: SampleApp!
    private var badgeTouched = false

    private static let sampleId = "sample-notification"
    private static let scheduledId = "scheduled-notification"

    override func setUpAfterGate() throws {
        sample = try launchSample()
        try sample.open(.notification)
        try NotificationPrecondition.requireAuthorized(sample, in: self)
        try NotificationCleanup.inApp(sample)
    }

    override func tearDownAfterGate() throws {
        defer { sample = nil }
        try NotificationCleanup.inApp(sample)
        if badgeTouched {
            XCTAssertEqual(try sample.press(.setBadgeCount0), success("[setBadgeCount] 0, error: nil"))
        }
    }

    // MARK: - Permission state and settings

    @MainActor
    func testN1_permissionStateIsAuthorized() throws {
        XCTAssertEqual(try sample.press(.hasPermission), success("[hasPermission] true"))
        XCTAssertEqual(try sample.press(.authorizationStatus), success("[authorizationStatus] authorized"))
    }

    /// Requesting an already granted permission shows no alert for 5 seconds (U-14).
    @MainActor
    func testN2_requestPermissionWhenGrantedShowsNoAlert() throws {
        let token = try systemUIToken()
        let springboard = Springboard(token)
        let before = try sample.updateCount(.notification)
        try sample.tap(.requestPermission, token)
        XCTAssertFalse(springboard.waitForAlert(timeout: 5), "a permission alert appeared")
        try sample.waitForUpdateCount(.notification, before + 1)
        XCTAssertEqual(try sample.resultText(.notification), success("[requestPermission] granted"))
        XCTAssertEqual(sample.remainingAlertCount, 0)
    }

    /// The Settings app comes to the foreground. Nothing inside Settings is read or pressed.
    @MainActor
    func testN3_openNotificationSettingsShowsSettings() throws {
        let springboard = Springboard(try systemUIToken())
        XCTAssertFalse(springboard.isSettingsForeground, "Settings is already in the foreground")
        XCTAssertEqual(try sample.press(.openNotificationSettings, try systemUIToken()), success("[openNotificationSettings] called"))
        XCTAssertTrue(springboard.waitForSettingsForeground(timeout: 10), "Settings did not come to the foreground")
        try sample.activate()
        XCTAssertEqual(try sample.resultText(.notification), success("[openNotificationSettings] called"))
    }

    // MARK: - Show

    @MainActor
    func testN4_showImmediateShowsForegroundBanner() throws {
        let token = try systemUIToken()
        let springboard = Springboard(token)
        XCTAssertEqual(try sample.press(.showImmediate, token), success("[showImmediate] error: nil"))
        XCTAssertTrue(try springboard.waitForBanner(title: "Immediate Notification", body: "Displayed now", timeout: 10))
        XCTAssertEqual(
            try sample.waitForNotificationIDs(.getDelivered, [Self.sampleId]),
            success("[getDelivered] count: 1, ids: [sample-notification]")
        )
    }

    /// The same bundled attachment can be used twice (stage 0c: it is not moved away by the
    /// first notification). The image itself is HC1.
    @MainActor
    func testN5_attachmentCanBeShownTwice() throws {
        let token = try systemUIToken()
        let springboard = Springboard(token)
        let title = "Immediate Notification with Attachment"
        let body = "Displayed with app icon attachment"
        XCTAssertEqual(try sample.press(.showImmediateWithAttachment, token), success("[showImmediateWithAttachment] error: nil"))
        let first = try springboard.waitForBannerNotingSampleNotifications(title: title, body: body, timeout: 10)
        XCTAssertTrue(first.found, first.note)
        XCTAssertEqual(try sample.press(.removeAllDelivered), success("[removeAllDelivered] called"))
        try sample.waitForNotificationIDs(.getDelivered, [])
        XCTAssertTrue(try springboard.waitForBannerToVanish(title: title, body: body, timeout: 15), "the first banner stayed")

        XCTAssertEqual(try sample.press(.showImmediateWithAttachment, token), success("[showImmediateWithAttachment] error: nil"))
        let second = try springboard.waitForBannerNotingSampleNotifications(title: title, body: body, timeout: 10)
        XCTAssertTrue(second.found, second.note)
        try sample.waitForNotificationIDs(.getDelivered, [Self.sampleId])
    }

    /// The 5-second notification fires while the sample is not in the foreground. Reading
    /// GetScheduled before it fires is N7's job: the sample's layout puts GetScheduled too far
    /// below ShowTimeInterval(5s) to reach it in 5 seconds.
    @MainActor
    func testN6_timeIntervalFiresInBackground() throws {
        let token = try systemUIToken()
        let springboard = Springboard(token)
        XCTAssertEqual(try sample.press(.showTimeInterval, token), success("[showTimeInterval] error: nil"))
        try springboard.goHome()
        XCTAssertTrue(try springboard.waitForBanner(title: "5s Notification", body: "Will be shown after 5 seconds", timeout: 20))
        XCTAssertNotEqual(sample.state, .runningForeground, "the sample came to the foreground")
        try sample.activate()
        try sample.waitForNotificationIDs(.getScheduled, [])
        try sample.waitForNotificationIDs(.getDelivered, [Self.sampleId])
    }

    /// ShowCalendar(+1m): scheduled, then the foreground banner within 90 s (stage 0c: 73 s).
    @MainActor
    func testN7_calendarFiresWithinNinetySeconds() throws {
        let token = try systemUIToken()
        let springboard = Springboard(token)
        XCTAssertEqual(try sample.press(.showCalendar, token), success("[showCalendar] error: nil"))
        let pressed = Date()
        XCTAssertEqual(
            try sample.waitForNotificationIDs(.getScheduled, [Self.sampleId]),
            success("[getScheduled] count: 1, ids: [sample-notification]")
        )
        let remaining = 90 - Date().timeIntervalSince(pressed)
        XCTAssertTrue(
            try springboard.waitForBanner(title: "Calendar Notification", body: "Will be shown in one minute", timeout: remaining),
            "the calendar notification did not fire within 90 s"
        )
    }

    /// The location trigger is registered (the simulator without location permission accepts it.
    /// Stage 0c). Firing is not checked.
    @MainActor
    func testN8_showLocationRegisters() throws {
        let token = try systemUIToken()
        XCTAssertEqual(
            try sample.press(.showLocation, token),
            success("[showLocation] Registered. Notification will fire when entering Tokyo Station (radius: 100m).")
        )
        try sample.waitForNotificationIDs(.getScheduled, [Self.sampleId])
    }

    // MARK: - Update, cancel, remove

    /// UpdateById right after ShowTimeInterval(5s) replaces the pending request: the updated
    /// banner shows at once, and no 5s banner until the trigger time + 5 s (U-14).
    @MainActor
    func testN9_updatePendingReplacesIt() throws {
        let token = try systemUIToken()
        let springboard = Springboard(token)
        XCTAssertEqual(try sample.press(.showTimeInterval, token), success("[showTimeInterval] error: nil"))
        let shown = Date()
        XCTAssertEqual(try sample.press(.updateById, token), success("[update] id: sample-notification, error: nil"))
        XCTAssertTrue(try springboard.waitForBanner(title: "Updated Notification", body: "This content was updated", timeout: 10))
        XCTAssertFalse(
            try springboard.waitForBanner(title: "5s Notification", body: "Will be shown after 5 seconds", timeout: remaining(until: shown, plus: 10)),
            "the replaced 5s notification fired"
        )
        XCTAssertEqual(try sample.waitForNotificationIDs(.getScheduled, []), success("[getScheduled] count: 0, ids: []"))
        XCTAssertEqual(
            try sample.waitForNotificationIDs(.getDelivered, [Self.sampleId]),
            success("[getDelivered] count: 1, ids: [sample-notification]")
        )
    }

    /// Updating a delivered notification with the same id replaces it: still one (stage 0c).
    @MainActor
    func testN10_updateDeliveredKeepsOne() throws {
        let token = try systemUIToken()
        let springboard = Springboard(token)
        XCTAssertEqual(try sample.press(.showImmediate, token), success("[showImmediate] error: nil"))
        XCTAssertTrue(try springboard.waitForBanner(title: "Immediate Notification", body: "Displayed now", timeout: 10))
        XCTAssertEqual(try sample.press(.updateById, token), success("[update] id: sample-notification, error: nil"))
        XCTAssertTrue(try springboard.waitForBanner(title: "Updated Notification", body: "This content was updated", timeout: 10))
        XCTAssertEqual(
            try sample.waitForNotificationIDs(.getDelivered, [Self.sampleId]),
            success("[getDelivered] count: 1, ids: [sample-notification]")
        )
    }

    @MainActor
    func testN11_cancelByIdRemovesPending() throws {
        let token = try systemUIToken()
        let springboard = Springboard(token)
        XCTAssertEqual(try sample.press(.showTimeInterval, token), success("[showTimeInterval] error: nil"))
        let shown = Date()
        XCTAssertEqual(try sample.press(.cancelById), success("[cancel] id: sample-notification"))
        // Read before the trigger time: after it, a request that was not cancelled has fired and
        // the list is empty anyway.
        XCTAssertEqual(
            try sample.waitForNotificationIDs(.getScheduled, [], timeout: remaining(until: shown, plus: 4.5)),
            success("[getScheduled] count: 0, ids: []")
        )
        XCTAssertFalse(
            try springboard.waitForBanner(title: "5s Notification", body: "Will be shown after 5 seconds", timeout: remaining(until: shown, plus: 10)),
            "the cancelled notification fired"
        )
        // A request that fired stays delivered even when its banner was missed.
        XCTAssertEqual(try sample.press(.getDelivered), success("[getDelivered] count: 0, ids: []"))
    }

    /// CancelById only cancels pending requests: the delivered one stays (current behaviour.
    /// README 1.4).
    @MainActor
    func testN12_cancelByIdKeepsDelivered() throws {
        let token = try systemUIToken()
        let springboard = Springboard(token)
        XCTAssertEqual(try sample.press(.showImmediate, token), success("[showImmediate] error: nil"))
        XCTAssertTrue(try springboard.waitForBanner(title: "Immediate Notification", body: "Displayed now", timeout: 10))
        XCTAssertEqual(try sample.press(.cancelById), success("[cancel] id: sample-notification"))
        try sample.waitForNotificationIDs(.getScheduled, [])
        XCTAssertEqual(
            try sample.waitForNotificationIDs(.getDelivered, [Self.sampleId]),
            success("[getDelivered] count: 1, ids: [sample-notification]")
        )
    }

    /// CancelAll removes both pending requests, the one made by Show and the one made by
    /// Schedule. The +1 minute calendar triggers keep both pending while the list is read: with
    /// the 5 s / 10 s triggers of the design the sample's layout and the scrolling made the 5 s one
    /// fire before CancelAll could be pressed (stage 0c).
    @MainActor
    func testN13_cancelAllRemovesAllPending() throws {
        let token = try systemUIToken()
        try scheduleBothPending(token)
        XCTAssertEqual(try sample.press(.cancelAll), success("[cancelAll] called"))
        XCTAssertEqual(try sample.waitForNotificationIDs(.getScheduled, []), success("[getScheduled] count: 0, ids: []"))
    }

    @MainActor
    func testN14_removeDeliveredById() throws {
        let token = try systemUIToken()
        let springboard = Springboard(token)
        XCTAssertEqual(try sample.press(.showImmediate, token), success("[showImmediate] error: nil"))
        XCTAssertTrue(try springboard.waitForBanner(title: "Immediate Notification", body: "Displayed now", timeout: 10))
        try sample.waitForNotificationIDs(.getDelivered, [Self.sampleId])
        XCTAssertEqual(try sample.press(.removeDeliveredById), success("[removeDelivered] id: sample-notification"))
        XCTAssertEqual(try sample.waitForNotificationIDs(.getDelivered, []), success("[getDelivered] count: 0, ids: []"))
    }

    @MainActor
    func testN15_removeAllDelivered() throws {
        let token = try systemUIToken()
        let springboard = Springboard(token)
        XCTAssertEqual(try sample.press(.showImmediate, token), success("[showImmediate] error: nil"))
        XCTAssertEqual(try sample.press(.scheduleTimeInterval, token), success("[scheduleTimeInterval] id: scheduled-notification, error: nil"))
        XCTAssertTrue(try springboard.waitForBanner(title: "Scheduled Notification", body: "Scheduled in 10 seconds", timeout: 25))
        try sample.waitForNotificationIDs(.getDelivered, [Self.sampleId, Self.scheduledId])
        XCTAssertEqual(try sample.press(.removeAllDelivered), success("[removeAllDelivered] called"))
        XCTAssertEqual(try sample.waitForNotificationIDs(.getDelivered, []), success("[getDelivered] count: 0, ids: []"))
    }

    // MARK: - Schedule

    @MainActor
    func testN16_scheduleTimeIntervalFires() throws {
        let token = try systemUIToken()
        let springboard = Springboard(token)
        XCTAssertEqual(try sample.press(.scheduleTimeInterval, token), success("[scheduleTimeInterval] id: scheduled-notification, error: nil"))
        let scheduled = Date()
        XCTAssertEqual(
            try sample.waitForNotificationIDs(.getScheduled, [Self.scheduledId]),
            success("[getScheduled] count: 1, ids: [scheduled-notification]")
        )
        XCTAssertLessThan(Date().timeIntervalSince(scheduled), 10, "GetScheduled was read after the trigger time")
        XCTAssertTrue(try springboard.waitForBanner(
            title: "Scheduled Notification", body: "Scheduled in 10 seconds", timeout: remaining(until: scheduled, plus: 25)
        ))
        XCTAssertEqual(try sample.waitForNotificationIDs(.getScheduled, []), success("[getScheduled] count: 0, ids: []"))
        try sample.waitForNotificationIDs(.getDelivered, [Self.scheduledId])
    }

    @MainActor
    func testN17_scheduleCalendarThenCancelScheduled() throws {
        let token = try systemUIToken()
        XCTAssertEqual(try sample.press(.scheduleCalendar, token), success("[scheduleCalendar] id: scheduled-notification, error: nil"))
        try sample.waitForNotificationIDs(.getScheduled, [Self.scheduledId])
        XCTAssertEqual(try sample.press(.cancelScheduledById), success("[cancelScheduled] id: scheduled-notification"))
        XCTAssertEqual(try sample.waitForNotificationIDs(.getScheduled, []), success("[getScheduled] count: 0, ids: []"))
    }

    /// Registered on the simulator (stage 0c). Firing is not checked.
    @MainActor
    func testN18_scheduleLocationRegisters() throws {
        let token = try systemUIToken()
        XCTAssertEqual(
            try sample.press(.scheduleLocation, token),
            success("[scheduleLocation] Registered. Notification will fire when entering Tokyo Station (radius: 100m).")
        )
        try sample.waitForNotificationIDs(.getScheduled, [Self.scheduledId])
    }

    @MainActor
    func testN19_cancelScheduledById() throws {
        let token = try systemUIToken()
        let springboard = Springboard(token)
        XCTAssertEqual(try sample.press(.scheduleTimeInterval, token), success("[scheduleTimeInterval] id: scheduled-notification, error: nil"))
        let scheduled = Date()
        XCTAssertEqual(try sample.press(.cancelScheduledById), success("[cancelScheduled] id: scheduled-notification"))
        // Read before the trigger time (as N11).
        XCTAssertEqual(
            try sample.waitForNotificationIDs(.getScheduled, [], timeout: remaining(until: scheduled, plus: 9.5)),
            success("[getScheduled] count: 0, ids: []")
        )
        XCTAssertFalse(
            try springboard.waitForBanner(title: "Scheduled Notification", body: "Scheduled in 10 seconds", timeout: remaining(until: scheduled, plus: 15)),
            "the cancelled notification fired"
        )
        // A request that fired stays delivered even when its banner was missed.
        XCTAssertEqual(try sample.press(.getDelivered), success("[getDelivered] count: 0, ids: []"))
    }

    /// CancelAllScheduled also cancels the request made by Show (current behaviour: the same as
    /// cancelAll. README 1.4). Calendar triggers as in N13.
    @MainActor
    func testN20_cancelAllScheduledRemovesAllPending() throws {
        let token = try systemUIToken()
        try scheduleBothPending(token)
        XCTAssertEqual(try sample.press(.cancelAllScheduled), success("[cancelAllScheduled] called"))
        XCTAssertEqual(try sample.waitForNotificationIDs(.getScheduled, []), success("[getScheduled] count: 0, ids: []"))
    }

    // MARK: - Query and badge

    /// After the in-app cleanup of setUp both lists are empty.
    @MainActor
    func testN21_queriesAfterCleanupAreEmpty() throws {
        XCTAssertEqual(try sample.press(.getScheduled), success("[getScheduled] count: 0, ids: []"))
        XCTAssertEqual(try sample.press(.getDelivered), success("[getDelivered] count: 0, ids: []"))
    }

    /// The result lines only; the home screen is N34.
    @MainActor
    func testN22_setBadgeCountResults() throws {
        badgeTouched = true
        XCTAssertEqual(try sample.press(.setBadgeCount1), success("[setBadgeCount] 1, error: nil"))
        XCTAssertEqual(try sample.press(.setBadgeCount0), success("[setBadgeCount] 0, error: nil"))
    }

    /// The home screen icon's value: `1 new item` with badge 1 (en; the digit is checked) and empty
    /// with badge 0 (stage 0c).
    @MainActor
    func testN34_homeIconBadge() throws {
        let springboard = Springboard(try systemUIToken())
        badgeTouched = true
        XCTAssertEqual(try sample.press(.setBadgeCount1), success("[setBadgeCount] 1, error: nil"))
        try springboard.goHome()
        try waitForIconValue("a value with the digit 1", springboard) { $0.contains("1") }
        try sample.activate()
        XCTAssertEqual(try sample.press(.setBadgeCount0), success("[setBadgeCount] 0, error: nil"))
        try springboard.goHome()
        try waitForIconValue("an empty value", springboard) { $0.isEmpty }
        try sample.activate()
    }

    // MARK: - Helpers

    private func success(_ body: String) -> String {
        ResultLine.expected(success: true, body)
    }

    /// Seconds left until `start + seconds` (at least 0.1).
    private func remaining(until start: Date, plus seconds: TimeInterval) -> TimeInterval {
        max(0.1, seconds - Date().timeIntervalSince(start))
    }

    /// ShowCalendar(+1m) and ScheduleCalendar(+1m): two pending requests, read back (N13, N20).
    private func scheduleBothPending(_ token: SystemUIToken) throws {
        XCTAssertEqual(try sample.press(.showCalendar, token), success("[showCalendar] error: nil"))
        XCTAssertEqual(try sample.press(.scheduleCalendar, token), success("[scheduleCalendar] id: scheduled-notification, error: nil"))
        try sample.waitForNotificationIDs(.getScheduled, [Self.sampleId, Self.scheduledId])
    }

    /// The icon's value follows the badge asynchronously; reads it every 0.5 s for up to 10 s.
    private func waitForIconValue(_ description: String, _ springboard: Springboard, _ matches: (String) -> Bool) throws {
        let deadline = Date().addingTimeInterval(10)
        var value = try springboard.sampleIconValue()
        while !matches(value) {
            guard Date() < deadline else {
                throw SampleUITestError("icon value did not become \(description): \"\(value)\"")
            }
            Thread.sleep(forTimeInterval: 0.5)
            value = try springboard.sampleIconValue()
        }
    }
}
