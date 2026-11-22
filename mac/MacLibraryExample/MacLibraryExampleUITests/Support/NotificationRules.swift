//
//  NotificationRules.swift
//  MacLibraryExampleUITests
//
//  The pure rules of the Notification tests (UI test design 4.3, 5.0, 5.3, U-5, U-6, U-14 (c),
//  U-21), kept as functions of their inputs so that `SupportRuleTests` can check and break them
//  without launching anything. Trusted Support file.
//

import Foundation
import CoreGraphics

// MARK: - Banner root (U-2, U-5)

/// The label of the sample's banner root: `<app>, <title>, <app>, <body>` (app name, title,
/// subtitle, body; the sample's subtitle is its app name. Design 5.3). Compared whole, so a stacked
/// or another app's notification with the same title never matches.
struct BannerAnchor: Equatable {
    let title: String
    let body: String

    static let appName = "MacLibraryExample"

    var label: String {
        let separator = SystemLabels.notificationLabelSeparator
        return Self.appName + separator + title + separator + Self.appName + separator + body
    }

    /// Every root of the sample starts with this.
    static var anyRootPrefix: String { appName + SystemLabels.notificationLabelSeparator }

    func matches(_ label: String) -> Bool { label == self.label }

    // The sample's notifications (`NotificationSampleView`).
    static let immediate = BannerAnchor(title: "Immediate Notification", body: "Displayed now")
    static let tenSeconds = BannerAnchor(title: "10s Notification", body: "Will be shown after 10 seconds")
    static let calendar = BannerAnchor(title: "Calendar Notification", body: "Will be shown in one minute")
    static let updated = BannerAnchor(title: "Updated Notification", body: "This content was updated")
    static let scheduled = BannerAnchor(title: "Scheduled Notification", body: "Scheduled in 10 seconds")
    static let scheduledCalendar = BannerAnchor(title: "Scheduled Calendar", body: "Scheduled by calendar")
}

/// The sample's notification identifiers and texts (`NotificationSampleView`).
enum SampleNotification {
    static let notificationId = "mac-sample-notification"
    static let scheduledId = "mac-sample-scheduled"
    static let openAction = "open"
    static let replyAction = "reply"
    /// The titles of the category's actions.
    static let openTitle = "Open"
    static let replyTitle = "Reply"
    static let registeredText = "[registerCategory] Registered. Send a notification and hover over the notification banner and click Options (▼) to see Open / Reply."
}

// MARK: - Last event (design 4.3)

/// `notification.lastEvent`: `#<n> kind=<k> notificationId=<id> actionId=<id> userText=<t|-> userInfo=<...>`.
struct LastEvent: Equatable {
    let sequence: Int
    let kind: String
    let notificationId: String
    let actionId: String
    let userText: String
    let userInfo: String

    static func parse(_ value: String) -> LastEvent? {
        guard let shown = ResultLine.parse(value) else { return nil }
        let pattern = "^kind=(\\S+) notificationId=(\\S+) actionId=(\\S+) userText=(.*) userInfo=(\\S+)$"
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(in: shown.text, range: NSRange(shown.text.startIndex..., in: shown.text)),
              match.numberOfRanges == 6 else { return nil }
        func group(_ index: Int) -> String {
            guard let range = Range(match.range(at: index), in: shown.text) else { return "" }
            return String(shown.text[range])
        }
        return LastEvent(sequence: shown.sequence, kind: group(1), notificationId: group(2), actionId: group(3),
                         userText: group(4), userInfo: group(5))
    }

    static let initialText = "kind=none notificationId=- actionId=- userText=- userInfo=-"
}

/// What a test expects of the last event. The notification id is either exact or the id of
/// ShowImmediate (`mac-sample-notification-<digits>`. U-1); the user info is derived from it.
struct ExpectedEvent {
    enum NotificationID {
        case exact(String)
        case immediate
    }

    let sequence: Int
    let kind: String
    let notificationId: NotificationID
    let actionId: String
    let userText: String

    static let defaultAction = "com.apple.UNNotificationDefaultActionIdentifier"
    static let immediatePattern = "^mac-sample-notification-[0-9]+$"

    /// Whether `event` is this one: every field in full, the user info as the sample sends it
    /// (`id:<notification id>,source:MacLibraryExample`, sorted by key).
    func matches(_ event: LastEvent) -> Bool {
        guard event.sequence == sequence, event.kind == kind, event.actionId == actionId,
              event.userText == userText else { return false }
        switch notificationId {
        case .exact(let id):
            guard event.notificationId == id else { return false }
        case .immediate:
            guard event.notificationId.range(of: Self.immediatePattern, options: .regularExpression) != nil else {
                return false
            }
        }
        return event.userInfo == "id:\(event.notificationId),source:\(BannerAnchor.appName)"
    }
}

// MARK: - Launch copy (U-21)

enum LaunchCopy {
    /// `copy=<12 lowercase hex digits>`.
    static func isWellFormed(_ value: String) -> Bool {
        value.range(of: "^copy=[0-9a-f]{12}$", options: .regularExpression) != nil
    }
}

