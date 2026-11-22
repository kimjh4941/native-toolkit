//
//  NotificationScreen.swift
//  MacLibraryExampleUITests
//
//  Steps on the sample's Notification screen shared by the Notification test classes (UI test
//  design 5.3, U-3, U-6, U-14 (c)). Trusted Support file. Presses go through `SampleApp` (the check
//  before every press, the token-taking entry points); this file only orders them and reads the
//  results.
//

import XCTest
import Foundation

struct NotificationScreen {

    let sample: SampleApp

    init(_ sample: SampleApp) {
        self.sample = sample
    }

    /// Re-press interval and how long a reflection may take (U-6, design 6.2).
    static let repressInterval: TimeInterval = 0.5
    static let reflectionTimeout: TimeInterval = 10

    // MARK: One press, one result (U-3)

    /// Presses a button that needs no token and returns the text of its result.
    @discardableResult
    func run(_ button: NotificationButton, quiet: Bool = true) throws -> String {
        try run(marker: button.resultMarker, quiet: quiet) { try sample.tap(button) }
    }

    @discardableResult
    func run(_ button: NotificationButton, _ token: NotificationToken, marker: String? = nil,
             quiet: Bool = true) throws -> String {
        try run(marker: marker ?? button.resultMarker, quiet: quiet) { try sample.tap(button, token) }
    }

    @discardableResult
    func run(_ button: NotificationButton, _ token: SettingsToken) throws -> String {
        try run(marker: button.resultMarker, quiet: true) { try sample.tap(button, token) }
    }

    @discardableResult
    func run(_ button: NotificationButton, _ badge: BadgeToken, _ token: NotificationToken) throws -> String {
        try run(marker: button.resultMarker, quiet: true) { try sample.tap(button, badge, token) }
    }

    /// A press whose banner comes at once (ShowImmediate, UpdateById): the result, then the root
    /// (waited for right after the result: on the VM a root looked for only after the 2-second
    /// check was sometimes already gone. Stage 0c 2.3), then the 2-second check for an extra result.
    func runShowing(_ button: NotificationButton, _ token: NotificationToken, center: NotificationCenterUI,
                    anchor: BannerAnchor) throws -> (text: String, root: NotificationRoot) {
        let before = try sample.resultSequence(.notification)
        try sample.tap(button, token)
        let text = try sample.waitForNextResult(.notification, after: before, marker: button.resultMarker)
        let root = try center.waitForRoot(anchor, timeout: SampleApp.elementTimeout)
        try sample.expectNoFurtherResult(.notification, sequence: before + 1)
        return (text, root)
    }

    /// Records the number, presses, waits for exactly the next result with `marker` and, when
    /// `quiet`, sees no further result for 2 seconds.
    private func run(marker: String, quiet: Bool, press: () throws -> Void) throws -> String {
        let before = try sample.resultSequence(.notification)
        try press()
        let text = try sample.waitForNextResult(.notification, after: before, marker: marker)
        if quiet {
            try sample.expectNoFurtherResult(.notification, sequence: before + 1)
        }
        return text
    }

    // MARK: Lists (U-6)

