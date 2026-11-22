//
//  NotificationPermissionUITests.swift
//  IosLibraryExampleUITests
//
//  NP1 and NP2 of the UI test design (3.3, U-7), and N42 and N40 of the Swift API design (13.2).
//  Each test needs a freshly installed sample (`notDetermined`): the runner deletes the sample
//  before each test and runs NP2, N42, N40 and NP1 in that order, one test per xcodebuild
//  invocation (the run ends with the permission granted). The interruption monitor of this class
//  presses nothing (U-8); the permission alert is waited for and pressed explicitly through
//  springboard. N42 and N40 run on the simulator only (SIMULATOR_ONLY_TESTS).
//

import XCTest
import Foundation

final class NotificationPermissionUITests: SampleUITestCase {

    private var sample: SampleApp!

    override func setUpAfterGate() throws {
        sample = try launchSample()
        try sample.open(.notification)
    }

    override func tearDownAfterGate() throws {
        sample = nil
    }

    /// NP1: request -> Allow -> granted, authorized, true.
    @MainActor
    func testNP1_allowPermission() throws {
        _ = try reinstallToken()
        let token = try systemUIToken()
        let springboard = Springboard(token)
        try requireFreshInstall()

        let before = try sample.updateCount(.notification)
        try sample.tap(.requestPermission, token)
        XCTAssertTrue(springboard.waitForAlert(), "the permission alert did not appear")
        XCTAssertTrue(try springboard.alertNamesSample(), "the permission alert does not name the sample")
        try springboard.tapAlertButton(SystemLabels.allow)
        try sample.waitForUpdateCount(.notification, before + 1)
        XCTAssertEqual(try sample.resultText(.notification), success("[requestPermission] granted"))
        XCTAssertEqual(sample.remainingAlertCount, 0, "alerts left after the permission request")

        XCTAssertEqual(try sample.press(.authorizationStatus), success("[authorizationStatus] authorized"))
        XCTAssertEqual(try sample.press(.hasPermission), success("[hasPermission] true"))
    }

    /// NP2: request -> Don't Allow -> denied; a second request shows no alert; ShowImmediate fails
    /// and shows no banner.
    @MainActor
    func testNP2_denyPermission() throws {
        _ = try reinstallToken()
        let token = try systemUIToken()
        let springboard = Springboard(token)
        try requireFreshInstall()
        XCTAssertEqual(try sample.press(.hasPermission), success("[hasPermission] false"))

        let denied = failure("[requestPermission] denied. Permission dialog will not appear again. Please enable notifications in Settings.")
        let before = try sample.updateCount(.notification)
        try sample.tap(.requestPermission, token)
        XCTAssertTrue(springboard.waitForAlert(), "the permission alert did not appear")
        XCTAssertTrue(try springboard.alertNamesSample(), "the permission alert does not name the sample")
        try springboard.tapAlertButton(SystemLabels.dontAllow)
        try sample.waitForUpdateCount(.notification, before + 1)
        XCTAssertEqual(try sample.resultText(.notification), denied)
        XCTAssertEqual(sample.remainingAlertCount, 0, "alerts left after the permission request")

        XCTAssertEqual(try sample.press(.authorizationStatus), success("[authorizationStatus] denied"))
        XCTAssertEqual(try sample.press(.hasPermission), success("[hasPermission] false"))

        // The second request shows no alert for 5 seconds (fixed wait. U-14).
        let second = try sample.updateCount(.notification)
        try sample.tap(.requestPermission, token)
        XCTAssertFalse(springboard.waitForAlert(timeout: 5), "the permission alert appeared again")
        try sample.waitForUpdateCount(.notification, second + 1)
        XCTAssertEqual(try sample.resultText(.notification), denied)

        // Without the permission no notification is posted: no banner for 5 seconds (U-14).
        XCTAssertEqual(
            try sample.press(.showImmediate, token),
            failure("Notification permission is not granted. Please request permission first.")
        )
        XCTAssertFalse(
            try springboard.waitForBanner(title: "Immediate Notification", body: "Displayed now", timeout: 5),
            "a banner appeared without the permission"
        )
    }

