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
    }

    @MainActor
    func testN32_replyColdStart() throws {
        let springboard = try showAndTerminate(registerCategory: true)
        try springboard.expandBanner(title: Self.title, body: Self.body)
        try springboard.tapAction("Reply", title: Self.title, body: Self.body)
        try springboard.sendReply("cold reply", title: Self.title, body: Self.body)
        try sample.activate()
        try openNotificationFromMenu()
        try assertEvent(kind: "textInput", actionId: "reply", userText: "cold reply")
    }

    @MainActor
    func testN33_deleteColdStart() throws {
        let springboard = try showAndTerminate(registerCategory: true)
        try springboard.expandBanner(title: Self.title, body: Self.body)
        try springboard.tapAction("Delete", title: Self.title, body: Self.body)
        try sample.activate()
        try openNotificationFromMenu()
        try assertEvent(kind: "action", actionId: "delete", userText: "-")
    }

    // MARK: - Helpers

    private func success(_ body: String) -> String {
        ResultLine.expected(success: true, body)
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

    @MainActor
    private func assertEvent(kind: String, actionId: String, userText: String) throws {
        try sample.waitForEventSequence(1)
        let expected = ["sequence=1", "kind=\(kind)", "notificationId=sample-notification", "actionId=\(actionId)", "userText=\(userText)"]
        XCTAssertEqual(try sample.lastEvent(), expected)
    }
}
