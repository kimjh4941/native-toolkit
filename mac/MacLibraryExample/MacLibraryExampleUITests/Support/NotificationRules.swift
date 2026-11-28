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
    /// A wait aims this far inside the window, not at its edge: the sleep counts on the monotonic clock,
    /// and after a 35 s sleep the VM's wall clock read 4.998, 2 ms short of the window (stage 0d 17:
    /// N14b `secondsWindow`).
    static let aimInside: Double = 0.5
    /// The longest wait (from second 29.0 to the next 5.5) is 36.5 s; the deadline is 40 s.
    static let deadline: TimeInterval = 40

    /// How long to wait from `second` (0 ≤ second < 60, with fractions) until `aimInside` past the
    /// window's start.
    static func delay(fromSecond second: Double) -> TimeInterval {
        if second >= start && second < end - margin { return 0 }
        if second < start { return start + aimInside - second }
        return 60 - second + start + aimInside
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

// MARK: - Notification Center's groups around a press (2026-11-28; runner review v7: Codex B-1; CenterLayoutRule review v1)

/// One group Notification Center shows: its identifier (empty when it has none), its frame, and the identifier of
/// the nearest group above it in the snapshot that has one (`parent`; nil at the top). No label: the comparison never uses one (the root
/// itself is found by its whole label, `BannerAnchor`).
struct CenterGroup: Equatable {
    let identifier: String
    let frame: CGRect
    let parent: String?

    init(identifier: String, frame: CGRect, parent: String? = nil) {
        self.identifier = identifier
        self.frame = frame
        self.parent = parent
    }
}

/// What the reads of Notification Center's groups around one click can tell.
enum CenterPressVerdict: Equatable {
    /// Nothing the reads can see came, or grew where it may have come into another notification.
    case clear
    /// Right before the click the groups differ from the check's: nothing is pressed.
    case changed
    /// After the click a named group is there more times than before: a notification arrived.
    case arrived
    /// After the click the reads cannot tell a new group from an old one (a group without an identifier that
    /// is not where one was, or another notification's group that grew without a checked reason): not taken as
    /// safe.
    case cannotTell
}

/// One read of Notification Center after a click (settle review v1): its groups, when it was taken (seconds after the
/// click, monotonic), and the identifier of the expected banner when this same snapshot holds exactly one group with
/// the banner's whole label.
struct CenterRead: Equatable {
    let groups: [CenterGroup]
    let at: TimeInterval
    let expectedBanner: String?

    init(_ groups: [CenterGroup], at: TimeInterval = 0, expectedBanner: String? = nil) {
        self.groups = groups
        self.at = at
        self.expectedBanner = expectedBanner
    }
}

/// What was pressed and on which macOS (vm26 review v1 A-2): the exceptions seen on 26 apply only on 26 and only to the
/// press they were seen with; 15 keeps the strict comparison.
struct CenterPressContext: Equatable {
    enum Press: Equatable {
        case body, options, menuItem, promptOptions, promptAnswer
    }
    let press: Press
    let osMajor: Int
}

/// The comparison of `pressInCenter`, cut out so that `SupportRuleTests` gives it made-up reads. This is detection
/// in the VM, not a guard (UI tests never run on this Mac; D-21 revised 2026-11-28).
///
/// Not seen, by design of the reads (the limit `SupportRuleTests` lists): a notification that took the click and
/// went away before the read after it; a new notification that comes with the identifier, the frame and the size
/// of one that went away; a notification that merged into the last banner of the list exactly when the list
/// collapsed onto it (the same reads as the collapse); anything in the time between the last read and the event
/// XCTest synthesizes.
enum CenterLayoutRule {

    /// The identifiers of the list that holds the banners, as checked in the VM (15.8.3, 2026-11-28; 26 in U-30).
    /// Only such a group, holding banners before the click, may grow without being a notification.
    static let listIdentifiers: Set<String> = ["AXNotificationListItems"]


    /// Right before the click against the read when the check started: the same groups, each with the same
    /// identifier, exactly the same frame and the same parent (as a multiset: their order does not matter).
    /// Anything else is `changed`.
    static func beforeClick(atCheck: [CenterGroup], beforeClick: [CenterGroup]) -> CenterPressVerdict {
        sameGroups(atCheck, beforeClick) ? .clear : .changed
    }

    /// Right after the click against the read right before it. A right press may close the pressed banner, open
    /// a menu (not a group), make the pressed root grow with parts of its own (Reply), make the list grow, and
    /// make the list collapse onto its last banner, and leave the closing root without its identifier (26); it never
    /// brings a group. `pressedRoot` is the identifier of
    /// the root whose part was pressed. Every exception is taken from the snapshot's parents, never from frames
    /// that happen to contain each other (CenterLayoutRule review v1 A-1, A-2).
    static func afterClick(beforeClick: [CenterGroup], afterClick: [CenterGroup], pressedRoot: String,
                           context: CenterPressContext) -> CenterPressVerdict {
        let before = Dictionary(grouping: beforeClick.filter { !$0.identifier.isEmpty }, by: \.identifier)
        let after = Dictionary(grouping: afterClick.filter { !$0.identifier.isEmpty }, by: \.identifier)
        for (identifier, groups) in after where groups.count > (before[identifier]?.count ?? 0) {
            return .arrived
        }
        let on26 = context.osMajor >= 26
        // The pressed root's own parts: below it in the snapshot.
        func partOfRoot(_ group: CenterGroup) -> Bool {
            !pressedRoot.isEmpty && group.identifier != pressedRoot && group.parent == pressedRoot
        }
        // The list: a checked list identifier, once and holding banners before the click.
        func isList(_ identifier: String) -> Bool {
            listIdentifiers.contains(identifier) && before[identifier]?.count == 1 &&
                beforeClick.contains { $0.parent == identifier && !$0.identifier.isEmpty }
        }
        // Frames are compared exactly; the reads are taken once they settle (afterClickSettling), so frames half way
        // through an animation (26: 171.9993 for 172) are not compared.
        func same(_ a: CGRect, _ b: CGRect) -> Bool {
            a == b
        }
        // 15.8.3 (2026-11-28, N23 `Open` in the VM, 3 of 3): when the pressed banner goes and one banner is left,
        // the list goes and that banner takes the list's frame. Taken only when all of it holds: the list was there
        // and is gone, the pressed root was in the list and is gone, the list held exactly the root and this banner,
        // and the banner now has exactly the list's frame. On 26, for a press of a banner's body only (N21, N22,
        // NC1), the banner may be drawn wider to the left by its highlight (`highlightedCollapse`).
        func collapsedOnto(_ identifier: String, _ groups: [CenterGroup]) -> Bool {
            guard groups.count == 1, before[identifier]?.count == 1, let banner = before[identifier]?.first,
                  let list = banner.parent, isList(list), after[list] == nil,
                  let listFrame = before[list]?.first?.frame,
                  before[pressedRoot]?.count == 1, before[pressedRoot]?.first?.parent == list, after[pressedRoot] == nil else {
                return false
            }
            let held = Set(beforeClick.filter { $0.parent == list && !$0.identifier.isEmpty }.map(\.identifier))
            guard held == [pressedRoot, identifier] else { return false }
            return same(groups[0].frame, listFrame) ||
                (on26 && context.press == .body && highlightedCollapse(listFrame, groups[0].frame))
        }
        // 26.6.2 (2026-11-28, NP1 `Allow` in the 26 VM): the banner under the pointer is drawn 6 points wider to the
        // left and 4 higher to the top. Answering the permission prompt moved the pointer's banner from the prompt
        // (the pressed root) to the banner right below it: the root lost exactly that on its left and top edges and
        // that banner gained exactly that, their right and bottom edges unchanged. Only that transition is taken:
        // on 26, for an answer to the prompt, once.
        var highlightTaken = false
        // 26.6.2 (2026-11-28, NP3 settled reads): when the prompt closed, the list laid itself out again and the banner
        // that came under the pointer was drawn with the highlight: exactly 6 wider and 4 higher, its right edge where
        // it was. Taken on 26, for an answer to the prompt, when the root is gone, once (with the move above).
        func highlightedAfterTheRootWent(_ identifier: String, _ groups: [CenterGroup]) -> Bool {
            guard on26, context.press == .promptAnswer, !highlightTaken, groups.count == 1,
                  before[identifier]?.count == 1, let old = before[identifier]?.first, let list = old.parent, isList(list),
                  groups[0].parent == list, before[pressedRoot]?.count == 1, after[pressedRoot] == nil,
                  before[pressedRoot]?.first?.parent == list,
                  groups[0].frame.width == old.frame.width + Self.highlightLeft,
                  groups[0].frame.height == old.frame.height + Self.highlightTop,
                  groups[0].frame.maxX == old.frame.maxX else {
                return false
            }
            highlightTaken = true
            return true
        }
        func highlightMovedFromRoot(_ identifier: String, _ groups: [CenterGroup]) -> Bool {
            if highlightedAfterTheRootWent(identifier, groups) {
                return true
            }
            guard on26, context.press == .promptAnswer, !highlightTaken, groups.count == 1,
                  before[identifier]?.count == 1, let old = before[identifier]?.first, let list = old.parent, isList(list),
                  groups[0].parent == list, before[pressedRoot]?.count == 1, after[pressedRoot]?.count == 1,
                  let rootOld = before[pressedRoot]?.first, let rootNew = after[pressedRoot]?.first,
                  rootOld.parent == list, rootNew.parent == list, old.frame.minY > rootOld.frame.minY else {
                return false
            }
            guard same(rootNew.frame, Self.unhighlighted(rootOld.frame)), same(groups[0].frame, Self.highlighted(old.frame)) else {
                return false
            }
            highlightTaken = true
            return true
        }
        for (identifier, groups) in after where identifier != pressedRoot && !isList(identifier) {
            let own = groups.filter { !partOfRoot($0) }
            // 26 (settle review v1 A-3): a growth of the width or of the height, each on its own; 15 as before (the area).
            let grown: Bool
            if on26, own.count == 1, before[identifier]?.count == 1, let old = before[identifier]?.first {
                grown = own[0].frame.width > old.frame.width || own[0].frame.height > old.frame.height
            } else {
                grown = own.map { area($0.frame) }.reduce(0, +) > (before[identifier] ?? []).map { area($0.frame) }.reduce(0, +)
            }
            if grown && !collapsedOnto(identifier, own) && !highlightMovedFromRoot(identifier, own) {
                return .cannotTell
            }
        }
        // 26.6.2 (2026-11-28, NP2 `Don’t Allow` in the 26 VM): the prompt, closing after its answer, is read once more
        // at the same frame and under the same parent but without its identifier. Taken on 26, for an answer to the
        // prompt, for one such group only, and only when the root is gone.
        var rest = afterClick.filter { $0.identifier.isEmpty && !partOfRoot($0) }
        if on26, context.press == .promptAnswer, after[pressedRoot] == nil, before[pressedRoot]?.count == 1,
           let root = before[pressedRoot]?.first,
           let index = rest.firstIndex(where: { same($0.frame, root.frame) && $0.parent == root.parent }) {
            rest.remove(at: index)
        }
        var unnamedBefore = beforeClick.filter { $0.identifier.isEmpty }.map(\.frame)
        for group in rest {
            guard let index = unnamedBefore.firstIndex(of: group.frame) else {
                return .cannotTell
            }
            unnamedBefore.remove(at: index)
        }
        return .clear
    }

    /// The highlight of 26.6.2: 6 points to the left, 4 to the top (2026-11-28 in the 26 VM).
    static let highlightLeft: CGFloat = 6
    static let highlightTop: CGFloat = 4

    static func highlighted(_ frame: CGRect) -> CGRect {
        CGRect(x: frame.minX - highlightLeft, y: frame.minY - highlightTop,
               width: frame.width + highlightLeft, height: frame.height + highlightTop)
    }

    static func unhighlighted(_ frame: CGRect) -> CGRect {
        CGRect(x: frame.minX + highlightLeft, y: frame.minY + highlightTop,
               width: frame.width - highlightLeft, height: frame.height - highlightTop)
    }


    /// 26.6.2 (2026-11-28, N22 in the 26 VM): the banner the list collapsed onto is under the pointer and drawn wider
    /// to the left by its highlight: the list's frame, 6 points wider to the left (the same top, height and right edge).
    private static func highlightedCollapse(_ frame: CGRect, _ drawn: CGRect) -> Bool {
        drawn == CGRect(x: frame.minX - highlightLeft, y: frame.minY, width: frame.width + highlightLeft, height: frame.height)
    }

    private static func area(_ frame: CGRect) -> CGFloat {
        frame.width * frame.height
    }

    /// The reads after the click (settle review v1). Each read carries the time it was taken, counted from the click
    /// on a monotonic clock, and the identifier of the sample's expected banner when that same snapshot holds exactly
    /// one group with the banner's whole label (`expectedBanner`).
    ///
    /// - The expected banner (NP3) is set aside only when it is the one identifier that came in any read and some read
    ///   confirmed it in its own snapshot; any other identifier that came in any read is `arrived`.
    /// - A first read that is `clear` and is the only read is taken as it is.
    /// - Otherwise the reads must settle before `deadline`: the first two reads in a row that are the same groups
    ///   (identifier, frame and parent), the second taken before the deadline, are compared.
    /// - Every read before that pair must be clear, or, on 26 only, a step of an animation towards the settled read:
    ///   every named group inside the box of its frames before and settled (a list anywhere, a group without an
    ///   identifier only when unchanged from before or as the closing prompt). A read that was not is kept: the result
    ///   is `cannotTell` even when the reads settle clear.
    static func afterClickSettling(beforeClick: [CenterGroup], reads: [CenterRead], deadline: TimeInterval,
                                   pressedRoot: String, context: CenterPressContext) -> CenterPressVerdict {
        guard !reads.isEmpty else {
            return .cannotTell
        }
        let arrived = arrivedIdentifiers(beforeClick: beforeClick, reads: reads.map(\.groups))
        let confirmed = Set(reads.compactMap(\.expectedBanner))
        var groupsRead = reads.map(\.groups)
        if !arrived.isEmpty {
            guard arrived.count == 1, confirmed == arrived, let banner = arrived.first else {
                return .arrived
            }
            groupsRead = without(banner, groupsRead)
        }
        let verdicts = groupsRead.map { afterClick(beforeClick: beforeClick, afterClick: $0, pressedRoot: pressedRoot, context: context) }
        if verdicts.contains(.arrived) {
            return .arrived
        }
        if groupsRead.count == 1 {
            return verdicts[0] == .clear ? .clear : .cannotTell
        }
        guard let settled = groupsRead.indices.dropFirst().first(where: {
            sameGroups(groupsRead[$0 - 1], groupsRead[$0]) && reads[$0].at <= deadline
        }) else {
            return .cannotTell
        }
        for index in 0..<(settled - 1) where verdicts[index] != .clear {
            guard context.osMajor >= 26, stepTowards(groupsRead[settled], groupsRead[index], beforeClick: beforeClick,
                                                     pressedRoot: pressedRoot, context: context) else {
                return .cannotTell
            }
        }
        return verdicts[settled]
    }

    /// 26: whether `step` lies between the reads before the click and `settled` (an animation half way).
    private static func stepTowards(_ settled: [CenterGroup], _ step: [CenterGroup], beforeClick: [CenterGroup],
                                    pressedRoot: String, context: CenterPressContext) -> Bool {
        for group in step {
            if group.identifier.isEmpty {
                let unchanged = beforeClick.contains(group)
                let closingPrompt = context.press == .promptAnswer &&
                    beforeClick.contains { $0.identifier == pressedRoot && $0.frame == group.frame && $0.parent == group.parent }
                guard unchanged || closingPrompt else { return false }
                continue
            }
            if listIdentifiers.contains(group.identifier) {
                continue
            }
            let frames = (beforeClick + settled).filter { $0.identifier == group.identifier }.map(\.frame)
            guard let first = frames.first else { return false }
            let box = frames.dropFirst().reduce(first) { $0.union($1) }
            let list = beforeClick.first { listIdentifiers.contains($0.identifier) && $0.identifier == group.parent }?.frame
            guard box.contains(group.frame) || (list?.contains(group.frame) ?? false) else { return false }
        }
        return true
    }

    /// Whether the reads so far are enough for `afterClickSettling`: the first and only read is clear, a read has a
    /// new notification other than the expected banner (with an expected banner the reads go on until they settle,
    /// NP3), or the last two are the same.
    static func readsAreDone(beforeClick: [CenterGroup], reads: [CenterRead], pressedRoot: String,
                             context: CenterPressContext, expectingBanner: Bool = false) -> Bool {
        guard let last = reads.last else {
            return false
        }
        let verdict = afterClick(beforeClick: beforeClick, afterClick: last.groups, pressedRoot: pressedRoot, context: context)
        if (verdict == .arrived && !expectingBanner) || (reads.count == 1 && verdict == .clear) {
            return true
        }
        return reads.count >= 2 && sameGroups(reads[reads.count - 2].groups, last.groups)
    }

    /// The identifiers that are there more times after the click than before (the notifications that came).
    static func arrivedIdentifiers(beforeClick: [CenterGroup], reads: [[CenterGroup]]) -> Set<String> {
        let before = Dictionary(grouping: beforeClick.filter { !$0.identifier.isEmpty }, by: \.identifier)
        var arrived: Set<String> = []
        for read in reads {
            for (identifier, groups) in Dictionary(grouping: read.filter { !$0.identifier.isEmpty }, by: \.identifier)
            where groups.count > (before[identifier]?.count ?? 0) {
                arrived.insert(identifier)
            }
        }
        return arrived
    }

    /// The reads without the groups of `identifier` (the sample's own banner that the press was expected to bring).
    static func without(_ identifier: String, _ reads: [[CenterGroup]]) -> [[CenterGroup]] {
        reads.map { $0.filter { $0.identifier != identifier } }
    }

    static let settleInterval: TimeInterval = 0.3
    static let settleTimeout: TimeInterval = 3

    private static func sameGroups(_ a: [CenterGroup], _ b: [CenterGroup]) -> Bool {
        guard a.count == b.count else {
            return false
        }
        var rest = b
        for group in a {
            guard let index = rest.firstIndex(of: group) else {
                return false
            }
            rest.remove(at: index)
        }
        return true
    }
}

// MARK: - Reply state (U-30 mac26-reply)

/// Whether `Reply` opened Notification Center's list (U-30): the runner's `classify_reply_state`, the same rules.
enum ReplyState: Equatable {
    case list, banner, unknown
}

struct ReplyField: Equatable {
    let inRoot: Bool
    let focused: Bool
}

enum ReplyStateRule {
    /// `rootBefore`: the frame of the sample's root before `Reply`. `windowsBefore` / `windowsAfter`: the frames of
    /// Notification Center's windows in front of the sample's window, before and within 2 seconds after. Precondition:
    /// exactly one window before, holding the root and inside the root plus `margin` (a banner-sized window). `list`
    /// when a window was added, or the window holding the root grew past root plus `margin`. `banner` when the count is
    /// the same, that window stays inside root plus `margin`, and exactly one focused field is in the root. Anything
    /// else, or any value missing, is `unknown`.
    static func classify(rootBefore: CGRect?, windowsBefore: [CGRect]?, windowsAfter: [CGRect]?,
                         fieldsAfter: [ReplyField]?, margin: CGFloat) -> ReplyState {
        guard let root = rootBefore, let before = windowsBefore, let after = windowsAfter, let fields = fieldsAfter,
              margin >= 0 else {
            return .unknown
        }
        let bound = root.insetBy(dx: -margin, dy: -margin)
        let holdingBefore = before.filter { $0.contains(root) }
        guard before.count == 1, holdingBefore.count == 1, bound.contains(holdingBefore[0]) else {
            return .unknown
        }
        if after.count > before.count {
            return .list
        }
        let holdingAfter = after.filter { $0.contains(root) }
        if holdingAfter.count == 1 && !bound.contains(holdingAfter[0]) {
            return .list
        }
        guard after.count == before.count, holdingAfter.count == 1 else {
            return .unknown
        }
        let inRoot = fields.filter(\.inRoot)
        return inRoot.count == 1 && inRoot[0].focused ? .banner : .unknown
    }
}