    /// N42 (Swift API design 13.2, S-13, SA-05): while the permission is not determined, a request
    /// with `.foreground` made in the background fails with `notForeground` and shows no alert;
    /// nothing is requested (the status stays `notDetermined`). Simulator only.
    @MainActor
    func testN42_aPermissionRequestInTheBackgroundReportsNotForeground() throws {
        _ = try reinstallToken()
        let token = try systemUIToken()
        let springboard = Springboard(token)
        try requireFreshInstall()

        let before = try sample.updateCount(.notification)
        try sample.tap(.requestPermissionAfter3Seconds, token)
        try springboard.goHome()
        // A fixed wait (U-14 exception, as S18): the request comes 3 seconds after the tap while
        // the sample is in the background; no permission alert appears meanwhile.
        XCTAssertFalse(springboard.waitForAlert(timeout: 6), "a permission alert appeared for a request in the background")
        try sample.activate()
        try sample.waitForUpdateCount(.notification, before + 1)
        XCTAssertEqual(try sample.resultText(.notification), failure("[requestPermissionAfter3Seconds@background] failure notForeground"))
        XCTAssertEqual(sample.remainingAlertCount, 0, "alerts left after the request")
        XCTAssertEqual(try sample.press(.authorizationStatus), success("[authorizationStatus] notDetermined"))
    }

    /// N40 (Swift API design 13.2, SA-13, SR-11, MS-07): a freshly installed sample asks with
    /// `.providesAppNotificationSettings` from the foreground and opens its settings page; the
    /// sample's notification settings link in Settings sends `openSettingsFor`, which the library
    /// delivers to `settingsRequests` (one request, without a notification) and the sample comes
    /// to the foreground. Simulator only (it presses rows of Settings).
    @MainActor
    func testN40_theAppNotificationSettingsLinkSendsASettingsRequest() throws {
        _ = try reinstallToken()
        let token = try systemUIToken()
        let springboard = Springboard(token)
        try requireFreshInstall()
        XCTAssertEqual(try sample.statusLine(.lastSettingsRequest), "settingsRequests=0, notificationId=-")

        let before = try sample.updateCount(.notification)
        try sample.tap(.requestPermissionWithAppSettings, token)
        XCTAssertTrue(springboard.waitForAlert(), "the permission alert did not appear")
        XCTAssertTrue(try springboard.alertNamesSample(), "the permission alert does not name the sample")
        try springboard.tapAlertButton(SystemLabels.allow)
        try sample.waitForUpdateCount(.notification, before + 1)
        XCTAssertEqual(try sample.resultText(.notification), success("[requestPermissionWithAppSettings] success granted=true"))

        let opened = try sample.updateCount(.notification)
        try sample.tap(.openNotificationSettingsForeground, token)
        XCTAssertTrue(springboard.waitForSettingsForeground(timeout: 10), "Settings did not come to the foreground")
        try springboard.openSampleNotificationSettingsLink()
        XCTAssertTrue(try sample.waitForForeground(timeout: 10), "the sample did not come to the foreground")
        XCTAssertTrue(sample.isShowing(.notification), "the sample is not on the Notification screen")
        try sample.waitForStatusLine(.lastSettingsRequest, "settingsRequests=1, notificationId=-")
        try sample.waitForUpdateCount(.notification, opened + 1)
        XCTAssertEqual(try sample.resultText(.notification), success("[openNotificationSettingsForeground] success opened"))
        sample.observeQuietly(for: 2)
        XCTAssertEqual(try sample.statusLine(.lastSettingsRequest), "settingsRequests=1, notificationId=-", "another settings request arrived")
    }

    // MARK: - Helpers

    /// The sample must have been deleted right before this test (U-7).
    @MainActor
    private func requireFreshInstall() throws {
        let status = try sample.press(.authorizationStatus)
        guard status == success("[authorizationStatus] notDetermined") else {
            throw SampleUITestError("the permission is not notDetermined (\(status)); delete the sample before this test")
        }
    }

    private func success(_ body: String) -> String {
        ResultLine.expected(success: true, body)
    }

    private func failure(_ body: String) -> String {
        ResultLine.expected(success: false, body)
    }
}
