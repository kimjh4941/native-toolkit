//
//  Springboard.swift
//  IosLibraryExampleUITests
//
//  Springboard operations (UI test design 6.1): the sample's notification banner, its actions,
//  permission and paste alerts, the home screen and the Settings app. Every entry point needs a
//  `SystemUIToken` (U-9). Trusted Support file.
//
//  On the device no hierarchy dump is written and failure messages carry no springboard label.
//

import XCTest
import Foundation

struct Springboard {

    private let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")
    private let settings = XCUIApplication(bundleIdentifier: "com.apple.Preferences")
    private let session: UITestSession

    static let alertTimeout: TimeInterval = 10
    static let actionTimeout: TimeInterval = 5
    static let longPressDuration: TimeInterval = 1.5

    init(_ token: SystemUIToken) {
        session = token.session
    }

    // MARK: Home

    func goHome() throws {
        XCUIDevice.shared.press(.home)
        try session.checkInterruption()
    }

    // MARK: Notification banner (design 3.0)

    /// The sample's banner: identifier `NotificationShortLookView`, the label starts with
    /// `IosLibraryExample, `, contains `, <title>, ` and ends with `, <body>`. Exactly one match.
    private func bannerQuery(title: String, body: String) -> XCUIElementQuery {
        springboard.descendants(matching: .any).matching(NSPredicate(
            format: "identifier == %@ AND label BEGINSWITH[c] %@ AND label CONTAINS %@ AND label ENDSWITH %@",
            SystemLabels.notificationShortLook,
            "\(SystemLabels.sampleDisplayName), ",
            ", \(title), ",
            ", \(body)"
        ))
    }

    /// Waits for the sample's banner. Returns false when it did not appear in `timeout`.
    func waitForBanner(title: String, body: String, timeout: TimeInterval) throws -> Bool {
        let found = bannerQuery(title: title, body: body).firstMatch.waitForExistence(timeout: timeout)
        try session.checkInterruption()
        if found {
            _ = try exactlyOne(bannerQuery(title: title, body: body), "sample banner")
        }
        return found
    }

    /// Whether the banner exists now (no wait).
    func bannerExists(title: String, body: String) -> Bool {
        bannerQuery(title: title, body: body).count > 0
    }

    func tapBanner(title: String, body: String) throws {
        try exactlyOne(bannerQuery(title: title, body: body), "sample banner").tap()
        try session.checkInterruption()
    }

    /// Long-presses the banner so that its actions appear (U-5: no drag on the device).
    func longPressBanner(title: String, body: String) throws {
        try exactlyOne(bannerQuery(title: title, body: body), "sample banner").press(forDuration: Self.longPressDuration)
        try session.checkInterruption()
    }

    /// Waits for and taps an action button (`Open` / `Delete` / `Reply`) of the expanded banner.
    /// The expanded platter's root element is not confirmed yet (design 8.1), so the button is
    /// taken from the whole springboard with exactly one match.
    func tapAction(_ label: String, timeout: TimeInterval = Springboard.actionTimeout) throws {
        let query = springboard.buttons.matching(identifier: label)
        guard query.firstMatch.waitForExistence(timeout: timeout) else {
            throw SampleUITestError("notification action \(label) did not appear")
        }
        try exactlyOne(query, "notification action \(label)").tap()
        try session.checkInterruption()
    }

    func actionExists(_ label: String) -> Bool {
        springboard.buttons.matching(identifier: label).count > 0
    }

    /// Types into the reply text view (placeholder `Type a message`) and taps `Send`.
    func sendReply(_ text: String) throws {
        let field = springboard.textViews.firstMatch
        guard field.waitForExistence(timeout: Self.actionTimeout) else {
            throw SampleUITestError("reply text view did not appear")
        }
        try exactlyOne(springboard.textViews, "reply text view").typeText(text)
        try tapAction("Send")
    }

    // MARK: Alerts

    /// Number of springboard alerts (U-8 (1)). Labels are not read.
    var alertCount: Int { springboard.alerts.count }

    /// Waits for a springboard alert. Returns false when none appeared.
    func waitForAlert(timeout: TimeInterval = Springboard.alertTimeout) -> Bool {
        springboard.alerts.firstMatch.waitForExistence(timeout: timeout)
    }

    /// Whether the only springboard alert's label contains the sample's quoted display name.
    func alertNamesSample() throws -> Bool {
        try exactlyOne(springboard.alerts, "springboard alert").label.contains(SystemLabels.quotedSampleDisplayName)
    }

    /// Presses one of `labels` (en / ja) on the only springboard alert; exactly one must match.
    func tapAlertButton(_ labels: [String]) throws {
        let alert = try exactlyOne(springboard.alerts, "springboard alert")
        try exactlyOne(alert.buttons.matching(NSPredicate(format: "label IN %@", labels)), "alert button").tap()
        try session.checkInterruption()
    }

    // MARK: Settings app (N3)

    func waitForSettingsForeground(timeout: TimeInterval) -> Bool {
        settings.wait(for: .runningForeground, timeout: timeout)
    }

    // MARK: Simulator diagnostics

    /// Hierarchy of springboard for a failure analysis. Simulator only.
    func debugDescriptionOnSimulator() -> String {
        session.isDevice ? "(not written on the device)" : springboard.debugDescription
    }
}
