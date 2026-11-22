//
//  NotificationColdStartUITests.swift
//  MacLibraryExampleUITests
//
//  NC1〜NC3 of the UI test design (5.3, U-22): a notification wakes the stopped sample. The contract
//  of the design's steps 1〜7:
//
//  1. Launch, the Notification screen, `authorized`, the cleanup, RegisterCategory, and the copy
//     mark V1 equals the runner's `NTK_EXPECTED_COPY` (U-21).
//  2. ShowTimeInterval(10s) at T0, then GetScheduled shows the request (pressed again at most once).
//  3. `terminate()`; T0 to `notRunning` must be within 6 s, or the test stops with
//     `NTK-PRECONDITION:coldStartTiming` before any press in Notification Center.
//  4. The root within 25 s of T0, one second, then the operation (the sample is not running).
//  5. The foreground within 15 s, without `launch()` or `activate()`.
//  6. The window lies on a display, the Notification screen opens in the woken process, the last
//     event is the expected one, the copy mark is still V1, and no further event for 2 s.
//  7. The launch kind (`launch_response`) is not read (5.9 NC5).
//
//  The times from T0 are printed as `NTK-TIMING` (seconds only. Design 3.4).
//

import XCTest
import Foundation

final class NotificationColdStartUITests: SampleUITestCase {

    private var sample: SampleApp!
    private var screen: NotificationScreen!
    private var token: NotificationToken?

    private static let notRunningBudget: TimeInterval = 6
    private static let tenSecondBanner: TimeInterval = 25
    private static let wakeTimeout: TimeInterval = 15

    override func setUpAfterGate() throws {
        sample = try launchSample()
        try sample.open(.notification)
        screen = NotificationScreen(sample)
        let token = try notificationToken()
        self.token = token
        try NotificationCleanup.prepare(screen, token)
        XCTAssertEqual(try screen.run(.registerCategory),
                       ResultLine.expected(success: true, SampleNotification.registeredText))
    }

    override func tearDownAfterGate() throws {
        if let token, let screen {
            try NotificationCleanup.finish(screen, token)
        }
        sample = nil
        screen = nil
        token = nil
    }

    @MainActor
    func testNC1_bodyClickLaunches() throws {
        try coldStart(actionId: ExpectedEvent.defaultAction, kind: "action", userText: "-") { center, root in
            try center.clickBody(root, sampleIs: .notRunning)
        }
    }

    @MainActor
    func testNC2_openActionLaunches() throws {
        try coldStart(actionId: SampleNotification.openAction, kind: "action", userText: "-") { center, root in
            try center.openOptions(root, sampleIs: .notRunning)
            try center.choose(SampleNotification.openTitle, of: root, sampleIs: .notRunning)
        }
    }

    /// From a stopped state the reply brings the sample to the front (stage 0a 5.1).
    @MainActor
    func testNC3_replyLaunches() throws {
        try coldStart(actionId: SampleNotification.replyAction, kind: "textInput", userText: "cold reply") { center, root in
            try center.openOptions(root, sampleIs: .notRunning)
            try center.choose(SampleNotification.replyTitle, of: root, sampleIs: .notRunning)
            try center.reply("cold reply", in: root)
        }
    }

    // MARK: - Helpers

    private func coldStart(actionId: String, kind: String, userText: String,
                           operate: (NotificationCenterUI, NotificationRoot) throws -> Void) throws {
        guard let token else {
            throw SampleUITestError(.gate, "the test holds no notification token")
        }
        let coldToken = try coldStartToken()
        let center = NotificationCenterUI(sample, token)

        // 1
        let copy = try sample.launchCopy()
        XCTAssertEqual(copy, try expectedLaunchCopy(coldToken), "the sample is not the copy the runner built")

        // 2 (no 2-second checks here: the banner comes 10 s after T0)
        XCTAssertEqual(try screen.run(.showTimeInterval, token, quiet: false),
                       ResultLine.expected(success: true, "[showTimeInterval] success"))
        guard let pressed = sample.lastClickAt else {
            throw SampleUITestError(.coldStart, "the click of ShowTimeInterval has no time")
        }
        let scheduled = try screen.pollList(.getScheduled, maxPresses: 2, quiet: false) { $0.count == 1 }
        XCTAssertTrue(scheduled.hasExactly([SampleNotification.notificationId]), "scheduled: \(scheduled.ids)")

        // 3
        let stopped = try sample.terminateForColdStart(coldToken)
        let toStop = stopped.timeIntervalSince(pressed)
        guard toStop <= Self.notRunningBudget else {
            throw SampleUITestError(.precondition, "NTK-PRECONDITION:coldStartTiming notRunning \(Self.seconds(toStop))s after T0")
        }

        // 4
        let root = try center.waitForRoot(.tenSeconds,
                                          timeout: NotificationScreen.timeLeft(since: pressed, total: Self.tenSecondBanner))
        let seen = root.appearedAt.timeIntervalSince(pressed)
        try operate(center, root)
        let operated = Date().timeIntervalSince(pressed)

        // 5, 6
        try sample.adoptWokenProcess(coldToken, timeout: Self.wakeTimeout)
        let foreground = Date().timeIntervalSince(pressed)
        print("NTK-TIMING \(name) notRunning=\(Self.seconds(toStop)) rootSeen=\(Self.seconds(seen)) operated=\(Self.seconds(operated)) foreground=\(Self.seconds(foreground))")
        try sample.open(.notification)
        try screen.waitForEvent(ExpectedEvent(sequence: 1, kind: kind,
                                              notificationId: .exact(SampleNotification.notificationId),
                                              actionId: actionId, userText: userText))
        XCTAssertEqual(try sample.launchCopy(), copy, "the woken sample is another copy")
        try screen.expectNoFurtherEvent(sequence: 1)
    }

    private static func seconds(_ value: TimeInterval) -> String {
        String(format: "%.1f", value)
    }
}
