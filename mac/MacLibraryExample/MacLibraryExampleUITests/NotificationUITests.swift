//
//  NotificationUITests.swift
//  MacLibraryExampleUITests
//
//  N1〜N18 and N14b of the UI test design (5.3): the state, showing, updating and cancelling,
//  scheduling, the lists and the badge of `NotificationSampleView`. N19 (the Dock's badge) is the
//  human check HC3: the badge is not in the Dock's accessibility tree (stage 0c 2.3).
//
//  Before anything is pressed a test with `notification` reads AuthorizationStatus and stops unless
//  it is `authorized` (U-7), clears the sample's own notifications and waits until no root of the
//  sample is shown (U-15). N1 and N17 hold no token and only wait. Results are compared in full
//  (U-1); a list is read again by pressing again (U-6).
//

import XCTest
import Foundation

final class NotificationUITests: SampleUITestCase {

    private var sample: SampleApp!
    private var screen: NotificationScreen!
    private var token: NotificationToken?
    private var badge: BadgeToken?

    private static let notificationId = SampleNotification.notificationId
    private static let scheduledId = SampleNotification.scheduledId
    /// A 10 s trigger fires 9〜10 s after the press; its banner is waited for up to 25 s (6.2).
    private static let tenSecondBanner: TimeInterval = 25
    /// "Does not appear" until the trigger's time plus 5 s (U-14 (a)).
    private static let tenSecondQuiet: TimeInterval = 15
    /// A +1 minute trigger pressed in the seconds window fires 30〜55 s later; 65 s (6.2).
    private static let calendarBanner: TimeInterval = 65

    override func setUpAfterGate() throws {
        sample = try launchSample()
        try sample.open(.notification)
        screen = NotificationScreen(sample)
        if try declares(.notification) {
            let token = try notificationToken()
            self.token = token
            try NotificationCleanup.prepare(screen, token)
        } else {
            try NotificationCleanup.waitNoSampleRoots(sample)
        }
        if try declares(.badge) {
            badge = try badgeToken()
        }
    }

