//
//  NotificationPermissionUITests.swift
//  IosLibraryExampleUITests
//
//  NP1 and NP2 of the UI test design (3.3, U-7). Each test needs a freshly installed sample
//  (`notDetermined`): the runner deletes the sample, runs NP2, deletes it again and runs NP1, one
//  test per xcodebuild invocation. The interruption monitor of this class presses nothing (U-8);
//  the permission alert is waited for and pressed explicitly through springboard.
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
