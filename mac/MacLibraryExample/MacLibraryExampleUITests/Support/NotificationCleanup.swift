//
//  NotificationCleanup.swift
//  MacLibraryExampleUITests
//
//  The start and the end of a Notification test (UI test design U-7, U-15). Trusted Support file.
//
//  - Before anything is pressed: wait, read-only, until no root of the sample is shown (15 s).
//  - A test that holds a `NotificationToken` then reads AuthorizationStatus (no prompt can come
//    from it) and stops with `NTK-PRECONDITION:notAuthorized` unless it is `authorized`, and clears
//    the sample's own delivered and scheduled notifications. N1 and N17 hold no token: they only
//    wait.
//  - The cleanup presses only RemoveAllDelivered and CancelAllScheduled (neither asks for
//    permission); SetBadgeCount(0) only with a `BadgeToken` and after `authorized` is read.
//    Nothing changes the permission.
//

import XCTest
import Foundation

enum NotificationCleanup {

    static let rootTimeout: TimeInterval = 15
    static let authorizedText = ResultLine.expected(success: true, "[authorizationStatus] authorized")

    /// Read-only: no root of the sample for up to 15 s.
    static func waitNoSampleRoots(_ sample: SampleApp) throws {
        try sample.waitUntil("no root of the sample", timeout: rootTimeout, step: .notificationRoot) {
            NotificationCenterRead.sampleRootCount() == 0
        }
    }

    /// Presses AuthorizationStatus (reads only) and stops unless it is `authorized` (U-7).
    static func requireAuthorized(_ screen: NotificationScreen) throws {
        let text = try screen.run(.authorizationStatus, quiet: false)
        guard text == authorizedText else {
            throw SampleUITestError(.precondition, "NTK-PRECONDITION:notAuthorized the sample's notifications are not authorized")
        }
    }

    /// The sample's own cleanup: RemoveAllDelivered and CancelAllScheduled (U-15).
    static func clear(_ screen: NotificationScreen, _ token: NotificationToken) throws {
        _ = token
        try screen.run(.removeAllDelivered, quiet: false)
        try screen.run(.cancelAllScheduled, quiet: false)
    }

    /// The start of a test that holds `token`: authorized, cleared, no root shown.
    static func prepare(_ screen: NotificationScreen, _ token: NotificationToken) throws {
        try requireAuthorized(screen)
        try clear(screen, token)
        try waitNoSampleRoots(screen.sample)
    }

    /// The end of a test that holds `token`: the same two buttons, with the sample in front on its
    /// Notification screen. Skipped when the sample is not running.
    static func finish(_ screen: NotificationScreen, _ token: NotificationToken) throws {
        let state = screen.sample.state
        guard state == .runningForeground || state == .runningBackground else { return }
        if state == .runningBackground {
            try screen.sample.activate()
        }
        guard screen.sample.isShowing(.notification) else { return }
        try clear(screen, token)
    }

    /// Badge 0 at the end of a `badge` test, only after `authorized` is read (U-15).
    static func resetBadge(_ screen: NotificationScreen, _ badge: BadgeToken, _ token: NotificationToken) throws {
        guard screen.sample.state == .runningForeground, screen.sample.isShowing(.notification) else { return }
        guard try screen.run(.authorizationStatus, quiet: false) == authorizedText else { return }
        try screen.run(.setBadgeCount0, badge, token)
    }
}