    override func tearDownAfterGate() throws {
        if let token, let screen {
            if let badge {
                try NotificationCleanup.resetBadge(screen, badge, token)
            }
            try NotificationCleanup.finish(screen, token)
        }
        sample = nil
        screen = nil
        token = nil
        badge = nil
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

    // MARK: - State

    /// No token: reads only, no cleanup.
    @MainActor
    func testN1_permissionIsAuthorized() throws {
        XCTAssertEqual(try screen.run(.hasPermission), ok("[hasPermission] true"))
        XCTAssertEqual(try screen.run(.authorizationStatus), ok("[authorizationStatus] authorized"))
    }

    @MainActor
    func testN2_requestPermissionWhenAuthorized() throws {
        let token = try requireToken()
        let center = NotificationCenterUI(sample, token)
        XCTAssertEqual(try screen.run(.requestPermission, token), ok("[requestPermission] granted"))
        try center.expectNoPermissionPrompt(for: 5)
    }

    /// System Settings comes to the front; nothing in it is read or pressed. It is stopped only when
    /// it was not running before.
    @MainActor
    func testN3_openNotificationSettings() throws {
        let settingsToken = try settingsToken()
        let settings = SystemSettingsApp(settingsToken)
        let wasRunning = settings.isRunning
        let before = try sample.resultSequence(.notification)
        try sample.tap(.openNotificationSettings, settingsToken)
        try settings.waitForeground()
        try sample.activate()
        let text = try sample.waitForNextResult(.notification, after: before,
                                                marker: NotificationButton.openNotificationSettings.resultMarker)
        XCTAssertEqual(text, ok("[openNotificationSettings] success"))
        try sample.expectNoFurtherResult(.notification, sequence: before + 1)
        try settings.stop(wasRunning: wasRunning)
    }

    // MARK: - Show

    /// The sentinel of a run that selects `notification` (U-20): runs first.
    @MainActor
    func testN4_showImmediateBanner() throws {
        let token = try requireToken()
        let center = NotificationCenterUI(sample, token)
        XCTAssertEqual(try screen.runShowing(.showImmediate, token, center: center, anchor: .immediate).text,
                       ok("[showImmediate] success"))
        let list = try screen.pollList(.getDelivered) { $0.count == 1 }
        XCTAssertTrue(list.hasExactly([], immediate: 1), "delivered: \(list.ids)")
    }

    @MainActor
    func testN5_showTimeIntervalFiresInTheBackground() throws {
        let token = try requireToken()
        let center = NotificationCenterUI(sample, token)
        XCTAssertEqual(try screen.run(.showTimeInterval, token), ok("[showTimeInterval] success"))
        let pressed = try screen.lastClickTime()
        let scheduled = try screen.pollList(.getScheduled) { $0.count == 1 }
        XCTAssertTrue(scheduled.hasExactly([Self.notificationId]), "scheduled: \(scheduled.ids)")
        try FinderFront(token).bringToFront(behind: sample)
        _ = try center.waitForRoot(.tenSeconds, timeout: NotificationScreen.timeLeft(since: pressed, total: Self.tenSecondBanner))
        try sample.activate()
        let delivered = try screen.pollList(.getDelivered) { $0.count == 1 }
        XCTAssertTrue(delivered.hasExactly([Self.notificationId]), "delivered: \(delivered.ids)")
    }

    @MainActor
    func testN6_showCalendarFiresAfterOneMinute() throws {
        executionTimeAllowance = 240
        let token = try requireToken()
        let center = NotificationCenterUI(sample, token)
        try screen.waitForSecondsWindow()
        XCTAssertEqual(try screen.run(.showCalendar, token), ok("[showCalendar] success"))
        let pressed = try screen.lastClickTime()
        let scheduled = try screen.pollList(.getScheduled) { $0.count == 1 }
        XCTAssertTrue(scheduled.hasExactly([Self.notificationId]), "scheduled: \(scheduled.ids)")
        _ = try center.waitForRoot(.calendar, timeout: NotificationScreen.timeLeft(since: pressed, total: Self.calendarBanner))
    }

    // MARK: - Update, cancel, remove

    @MainActor
    func testN7_updateByIdReplacesTheScheduled() throws {
        let token = try requireToken()
        let center = NotificationCenterUI(sample, token)
        XCTAssertEqual(try screen.run(.showTimeInterval, token), ok("[showTimeInterval] success"))
        let pressed = try screen.lastClickTime()
        XCTAssertEqual(try screen.runShowing(.updateById, token, center: center, anchor: .updated).text,
                       ok("[updateById] success"))
        let scheduled = try screen.pollList(.getScheduled) { $0.count == 0 }
        XCTAssertEqual(scheduled.ids, [])
        let delivered = try screen.pollList(.getDelivered) { $0.count == 1 }
        XCTAssertTrue(delivered.hasExactly([Self.notificationId]), "delivered: \(delivered.ids)")
        try center.expectNoRoot(.tenSeconds, until: pressed.addingTimeInterval(Self.tenSecondQuiet))
    }

    @MainActor
    func testN8_cancelByIdStopsTheScheduled() throws {
        let token = try requireToken()
        let center = NotificationCenterUI(sample, token)
        XCTAssertEqual(try screen.run(.showTimeInterval, token), ok("[showTimeInterval] success"))
        let pressed = try screen.lastClickTime()
        XCTAssertEqual(try screen.run(.cancelById), ok("[cancelById] id=\(Self.notificationId)"))
        XCTAssertEqual(try screen.pollList(.getScheduled) { $0.count == 0 }.ids, [])
        try center.expectNoRoot(.tenSeconds, until: pressed.addingTimeInterval(Self.tenSecondQuiet))
        XCTAssertEqual(try screen.pollList(.getDelivered) { _ in true }, NotificationIDList(count: 0, ids: []))
    }

    @MainActor
    func testN9_cancelAllClearsBothCalendarRequests() throws {
        executionTimeAllowance = 240
        let token = try requireToken()
        try screen.waitForSecondsWindow()
        XCTAssertEqual(try screen.run(.showCalendar, token), ok("[showCalendar] success"))
        XCTAssertEqual(try screen.run(.scheduleCalendar, token), ok("[scheduleCalendar] success"))
        let both = try screen.pollList(.getScheduled) { $0.count == 2 }
        XCTAssertTrue(both.hasExactly([Self.notificationId, Self.scheduledId]), "scheduled: \(both.ids)")
        XCTAssertEqual(try screen.run(.cancelAll), ok("[cancelAll] called"))
        XCTAssertEqual(try screen.pollList(.getScheduled) { $0.count == 0 }.ids, [])
    }

    @MainActor
    func testN10_removeDeliveredById() throws {
        let token = try requireToken()
        let center = NotificationCenterUI(sample, token)
        XCTAssertEqual(try screen.run(.showTimeInterval, token), ok("[showTimeInterval] success"))
        let pressed = try screen.lastClickTime()
        _ = try center.waitForRoot(.tenSeconds, timeout: NotificationScreen.timeLeft(since: pressed, total: Self.tenSecondBanner))
        let delivered = try screen.pollList(.getDelivered) { $0.count == 1 }
        XCTAssertTrue(delivered.hasExactly([Self.notificationId]), "delivered: \(delivered.ids)")
        XCTAssertEqual(try screen.run(.removeDeliveredById), ok("[removeDelivered] id=\(Self.notificationId)"))
        XCTAssertEqual(try screen.pollList(.getDelivered) { $0.count == 0 }.ids, [])
    }

    /// The current behaviour: ShowImmediate's id is `mac-sample-notification-<seconds>`, so
    /// RemoveDeliveredById (`mac-sample-notification`) leaves it (design 9.4).
    @MainActor
    func testN11_removeDeliveredByIdKeepsTheImmediate() throws {
        let token = try requireToken()
        let center = NotificationCenterUI(sample, token)
        XCTAssertEqual(try screen.runShowing(.showImmediate, token, center: center, anchor: .immediate).text,
                       ok("[showImmediate] success"))
        XCTAssertTrue(try screen.pollList(.getDelivered) { $0.count == 1 }.hasExactly([], immediate: 1))
        XCTAssertEqual(try screen.run(.removeDeliveredById), ok("[removeDelivered] id=\(Self.notificationId)"))
        let after = try screen.pollList(.getDelivered) { _ in true }
        XCTAssertTrue(after.hasExactly([], immediate: 1), "delivered: \(after.ids)")
    }

    @MainActor
    func testN12_removeAllDelivered() throws {
        let token = try requireToken()
        let center = NotificationCenterUI(sample, token)
        XCTAssertEqual(try screen.runShowing(.showImmediate, token, center: center, anchor: .immediate).text,
                       ok("[showImmediate] success"))
        XCTAssertEqual(try screen.run(.scheduleTimeInterval, token), ok("[scheduleTimeInterval] success"))
        let pressed = try screen.lastClickTime()
        _ = try center.waitForRoot(.scheduled, timeout: NotificationScreen.timeLeft(since: pressed, total: Self.tenSecondBanner))
        let two = try screen.pollList(.getDelivered) { $0.count == 2 }
        XCTAssertTrue(two.hasExactly([Self.scheduledId], immediate: 1), "delivered: \(two.ids)")
        XCTAssertEqual(try screen.run(.removeAllDelivered), ok("[removeAllDelivered] called"))
        XCTAssertEqual(try screen.pollList(.getDelivered) { $0.count == 0 }.ids, [])
    }

    // MARK: - Schedule

    @MainActor
    func testN13_scheduleTimeIntervalFires() throws {
        let token = try requireToken()
        let center = NotificationCenterUI(sample, token)
        XCTAssertEqual(try screen.run(.scheduleTimeInterval, token), ok("[scheduleTimeInterval] success"))
        let pressed = try screen.lastClickTime()
        let scheduled = try screen.pollList(.getScheduled) { $0.count == 1 }
        XCTAssertTrue(scheduled.hasExactly([Self.scheduledId]), "scheduled: \(scheduled.ids)")
        _ = try center.waitForRoot(.scheduled, timeout: NotificationScreen.timeLeft(since: pressed, total: Self.tenSecondBanner))
        XCTAssertEqual(try screen.pollList(.getScheduled) { $0.count == 0 }.ids, [])
        let delivered = try screen.pollList(.getDelivered) { $0.count == 1 }
        XCTAssertTrue(delivered.hasExactly([Self.scheduledId]), "delivered: \(delivered.ids)")
    }

    @MainActor
    func testN14_cancelScheduledById() throws {
        executionTimeAllowance = 240
        let token = try requireToken()
        try screen.waitForSecondsWindow()
        XCTAssertEqual(try screen.run(.scheduleCalendar, token), ok("[scheduleCalendar] success"))
        let scheduled = try screen.pollList(.getScheduled) { $0.count == 1 }
        XCTAssertTrue(scheduled.hasExactly([Self.scheduledId]), "scheduled: \(scheduled.ids)")
        XCTAssertEqual(try screen.run(.cancelScheduledById), ok("[cancelScheduled] id=\(Self.scheduledId)"))
        XCTAssertEqual(try screen.pollList(.getScheduled) { $0.count == 0 }.ids, [])
    }

    @MainActor
    func testN14b_scheduleCalendarFires() throws {
        executionTimeAllowance = 240
        let token = try requireToken()
        let center = NotificationCenterUI(sample, token)
        try screen.waitForSecondsWindow()
        XCTAssertEqual(try screen.run(.scheduleCalendar, token), ok("[scheduleCalendar] success"))
        let pressed = try screen.lastClickTime()
        let scheduled = try screen.pollList(.getScheduled) { $0.count == 1 }
        XCTAssertTrue(scheduled.hasExactly([Self.scheduledId]), "scheduled: \(scheduled.ids)")
        _ = try center.waitForRoot(.scheduledCalendar,
                                   timeout: NotificationScreen.timeLeft(since: pressed, total: Self.calendarBanner))
        XCTAssertEqual(try screen.pollList(.getScheduled) { $0.count == 0 }.ids, [])
        let delivered = try screen.pollList(.getDelivered) { $0.count == 1 }
        XCTAssertTrue(delivered.hasExactly([Self.scheduledId]), "delivered: \(delivered.ids)")
    }

    @MainActor
    func testN15_cancelScheduledTimeInterval() throws {
        let token = try requireToken()
        let center = NotificationCenterUI(sample, token)
        XCTAssertEqual(try screen.run(.scheduleTimeInterval, token), ok("[scheduleTimeInterval] success"))
        let pressed = try screen.lastClickTime()
        XCTAssertEqual(try screen.run(.cancelScheduledById), ok("[cancelScheduled] id=\(Self.scheduledId)"))
        XCTAssertEqual(try screen.pollList(.getScheduled) { $0.count == 0 }.ids, [])
        try center.expectNoRoot(.scheduled, until: pressed.addingTimeInterval(Self.tenSecondQuiet))
    }

    /// The current behaviour: CancelAllScheduled is the same operation as CancelAll (plan 1.4).
    @MainActor
    func testN16_cancelAllScheduled() throws {
        executionTimeAllowance = 240
        let token = try requireToken()
        try screen.waitForSecondsWindow()
        XCTAssertEqual(try screen.run(.showCalendar, token), ok("[showCalendar] success"))
        XCTAssertEqual(try screen.run(.scheduleCalendar, token), ok("[scheduleCalendar] success"))
        let both = try screen.pollList(.getScheduled) { $0.count == 2 }
        XCTAssertTrue(both.hasExactly([Self.notificationId, Self.scheduledId]), "scheduled: \(both.ids)")
        XCTAssertEqual(try screen.run(.cancelAllScheduled), ok("[cancelAllScheduled] called"))
        XCTAssertEqual(try screen.pollList(.getScheduled) { $0.count == 0 }.ids, [])
    }

    // MARK: - Query and badge

    /// No token: only the four buttons that ask nothing (the sample's own requests and deliveries).
    @MainActor
    func testN17_clearsWithoutAsking() throws {
        XCTAssertEqual(try screen.run(.removeAllDelivered), ok("[removeAllDelivered] called"))
        XCTAssertEqual(try screen.run(.cancelAllScheduled), ok("[cancelAllScheduled] called"))
        XCTAssertEqual(try screen.pollList(.getScheduled) { $0.count == 0 }, NotificationIDList(count: 0, ids: []))
        XCTAssertEqual(try screen.pollList(.getDelivered) { $0.count == 0 }, NotificationIDList(count: 0, ids: []))
    }

    @MainActor
    func testN18_setBadgeCount() throws {
        let token = try requireToken()
        guard let badge else {
            throw SampleUITestError(.gate, "the test holds no badge token")
        }
        XCTAssertEqual(try screen.run(.setBadgeCount1, badge, token), ok("[setBadgeCount(1)] success"))
        XCTAssertEqual(try screen.run(.setBadgeCount0, badge, token), ok("[setBadgeCount(0)] success"))
    }
}