    /// Presses GetScheduled or GetDelivered until the list satisfies `accept`, one press at a time
    /// (each result is exactly the next number), 0.5 s apart, for up to 10 s. Only the last result
    /// gets the 2-second check for an extra completion (U-14 (a)).
    @discardableResult
    func pollList(_ button: NotificationButton, timeout: TimeInterval = NotificationScreen.reflectionTimeout,
                  maxPresses: Int = .max, quiet: Bool = true,
                  until accept: (NotificationIDList) -> Bool) throws -> NotificationIDList {
        guard button == .getScheduled || button == .getDelivered else {
            throw SampleUITestError(.notificationList, "\(button.rawValue) does not list notifications")
        }
        let label = String(button.resultMarker.dropFirst().dropLast(2))
        let deadline = Date().addingTimeInterval(timeout)
        var last: String = ""
        var presses = 0
        while true {
            presses += 1
            let before = try sample.resultSequence(.notification)
            try sample.tap(button)
            let text = try sample.waitForNextResult(.notification, after: before, marker: button.resultMarker)
            let prefix = ResultLine.expected(success: true, "")
            guard text.hasPrefix(prefix),
                  let list = NotificationIDList.parse(String(text.dropFirst(prefix.count)), label: label) else {
                throw SampleUITestError(.notificationList, "\(label) result has another shape: \(text)")
            }
            last = text
            if accept(list) {
                if quiet {
                    try sample.expectNoFurtherResult(.notification, sequence: before + 1)
                }
                return list
            }
            guard Date() < deadline, presses < maxPresses else {
                throw SampleUITestError(.notificationList, "\(label) did not reach the expected ids in \(timeout)s: \(last)")
            }
            Thread.sleep(forTimeInterval: Self.repressInterval)
        }
    }

    /// When the last press was clicked: the start of a trigger's time.
    func lastClickTime() throws -> Date {
        guard let date = sample.lastClickAt else {
            throw SampleUITestError(.notificationState, "no click has been made")
        }
        return date
    }

    /// What is left of `total` seconds counted from `start` (at least 0.1 s, so a late check still
    /// looks once).
    static func timeLeft(since start: Date, total: TimeInterval) -> TimeInterval {
        max(0.1, total - Date().timeIntervalSince(start))
    }

    // MARK: Seconds window (U-14 (c))

    /// Waits until the clock's second is in [5, 30) before a +1 minute press.
    func waitForSecondsWindow(now: () -> Date = Date.init) throws {
        let second = Self.secondOfMinute(now())
        let delay = SecondsWindow.delay(fromSecond: second)
        guard delay <= SecondsWindow.deadline else {
            throw SampleUITestError(.secondsWindow, "the computed wait \(delay)s is over the deadline")
        }
        if delay > 0 {
            Thread.sleep(forTimeInterval: delay)
        }
        guard SecondsWindow.contains(second: Self.secondOfMinute(now())) else {
            throw SampleUITestError(.secondsWindow, "the clock is not in the window after waiting")
        }
        try sample.session.checkInterruption()
    }

    static func secondOfMinute(_ date: Date) -> Double {
        let components = Calendar.current.dateComponents([.second, .nanosecond], from: date)
        return Double(components.second ?? 0) + Double(components.nanosecond ?? 0) / 1_000_000_000
    }

    // MARK: Last event

    /// Waits until the last event has `expected.sequence` (or more, which fails at once) and matches.
    func waitForEvent(_ expected: ExpectedEvent, timeout: TimeInterval = SampleApp.elementTimeout) throws {
        let deadline = Date().addingTimeInterval(timeout)
        while true {
            let event = try sample.lastEvent()
            if event.sequence > expected.sequence {
                throw SampleUITestError(.lastEvent, "the last event passed #\(expected.sequence): #\(event.sequence)")
            }
            if event.sequence == expected.sequence {
                guard expected.matches(event) else {
                    throw SampleUITestError(.lastEvent, "the last event #\(event.sequence) is not the expected one: kind=\(event.kind) actionId=\(event.actionId)")
                }
                return
            }
            guard Date() < deadline else {
                throw SampleUITestError(.lastEvent, "the last event stayed at #\(event.sequence)")
            }
            Thread.sleep(forTimeInterval: 0.1)
        }
    }

    /// The last event stays at `sequence` for 2 seconds (U-3, U-14 (a)).
    func expectNoFurtherEvent(sequence: Int) throws {
        let deadline = Date().addingTimeInterval(SampleApp.quietPeriod)
        repeat {
            let event = try sample.lastEvent()
            guard event.sequence == sequence else {
                throw SampleUITestError(.lastEvent, "the last event moved from #\(sequence) to #\(event.sequence)")
            }
            Thread.sleep(forTimeInterval: 0.1)
        } while Date() < deadline
        try sample.session.checkInterruption()
    }
}