// MARK: - Scheduled and delivered lists (U-6)

/// `[getScheduled] count=<n>, ids=[<id>, ...]` and the same for `getDelivered`.
struct NotificationIDList: Equatable {
    let count: Int
    let ids: [String]

    /// Parses `body` (the text after `Result: `) for `label` (`getScheduled` or `getDelivered`).
    /// nil unless the shape is exact, the count equals the number of ids and no id repeats.
    static func parse(_ body: String, label: String) -> NotificationIDList? {
        let prefix = "[\(label)] count="
        guard body.hasPrefix(prefix) else { return nil }
        let rest = body.dropFirst(prefix.count)
        guard let comma = rest.range(of: ", ids=["), rest.hasSuffix("]") else { return nil }
        let digits = rest[rest.startIndex..<comma.lowerBound]
        guard !digits.isEmpty, digits.allSatisfy({ $0.isASCII && $0.isNumber }), let count = Int(digits) else {
            return nil
        }
        let inner = rest[comma.upperBound..<rest.index(before: rest.endIndex)]
        let ids = inner.isEmpty ? [] : inner.components(separatedBy: ", ")
        guard ids.count == count, Set(ids).count == ids.count, !ids.contains(where: \.isEmpty) else { return nil }
        return NotificationIDList(count: count, ids: ids)
    }

    /// Whether the ids are exactly `expected`, where `immediate` stands for one id of ShowImmediate.
    func hasExactly(_ expected: [String], immediate: Int = 0) -> Bool {
        let fixed = ids.filter { $0.range(of: ExpectedEvent.immediatePattern, options: .regularExpression) == nil }
        let immediates = ids.count - fixed.count
        return Set(fixed) == Set(expected) && fixed.count == expected.count && immediates == immediate
    }
}

// MARK: - Seconds window (U-14 (c))

/// The sample's +1 minute triggers cut the seconds to 0, so a press is made only while the clock's
/// second is in [5, 30): the notification then fires 30〜55 seconds later.
enum SecondsWindow {
    static let start: Double = 5
    static let end: Double = 30
    /// A wait is not started this close to the end: the clock moves on between reading it and the
    /// press (the VM read 30.0 right after reading 29.9x. Stage 0c 2.3).
    static let margin: Double = 1
    /// The longest wait (from second 29.0 to the next 5) is 36 s; the deadline is 40 s.
    static let deadline: TimeInterval = 40

    /// How long to wait from `second` (0 ≤ second < 60, with fractions) until the window opens.
    static func delay(fromSecond second: Double) -> TimeInterval {
        if second >= start && second < end - margin { return 0 }
        if second < start { return start - second }
        return 60 - second + start
    }

    static func contains(second: Double) -> Bool {
        second >= start && second < end
    }
}

// MARK: - Overlay before pressing Notification Center (design 5.0)

/// What a press inside Notification Center hits.
enum NotificationPressKind: Equatable {
    /// The body or `Options` of a banner root (also the permission prompt's root), with the root's
    /// frame now.
    case banner(rootFrame: CGRect)
    /// An item of the menu that the root's `Options` opened.
    case menuItem
}

enum NotificationOverlayRule {

    /// Windows that take no click here: transparent ones, the cursor level and above, and the
    /// full-display windows of the fixed owners other than Notification Center (Notification Center's
    /// full-display window is where the banners are drawn on 15.8.3).
    static func isPassive(_ window: ScreenWindow, displays: [CGRect]) -> Bool {
        if window.alpha <= 0 { return true }
        if window.layer >= OverlayRule.cursorLayer { return true }
        if let owner = window.owner, owner != SystemLabels.notificationCenterBundleIdentifier,
           SystemLabels.passiveFullDisplayOwners.contains(owner), displays.contains(window.bounds) {
            return true
        }
        return false
    }

    /// `windows` front to back. Banner: the frontmost window at the point belongs to Notification
    /// Center and is the only Notification Center window that holds the whole root (another window
    /// of the same owner in front of the point, or two windows that both hold the root, stop the
    /// press). Menu item: the frontmost window at the point belongs to Notification Center.
    static func verdict(point: CGPoint, kind: NotificationPressKind, windows: [ScreenWindow],
                        displays: [CGRect]) -> OverlayVerdict {
        let active = windows.filter { !isPassive($0, displays: displays) }
        guard let hit = active.first(where: { $0.bounds.contains(point) }) else { return .noWindow }
        guard hit.owner == SystemLabels.notificationCenterBundleIdentifier else { return .blocked }
        switch kind {
        case .menuItem:
            return .clear
        case .banner(let rootFrame):
            guard rootFrame.width > 0, rootFrame.height > 0, rootFrame.contains(point) else { return .blocked }
            let holders = active.filter {
                $0.owner == SystemLabels.notificationCenterBundleIdentifier && $0.bounds.contains(rootFrame)
            }
            return holders.count == 1 && holders[0] == hit ? .clear : .blocked
        }
    }
}
