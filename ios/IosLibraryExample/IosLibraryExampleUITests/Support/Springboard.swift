//
//  Springboard.swift
//  IosLibraryExampleUITests
//
//  Springboard operations (UI test design 6.1): the sample's notification banner, its actions,
//  permission and paste alerts, the home screen and the Settings app. Every entry point needs a
//  `SystemUIToken` (U-9). Trusted Support file.
//
//  On the device no hierarchy dump is written and failure messages carry no springboard label.
//  The one exception, approved by the user for N5, is `waitForBannerNotingSampleNotifications`:
//  it writes only the sample's name, the expected title and body as `<app>` / `<title>` /
//  `<body>`, and the length of anything else (stage 0e working notes 11.4).
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

    /// Like `waitForBanner`, and also returns a note of the springboard elements whose label
    /// starts with `IosLibraryExample, ` seen while waiting, for N5's failure message (the device
    /// does not find a banner that the user sees; stage 0e working notes 11.4). The note never
    /// carries other text: each label is split at `, ` and only parts equal to the sample's name,
    /// `title` or `body` are written (`<app>`, `<title>`, `<body>`); any other part is written as
    /// its length (`<12>`). Identifiers are written only when known, otherwise as their length.
    /// Reads only. At most four distinct entries of at most six parts each (more parts end in
    /// `…`), so that the runner's 300-character cut of a failure message keeps them in practice.
    func waitForBannerNotingSampleNotifications(title: String, body: String, timeout: TimeInterval) throws -> (found: Bool, note: String) {
        let sampleNamed = springboard.descendants(matching: .any).matching(NSPredicate(
            format: "label BEGINSWITH[c] %@", "\(SystemLabels.sampleDisplayName), "
        ))
        let knownIdentifiers = [
            SystemLabels.notificationShortLook, SystemLabels.notificationExpandedView, SystemLabels.expandedContent,
        ]
        func masked(_ part: String) -> String {
            if part.caseInsensitiveCompare(SystemLabels.sampleDisplayName) == .orderedSame { return "<app>" }
            if part == title { return "<title>" }
            if part == body { return "<body>" }
            return "<\(part.count)>"
        }
        var seen: [String] = []
        let deadline = Date().addingTimeInterval(timeout)
        while true {
            if bannerQuery(title: title, body: body).count > 0 {
                try session.checkInterruption()
                _ = try exactlyOne(bannerQuery(title: title, body: body), "sample banner")
                return (true, "")
            }
            let remaining = deadline.timeIntervalSinceNow
            if remaining <= 0 { break }
            for element in sampleNamed.allElementsBoundByIndex where seen.count < 4 {
                guard let snapshot = try? element.snapshot() else { continue }
                let identifier = knownIdentifiers.contains(snapshot.identifier)
                    ? snapshot.identifier : "<\(snapshot.identifier.count)>"
                let components = snapshot.label.components(separatedBy: ", ")
                let parts = components.prefix(6).map(masked) + (components.count > 6 ? ["…"] : [])
                let entry = "\(identifier): \(parts.joined(separator: ", "))"
                if !seen.contains(entry) { seen.append(entry) }
            }
            Thread.sleep(forTimeInterval: min(0.25, max(remaining, 0)))
        }
        try session.checkInterruption()
        return (false, "sample-named elements seen: \(seen.isEmpty ? "none" : seen.joined(separator: " | "))")
    }

    /// Waits until no banner of the sample is shown. Returns false when one is still shown.
    /// Throws when the interruption monitor marked the test while waiting.
    func waitForNoSampleBanner(timeout: TimeInterval) throws -> Bool {
        let gone = anySampleBanner.firstMatch.waitForNonExistence(timeout: timeout)
        try session.checkInterruption()
        return gone
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

    /// The root that holds the expanded notification and its actions. It must be found exactly
    /// once, and its expanded view must show exactly one content of the sample's notification
    /// `<title>` / `<body>`; otherwise nothing is pressed (an OS that is not measured fails instead
    /// of searching the whole springboard, and a root that shows another notification is not the
    /// sample's. Stage 0d review R-1, R-21). Taken again before every press.
    private func expandedScope(title: String, body: String) throws -> XCUIElement {
        let roots = springboard.descendants(matching: .any)
            .matching(NSPredicate(format: "elementType == %lu", Self.bannerNotificationElementType))
            .containing(.any, identifier: SystemLabels.notificationExpandedView)
        let root = try exactlyOne(roots, "root of the expanded notification")
        let view = try exactlyOne(root.descendants(matching: .any).matching(identifier: SystemLabels.notificationExpandedView),
                                  "expanded view in the root")
        _ = try exactlyOne(view.descendants(matching: .any).matching(NSPredicate(
            format: "identifier == %@ AND label ENDSWITH %@", SystemLabels.expandedContent, ", \(title), \(body)"
        )), "content of the expanded sample notification")
        return root
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
    func tapAction(_ label: String, title: String, body: String, timeout: TimeInterval = Springboard.actionTimeout) throws {
        let query = try expandedScope(title: title, body: body).buttons.matching(identifier: label)
        guard query.firstMatch.waitForExistence(timeout: timeout) else {
            throw SampleUITestError("notification action \(label) did not appear")
        }
        let button = try exactlyOne(try expandedScope(title: title, body: body).buttons.matching(identifier: label),
                                    "notification action \(label)")
        button.tap()
        try session.checkInterruption()
    }

    /// Waits until each of `labels` is shown exactly once in the expanded notification's scope.
    func waitForActions(_ labels: [String], title: String, body: String,
                        timeout: TimeInterval = Springboard.actionTimeout) throws {
        let deadline = Date().addingTimeInterval(timeout)
        for label in labels {
            let query = try expandedScope(title: title, body: body).buttons.matching(identifier: label)
            guard query.firstMatch.waitForExistence(timeout: max(0.1, deadline.timeIntervalSinceNow)) else {
                throw SampleUITestError("notification action \(label) did not appear in \(timeout)s")
            }
            _ = try exactlyOne(query, "notification action \(label)")
        }
        try session.checkInterruption()
    }

    /// Number of buttons labeled one of `labels` in the expanded notification's scope (no wait).
    func actionCount(_ labels: [String], title: String, body: String) throws -> Int {
        try expandedScope(title: title, body: body).buttons.matching(NSPredicate(format: "label IN %@", labels)).count
    }

    /// Types into the reply text view and taps `Send`, both inside the reply window of the
    /// sample's notification `<title>` / `<body>`.
    ///
    /// After Reply, the text view and Send are not inside the expanded notification's root: they
    /// are in a window of their own (measured on the iOS 26.2 simulator in stage 0d; no element of
    /// it has an identifier). That window is the scope: exactly one springboard window holding a
    /// text view with the sample's own placeholder (`SystemLabels.sampleReplyPlaceholder`, set by
    /// the sample's category and used by nothing else), or with the typed text after typing, and
    /// exactly one text view and one `Send` inside it. The root of the sample's expanded
    /// notification and the reply window are taken again before typing and before Send; when
    /// either cannot be shown to be the sample's, nothing is typed or pressed (review R-21).
    func sendReply(_ text: String, title: String, body: String) throws {
        let placeholder = SystemLabels.sampleReplyPlaceholder
        let beforeTyping = NSPredicate(format: "elementType == %lu AND placeholderValue == %@",
                                       XCUIElement.ElementType.textView.rawValue, placeholder)
        let afterTyping = NSPredicate(format: "elementType == %lu AND (placeholderValue == %@ OR value == %@)",
                                      XCUIElement.ElementType.textView.rawValue, placeholder, text)
        let windows = springboard.windows.containing(beforeTyping)
        guard windows.firstMatch.waitForExistence(timeout: Self.actionTimeout) else {
            throw SampleUITestError("reply text view of the sample did not appear")
        }
        _ = try expandedScope(title: title, body: body)
        let scope = try exactlyOne(windows, "reply window")
        let send = scope.buttons.matching(identifier: "Send")
        guard send.firstMatch.waitForExistence(timeout: Self.actionTimeout) else {
            throw SampleUITestError("Send did not appear")
        }
        _ = try exactlyOne(send, "Send")
        try exactlyOne(scope.textViews.matching(beforeTyping), "reply text view").typeText(text)
        try session.checkInterruption()
        _ = try expandedScope(title: title, body: body)
        let typed = try exactlyOne(springboard.windows.containing(afterTyping), "reply window")
        _ = try exactlyOne(typed.textViews.matching(afterTyping), "reply text view")
        let sendAfterTyping = typed.buttons.matching(identifier: "Send")
        guard sendAfterTyping.firstMatch.waitForExistence(timeout: Self.actionTimeout) else {
            throw SampleUITestError("Send did not appear after typing")
        }
        try exactlyOne(sendAfterTyping, "Send").tap()
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

    /// Presses one of `labels` (en / ja) on the only springboard alert, after checking that the
    /// alert names the sample; exactly one button must match. The label is checked again right
    /// before the press, and the press is refused when another alert appeared (stage 0d review R-2).
    func tapAlertButton(_ labels: [String]) throws {
        try tapAlertButton(labels) { $0.contains(SystemLabels.quotedSampleDisplayName) }
    }

    /// Presses one of `labels` on the paste alert only when `pasteAlertNamesKnownSource` accepts its
    /// label: content that came from another device (Universal Clipboard) names that device and
    /// is not allowed (stage 0d review R-3).
    func tapPasteAlertFromKnownSource(_ labels: [String]) throws {
        try tapAlertButton(labels, accepting: Self.pasteAlertNamesKnownSource)
    }

    /// The names quoted with `“` and `”` in `label`, in order. Nil when the quotes do not pair up
    /// (a quote inside a quote, an opening quote without its closing one, or the reverse).
    static func quotedNames(in label: String) -> [String]? {
        var names: [String] = []
        var current: String?
        for character in label {
            switch character {
            case "“":
                guard current == nil else { return nil }
                current = ""
            case "”":
                guard let name = current else { return nil }
                names.append(name)
                current = nil
            default:
                current?.append(character)
            }
        }
        return current == nil ? names : nil
    }

    /// Whether a paste alert's label is the sample pasting from the test runner or from itself.
    /// The label quotes exactly two names, the app first and the source second, in both languages:
    /// en `“IosLibraryExample” would like to paste from “IosLibraryExampleUITests-Runner”` (the
    /// iOS 26.2 simulator, stage 0c) and ja `“IosLibraryExample”に“IosLibraryExample”からペースト
    /// しようとしています` (the device, stage 0a 7.2: the source is the sample itself there). Any
    /// other source (a Mac's name from Universal Clipboard) or any other number of quoted names is
    /// refused. Mirrored by scripts/tests/test_ios_ui_runner.py (PasteAlert).
    static func pasteAlertNamesKnownSource(_ label: String) -> Bool {
        guard let names = quotedNames(in: label), names.count == 2 else { return false }
        return names[0] == SystemLabels.sampleDisplayName
            && [SystemLabels.runnerDisplayName, SystemLabels.sampleDisplayName].contains(names[1])
    }

    private func tapAlertButton(_ labels: [String], accepting accept: (String) -> Bool) throws {
        let alert = try exactlyOne(springboard.alerts, "springboard alert")
        let label = alert.label
        guard accept(label) else {
            throw SampleUITestError(session.isDevice
                ? "the springboard alert is not the expected alert of the sample; nothing was pressed"
                : "the springboard alert is not the expected alert of the sample; nothing was pressed: \(label)")
        }
        let button = try exactlyOne(alert.buttons.matching(NSPredicate(format: "label IN %@", labels)), "alert button")
        // Pressed only while that alert is still the only one and still accepted.
        guard springboard.alerts.count == 1, accept(alert.label) else {
            throw SampleUITestError("the springboard alert changed before the press; nothing was pressed")
        }
        button.tap()
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
