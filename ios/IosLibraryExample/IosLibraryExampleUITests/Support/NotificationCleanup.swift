//
//  NotificationCleanup.swift
//  IosLibraryExampleUITests
//
//  The two cleanups of the notification tests (UI test design U-15) and the permission
//  precondition of the notification tests (3.0). Trusted Support file.
//
//  - `inApp`: brings the sample to the front on its Notification screen, removes its delivered
//    and scheduled notifications through its own buttons and waits until both lists are empty
//    (U-6). Needs no category.
//  - `springboard`: leaves an expanded banner by going home and waits until no banner of the
//    sample is left. The base calls it only when the gate passed and the test received a
//    `SystemUIToken`.
//  - `NotificationPrecondition.requireAuthorized`: the notification permission must be
//    `authorized` before a notification test (3.0).
//

import XCTest
import Foundation

enum NotificationCleanup {

    static let reflectTimeout: TimeInterval = 10
    static let bannerTimeout: TimeInterval = 15

    /// Brings the sample to the front (relaunching it when it is not running), opens the
    /// Notification screen from the menu when another process start left it there, and empties
    /// the delivered and scheduled lists.
    static func inApp(_ sample: SampleApp) throws {
        if !sample.isForeground {
            try sample.activate()
        }
        if !sample.isShowing(.notification) {
            try sample.open(.notification)
        }
        try sample.press(.removeAllDelivered)
        try sample.press(.cancelAllScheduled)
        try sample.waitForNotificationIDs(.getDelivered, [], timeout: reflectTimeout)
        try sample.waitForNotificationIDs(.getScheduled, [], timeout: reflectTimeout)
    }

    static func springboard(_ token: SystemUIToken) throws {
        let springboard = Springboard(token)
        try springboard.goHome()
        guard try springboard.waitForNoSampleBanner(timeout: bannerTimeout) else {
            throw SampleUITestError("a banner of the sample was still shown \(bannerTimeout)s after the test")
        }
    }
}

enum NotificationPrecondition {

    /// Reads `AuthorizationStatus` (3.0). `authorized` passes. `notDetermined` is resolved by
    /// requesting the permission and pressing Allow only when the test declares `systemui`;
    /// otherwise it skips with `NTK-PRECONDITION:` on the device and fails on the simulator.
    /// `denied` fails: only deleting the sample resets it.
    static func requireAuthorized(_ sample: SampleApp, in testCase: SampleUITestCase) throws {
        let status = try sample.press(.authorizationStatus)
        switch status {
        case ResultLine.expected(success: true, "[authorizationStatus] authorized"):
            return
        case ResultLine.expected(success: true, "[authorizationStatus] notDetermined"):
            let key = try SampleUITestCase.normalizedTestKey(fromName: testCase.name)
            if try DeviceRequirements.categories(for: key).contains(.systemui) {
                try grant(sample, try testCase.systemUIToken())
            } else if SampleUITestCase.isDevice {
                throw XCTSkip("NTK-PRECONDITION:notDetermined")
            } else {
                throw SampleUITestError("the notification permission is notDetermined; run NotificationPermissionUITests/testNP1_allowPermission first")
            }
        case ResultLine.expected(success: true, "[authorizationStatus] denied"):
            throw SampleUITestError("the notification permission is denied; delete the sample (simctl uninstall) and run NotificationPermissionUITests/testNP1_allowPermission")
        default:
            throw SampleUITestError("unexpected authorization status: \(status)")
        }
    }

    private static func grant(_ sample: SampleApp, _ token: SystemUIToken) throws {
        let springboard = Springboard(token)
        let before = try sample.updateCount(.notification)
        try sample.tap(.requestPermission, token)
        guard springboard.waitForAlert(), try springboard.alertNamesSample() else {
            throw SampleUITestError("the permission alert of the sample did not appear")
        }
        try springboard.tapAlertButton(SystemLabels.allow)
        try sample.waitForUpdateCount(.notification, before + 1)
        let text = try sample.resultText(.notification)
        guard text == ResultLine.expected(success: true, "[requestPermission] granted") else {
            throw SampleUITestError("requesting the permission did not grant it: \(text)")
        }
    }
}
