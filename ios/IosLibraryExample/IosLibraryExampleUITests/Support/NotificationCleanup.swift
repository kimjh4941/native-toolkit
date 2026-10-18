//
//  NotificationCleanup.swift
//  IosLibraryExampleUITests
//
//  The two cleanups of the notification tests (UI test design U-15). Trusted Support file.
//
//  - `inApp`: removes the sample's delivered and scheduled notifications through its own buttons
//    and waits until both lists are empty (U-6). Needs no category.
//  - `springboard`: leaves an expanded banner by going home. The base calls it only when the gate
//    passed and the test received a `SystemUIToken`.
//

import Foundation

enum NotificationCleanup {

    static let reflectTimeout: TimeInterval = 10
    static let pollInterval: TimeInterval = 0.5

    /// The sample must show the Notification screen.
    static func inApp(_ sample: SampleApp) throws {
        try tapAndWait(sample, .removeAllDelivered)
        try tapAndWait(sample, .cancelAllScheduled)
        try waitEmpty(sample, .getDelivered, marker: "[getDelivered]")
        try waitEmpty(sample, .getScheduled, marker: "[getScheduled]")
    }

    static func springboard(_ token: SystemUIToken) throws {
        try Springboard(token).goHome()
    }

    private static func tapAndWait(_ sample: SampleApp, _ button: NotificationButton) throws {
        let before = try sample.updateCount(.notification)
        try sample.tap(button)
        try sample.waitForUpdateCount(.notification, before + 1)
    }

    /// Reads `GetDelivered` / `GetScheduled` every 0.5 s until `count: 0, ids: []` (10 s at most).
    private static func waitEmpty(_ sample: SampleApp, _ button: NotificationButton, marker: String) throws {
        let expected = ResultLine.expected(success: true, "\(marker) count: 0, ids: []")
        let deadline = Date().addingTimeInterval(reflectTimeout)
        while true {
            try tapAndWait(sample, button)
            let text = try sample.resultText(.notification)
            if text == expected { return }
            guard Date() < deadline else {
                throw SampleUITestError("\(marker) did not become empty: \(text)")
            }
            Thread.sleep(forTimeInterval: pollInterval)
        }
    }
}
