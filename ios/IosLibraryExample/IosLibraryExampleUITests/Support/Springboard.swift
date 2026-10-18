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

    private let springboard = XCUIApplication(bundleIdentifier: SystemLabels.springboardBundleIdentifier)
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

    /// Waits until the sample's banner `title` / `body` has gone. Returns false when it is still
    /// shown after `timeout`.
    func waitForBannerToVanish(title: String, body: String, timeout: TimeInterval) throws -> Bool {
        let gone = bannerQuery(title: title, body: body).firstMatch.waitForNonExistence(timeout: timeout)
        try session.checkInterruption()
        return gone
    }

    /// Any banner of the sample (identifier and the anchored app name only. 3.0).
    private var anySampleBanner: XCUIElementQuery {
        springboard.descendants(matching: .any).matching(NSPredicate(
            format: "identifier == %@ AND label BEGINSWITH[c] %@",
            SystemLabels.notificationShortLook,
            "\(SystemLabels.sampleDisplayName), "
        ))
    }

    /// Waits until no banner of the sample is shown. Returns false when one is still shown.
    func waitForNoSampleBanner(timeout: TimeInterval) -> Bool {
        anySampleBanner.firstMatch.waitForNonExistence(timeout: timeout)
    }

    func tapBanner(title: String, body: String) throws {
        try exactlyOne(bannerQuery(title: title, body: body), "sample banner").tap()
        try session.checkInterruption()
    }

    /// Long-presses the banner so that it expands (U-5: no drag on the device).
    func longPressBanner(title: String, body: String) throws {
        try exactlyOne(bannerQuery(title: title, body: body), "sample banner").press(forDuration: Self.longPressDuration)
        try session.checkInterruption()
    }

    // MARK: Expanded notification (design 3.0, 8.1)

    /// The expanded (long-pressed) notification, measured on the iOS 26.2 simulator in stage 0c:
    /// an element with the identifier `notification-expanded-view` holds the content (its button
    /// `ShortLook.Platter.Content.Seamless` is labeled `<time>, <title>, <body>`, without the app
    /// name), and a full-screen banner-notification element holds both that view and the action
    /// buttons. That element type has no public name in `XCUIElement.ElementType` (raw value 83,
    /// shown as `BannerNotification`), so it is matched by the raw value.
    private static let bannerNotificationElementType: UInt = 83

    private var expandedViews: XCUIElementQuery {
        springboard.descendants(matching: .any).matching(identifier: SystemLabels.notificationExpandedView)
    }

    /// The root that holds the expanded notification and its actions. When the full-screen banner
    /// element is not found exactly once (for example on an OS version not measured), the whole
    /// springboard is the scope, and every element is still taken with exactly one match (3.0).
    private func expandedScope() -> XCUIElement {
        let roots = springboard.descendants(matching: .any)
            .matching(NSPredicate(format: "elementType == %lu", Self.bannerNotificationElementType))
            .containing(.any, identifier: SystemLabels.notificationExpandedView)
        return roots.count == 1 ? roots.element : springboard
    }

    /// Long-presses the sample's banner and waits for the expanded view of that notification
    /// (the marker that it expanded). Throws when it did not expand or shows another notification.
    func expandBanner(title: String, body: String, timeout: TimeInterval = Springboard.actionTimeout) throws {
        try longPressBanner(title: title, body: body)
        guard expandedViews.firstMatch.waitForExistence(timeout: timeout) else {
            throw SampleUITestError("the sample banner did not expand")
        }
        let view = try exactlyOne(expandedViews, "expanded notification")
        let content = view.descendants(matching: .any).matching(NSPredicate(
            format: "identifier == %@ AND label ENDSWITH %@",
            SystemLabels.expandedContent,
            ", \(title), \(body)"
        ))
        _ = try exactlyOne(content, "content of the expanded sample notification")
        try session.checkInterruption()
    }

    /// Whether the expanded view is shown now (no wait).
    var isExpanded: Bool { expandedViews.count > 0 }

    /// Waits for and taps an action button (`Open` / `Delete` / `Reply`) of the expanded
    /// notification, with exactly one match inside its scope.
    func tapAction(_ label: String, timeout: TimeInterval = Springboard.actionTimeout) throws {
        let query = expandedScope().buttons.matching(identifier: label)
        guard query.firstMatch.waitForExistence(timeout: timeout) else {
            throw SampleUITestError("notification action \(label) did not appear")
        }
        try exactlyOne(query, "notification action \(label)").tap()
        try session.checkInterruption()
    }

    /// Waits until each of `labels` is shown exactly once in the expanded notification's scope.
    func waitForActions(_ labels: [String], timeout: TimeInterval = Springboard.actionTimeout) throws {
        let deadline = Date().addingTimeInterval(timeout)
        for label in labels {
            let query = expandedScope().buttons.matching(identifier: label)
            guard query.firstMatch.waitForExistence(timeout: max(0.1, deadline.timeIntervalSinceNow)) else {
                throw SampleUITestError("notification action \(label) did not appear in \(timeout)s")
            }
            _ = try exactlyOne(query, "notification action \(label)")
        }
        try session.checkInterruption()
    }

    /// Number of buttons labeled one of `labels` in the expanded notification's scope (no wait).
    func actionCount(_ labels: [String]) -> Int {
        expandedScope().buttons.matching(NSPredicate(format: "label IN %@", labels)).count
    }

    /// Types into the reply text view (a TextView with the sample's placeholder `Type a message`;
    /// the expanded content has other text views) and taps `Send`.
    func sendReply(_ text: String, placeholder: String = "Type a message") throws {
        let fields = springboard.textViews.matching(NSPredicate(format: "placeholderValue == %@", placeholder))
        guard fields.firstMatch.waitForExistence(timeout: Self.actionTimeout) else {
            throw SampleUITestError("reply text view did not appear")
        }
        try exactlyOne(fields, "reply text view").typeText(text)
        try session.checkInterruption()
        let send = springboard.buttons.matching(identifier: "Send")
        guard send.firstMatch.waitForExistence(timeout: Self.actionTimeout) else {
            throw SampleUITestError("Send did not appear")
        }
        try exactlyOne(send, "Send").tap()
        try session.checkInterruption()
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

    var isSettingsForeground: Bool { settings.state == .runningForeground }

    func waitForSettingsForeground(timeout: TimeInterval) -> Bool {
        settings.wait(for: .runningForeground, timeout: timeout)
    }

    // MARK: Home screen icon badge (N34)

    /// The accessibility value of the sample's home screen icon (`1 new item` with badge 1 and
    /// `""` without a badge on the iOS 26.2 simulator, en). Exactly one icon must match.
    func sampleIconValue() throws -> String {
        let icons = springboard.icons.matching(identifier: SystemLabels.sampleDisplayName)
        guard icons.firstMatch.waitForExistence(timeout: Self.alertTimeout) else {
            throw SampleUITestError("the sample's home screen icon was not found")
        }
        let value = try exactlyOne(icons, "sample icon").value as? String ?? ""
        try session.checkInterruption()
        return value
    }

    // MARK: Simulator diagnostics

    /// Hierarchy of springboard for a failure analysis. Simulator only.
    func debugDescriptionOnSimulator() -> String {
        session.isDevice ? "(not written on the device)" : springboard.debugDescription
    }
}
