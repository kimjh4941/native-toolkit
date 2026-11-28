//
//  NotificationCenterUI.swift
//  MacLibraryExampleUITests
//
//  Operations on Notification Center for the sample's notifications (UI test design U-2, U-5,
//  5.0, 6.1). Trusted Support file. Every entry point that presses needs a `NotificationToken`;
//  answering the permission prompt also needs `NCSettingsToken`.
//
//  - The sample's banner root is the one group whose label is the whole anchor (`BannerAnchor`);
//    0 or 2+ matches fail without a press. The root's group identifier is kept when it is first
//    found, and every later step finds the root again and requires the same identifier (a replaced
//    root fails).
//  - `Options` and the reply field are taken only from inside the root. The menu `Options` opens is
//    outside the root (macOS 15.8.3: a Notification Center window at layer 101); its items are taken
//    from the one open menu, by title (their identifiers are all `menuAction:`).
//  - Before each press: the sample is in the state the scenario names (foreground, background or not
//    running), and `NotificationOverlayRule` passes for the point. Before each key: Notification
//    Center is the frontmost app and the reply field in the root has the keyboard focus.
//  - Read-only counts (no token): `NotificationCenterRead`.
//

import XCTest
import Foundation
import AppKit

// MARK: - Read-only (no token. Design 5.0)

enum NotificationCenterRead {

    static var center: XCUIApplication {
        XCUIApplication(bundleIdentifier: SystemLabels.notificationCenterBundleIdentifier)
    }

    /// Roots of the sample (label starts with `MacLibraryExample, `), whatever their title.
    static func sampleRootCount() -> Int {
        center.groups.matching(NSPredicate(format: "label BEGINSWITH %@", BannerAnchor.anyRootPrefix)).count
    }

    /// Roots of the sample's permission prompt.
    static func permissionPromptCount() -> Int {
        center.groups.matching(permissionPromptPredicate).count
    }

    static var permissionPromptPredicate: NSPredicate {
        let prefixes = SystemLabels.permissionPromptPrefixes(appName: BannerAnchor.appName)
        return NSCompoundPredicate(orPredicateWithSubpredicates: prefixes.map {
            NSPredicate(format: "label BEGINSWITH %@", $0)
        })
    }

    /// The groups Notification Center shows now: identifier (empty when it has none), exact frame and parent only;
    /// no label is read here (the comparison uses none; the root is found by its whole label in `waitForRoot`). Notification Center draws every banner in one window, so a banner that arrives is seen
    /// here, not in the window list (2026-11-28: one window, the same number and frame, while banners came).
    /// Groups without an area are left out (nothing on the screen to take a click); a group without an area still
    /// passes its identifier down as the parent. `CenterLayoutRule` compares them (runner review v7: Codex B-1).
    static func groups() throws -> [CenterGroup] {
        let root: XCUIElementSnapshot
        do {
            root = try center.snapshot()
        } catch {
            throw SampleUITestError(.overlay, "Notification Center's tree could not be read")
        }
        var out: [CenterGroup] = []
        // `parent`: the nearest group above with an identifier (CenterLayoutRule review v1 A-1).
        func visit(_ node: XCUIElementSnapshot, parent: String?) {
            var below = parent
            if node.elementType == .group, node.frame.width > 0, node.frame.height > 0 {
                out.append(CenterGroup(identifier: node.identifier, frame: node.frame, parent: parent))
            }
            if node.elementType == .group, !node.identifier.isEmpty {
                below = node.identifier
            }
            for child in node.children {
                visit(child, parent: below)
            }
        }
        visit(root, parent: nil)
        return out
    }

    /// Frames of the menus of Notification Center that are open now (outside the menu bar, with a
    /// visible frame).
    static func openMenuFrames() throws -> [CGRect] {
        let root = try center.snapshot()
        var frames: [CGRect] = []
        func visit(_ node: XCUIElementSnapshot, inMenuBar: Bool) {
            let menuBar = inMenuBar || node.elementType == .menuBar
            if node.elementType == .menu && !menuBar && node.frame.width > 0 && node.frame.height > 0 {
                frames.append(node.frame)
            }
            for child in node.children {
                visit(child, inMenuBar: menuBar)
            }
        }
        visit(root, inMenuBar: false)
        return frames
    }
}

// MARK: - A found root

/// A root found once: its anchor, its group identifier and when it appeared.
struct NotificationRoot {
    let anchor: BannerAnchor
    let groupIdentifier: String
    let appearedAt: Date
}

/// The sample states a scenario allows at a press in Notification Center (design 5.0: the state the
/// scenario needs, not always the foreground).
enum SampleStateAtPress {
    case foreground
    case background
    case notRunning

    var state: XCUIApplication.State {
        switch self {
        case .foreground: return .runningForeground
        case .background: return .runningBackground
        case .notRunning: return .notRunning
        }
    }

    /// Whether the sample runs behind, as AppKit sees it: it runs, none of its processes is active, and
    /// none is the frontmost application. `XCUIApplication.state` is not used for "behind": on the VM it
    /// stayed `runningForeground` while Finder was already in front (stage 0d 16, 17). The main run loop is
    /// given a turn first, so the values are the ones of its latest pass (on the main thread only).
    static func sampleIsBehind() -> Bool {
        if Thread.isMainThread {
            RunLoop.current.run(until: Date())
        }
        let samples = NSRunningApplication.runningApplications(withBundleIdentifier: SystemLabels.sampleBundleIdentifier)
        let front = NSWorkspace.shared.frontmostApplication?.processIdentifier
        return !samples.isEmpty && samples.allSatisfy { !$0.isActive && $0.processIdentifier != front }
    }

    /// The reverse of `sampleIsBehind`, by the same observation: the sample runs as exactly one process,
    /// it is active, and it is the frontmost application (Codex FinderFront review v2 A-1: a stale
    /// `runningForeground` of XCUITest must not pass "came to the front").
    static func sampleIsInFront() -> Bool {
        if Thread.isMainThread {
            RunLoop.current.run(until: Date())
        }
        let samples = NSRunningApplication.runningApplications(withBundleIdentifier: SystemLabels.sampleBundleIdentifier)
        let front = NSWorkspace.shared.frontmostApplication?.processIdentifier
        return samples.count == 1 && samples[0].isActive && samples[0].processIdentifier == front
    }

    /// Waits until `sampleIsInFront`, giving the main run loop a turn between looks. Nothing here brings the
    /// sample to the front: the press under test must have done it.
    @MainActor
    static func waitForSampleInFront(timeout: TimeInterval, after name: String) throws {
        let deadline = Date().addingTimeInterval(timeout)
        while !sampleIsInFront() {
            guard Date() < deadline else {
                throw SampleUITestError(.notificationState, "the sample did not come to the front for AppKit in \(timeout)s after \(name)")
            }
            RunLoop.current.run(until: Date().addingTimeInterval(0.1))
        }
    }

    /// Writes into the test's activity log when XCUITest and AppKit disagree about the sample, so a later
    /// look at a failure can tell (the result bundle's activities; nothing else is affected).
    static func noteDisagreement(xcuiState: XCUIApplication.State, appKitBehind: Bool, at name: String) {
        let xcuiBehind = xcuiState == .runningBackground
        guard xcuiBehind != appKitBehind else { return }
        XCTContext.runActivity(named: "NTK-NOTE sample state: XCUITest \(xcuiState.rawValue), AppKit "
                               + (appKitBehind ? "behind" : "not behind") + " at \(name)") { _ in }
    }
}

// MARK: - Notification Center

struct NotificationCenterUI {

    private let sample: SampleApp
    private let session: UITestSession
    private let center = NotificationCenterRead.center

    /// Wait before pressing a banner after it appeared (U-14 (b)).
    static let settleAfterAppear: TimeInterval = 1
    static let menuTimeout: TimeInterval = 5
    /// How long a press may wait for the overlay rule (design 5.0: 10 s for Notification Center).
    static let overlayTimeout: TimeInterval = 10
    /// The sample's reply placeholder (stage 0b). Checked only when the tree shows a placeholder.
    static let replyPlaceholder = "MacLibraryExample reply"

    init(_ sample: SampleApp, _ token: NotificationToken) {
        self.sample = sample
        session = token.session
    }

    // MARK: Roots

    private func query(_ anchor: BannerAnchor) -> XCUIElementQuery {
        center.groups.matching(NSPredicate(format: "label == %@", anchor.label))
    }

    /// Waits until exactly one root with `anchor` is shown (2+ fail at once) and remembers it.
    func waitForRoot(_ anchor: BannerAnchor, timeout: TimeInterval) throws -> NotificationRoot {
        let deadline = Date().addingTimeInterval(timeout)
        while true {
            let matches = query(anchor)
            let count = matches.count
            if count > 1 {
                throw SampleUITestError(.notificationRoot, "\(count) roots of \(anchor.title)")
            }
            if count == 1 {
                let element = matches.element
                let identifier = element.identifier
                guard anchor.matches(element.label), !identifier.isEmpty else {
                    throw SampleUITestError(.notificationRoot, "the root of \(anchor.title) has another label or no identifier")
                }
                try session.checkInterruption()
                return NotificationRoot(anchor: anchor, groupIdentifier: identifier, appearedAt: Date())
            }
            guard Date() < deadline else {
                throw SampleUITestError(.notificationRoot, "no root of \(anchor.title) in \(timeout)s")
            }
            Thread.sleep(forTimeInterval: 0.1)
        }
    }

    /// No root with `anchor` until `deadline` (U-14 (a)).
    func expectNoRoot(_ anchor: BannerAnchor, until deadline: Date) throws {
        repeat {
            guard query(anchor).count == 0 else {
                throw SampleUITestError(.notificationRoot, "a root of \(anchor.title) appeared")
            }
            Thread.sleep(forTimeInterval: 0.2)
        } while Date() < deadline
        try session.checkInterruption()
    }

    /// Waits until the root has gone (the banner hides itself after about 5 seconds).
    func waitRootGone(_ root: NotificationRoot, timeout: TimeInterval) throws {
        guard query(root.anchor).firstMatch.waitForNonExistence(timeout: timeout) else {
            throw SampleUITestError(.notificationRoot, "the root of \(root.anchor.title) did not go in \(timeout)s")
        }
        try session.checkInterruption()
    }

    /// The root now: exactly one, the same group as when it was found.
    private func element(_ root: NotificationRoot) throws -> XCUIElement {
        let element = try exactlyOne(query(root.anchor), "root of \(root.anchor.title)", step: .notificationRoot)
        guard element.identifier == root.groupIdentifier else {
            throw SampleUITestError(.notificationRoot, "the root of \(root.anchor.title) was replaced")
        }
        return element
    }

    // MARK: Body, hover, Options

    /// Clicks the root's body, one second after it appeared (U-14 (b)).
    func clickBody(_ root: NotificationRoot, sampleIs expected: SampleStateAtPress) throws {
        let wait = Self.settleAfterAppear - Date().timeIntervalSince(root.appearedAt)
        if wait > 0 {
            Thread.sleep(forTimeInterval: wait)
        }
        let element = try self.element(root)
        try pressInCenter(element, root: root, kind: { .banner(rootFrame: try self.element(root).frame) },
                          sampleIs: expected, name: "body of \(root.anchor.title)")
    }

    /// Moves the pointer onto the root (it shows `Options` only then).
    func hover(_ root: NotificationRoot, sampleIs expected: SampleStateAtPress) throws {
        let wait = Self.settleAfterAppear - Date().timeIntervalSince(root.appearedAt)
        if wait > 0 {
            Thread.sleep(forTimeInterval: wait)
        }
        let element = try self.element(root)
        try checkBeforePress(element, kind: { .banner(rootFrame: try self.element(root).frame) },
                             sampleIs: expected, name: "hover of \(root.anchor.title)")
        element.hover()
        try session.checkInterruption()
    }

    private func optionsQuery(in rootElement: XCUIElement) -> XCUIElementQuery {
        rootElement.menuButtons.matching(NSPredicate(format: "title IN %@", SystemLabels.notificationOptions))
    }

    /// After hovering: no `Options` inside the root for `seconds` (N20, a notification without a
    /// category. U-14 (a)).
    func expectNoOptions(_ root: NotificationRoot, for seconds: TimeInterval, sampleIs expected: SampleStateAtPress) throws {
        try hover(root, sampleIs: expected)
        let deadline = Date().addingTimeInterval(seconds)
        repeat {
            guard optionsQuery(in: try element(root)).count == 0 else {
                throw SampleUITestError(.notificationAction, "the root of \(root.anchor.title) shows Options")
            }
            Thread.sleep(forTimeInterval: 0.2)
        } while Date() < deadline
        try session.checkInterruption()
    }

    /// Hovers the root, presses its `Options` and waits for exactly one open menu.
    func openOptions(_ root: NotificationRoot, sampleIs expected: SampleStateAtPress) throws {
        guard try NotificationCenterRead.openMenuFrames().isEmpty else {
            throw SampleUITestError(.notificationAction, "a menu of Notification Center is open before Options")
        }
        try hover(root, sampleIs: expected)
        let deadline = Date().addingTimeInterval(Self.menuTimeout)
        while optionsQuery(in: try element(root)).count == 0 {
            guard Date() < deadline else {
                throw SampleUITestError(.notificationAction, "the root of \(root.anchor.title) shows no Options")
            }
            Thread.sleep(forTimeInterval: 0.1)
        }
        let options = try exactlyOne(optionsQuery(in: try element(root)), "Options in the root", step: .notificationAction)
        try pressInCenter(options, root: root, kind: { .banner(rootFrame: try self.element(root).frame) },
                          sampleIs: expected, name: "Options of \(root.anchor.title)")
        try waitForOneOpenMenu()
    }

    private func waitForOneOpenMenu() throws {
        let deadline = Date().addingTimeInterval(Self.menuTimeout)
        while true {
            let count = try NotificationCenterRead.openMenuFrames().count
            if count == 1 { break }
            guard count == 0, Date() < deadline else {
                throw SampleUITestError(.notificationAction, "\(count) open menus after Options")
            }
            Thread.sleep(forTimeInterval: 0.1)
        }
        try session.checkInterruption()
    }

    // MARK: The menu Options opened

    /// The item titled `title` in the one open menu: exactly one, inside that menu's frame.
    private func menuItem(_ title: String) throws -> XCUIElement {
        let menus = try NotificationCenterRead.openMenuFrames()
        guard menus.count == 1, let menu = menus.first else {
            throw SampleUITestError(.notificationAction, "\(menus.count) open menus")
        }
        let candidates = center.menuItems.matching(NSPredicate(format: "title == %@ OR identifier == %@", title, title))
            .allElementsBoundByIndex.filter { menu.contains($0.frame) && $0.frame.width > 0 }
        guard candidates.count == 1, let item = candidates.first else {
            throw SampleUITestError(.notificationAction, "\(candidates.count) items \(title) in the open menu")
        }
        return item
    }

    /// Number of items titled `title` in the one open menu (N20).
    func menuItemCount(_ title: String) throws -> Int {
        let menus = try NotificationCenterRead.openMenuFrames()
        guard menus.count == 1, let menu = menus.first else {
            throw SampleUITestError(.notificationAction, "\(menus.count) open menus")
        }
        return center.menuItems.matching(NSPredicate(format: "title == %@ OR identifier == %@", title, title))
            .allElementsBoundByIndex.filter { menu.contains($0.frame) && $0.frame.width > 0 }.count
    }

    /// Presses the item `title` of the menu the root's `Options` opened. The root must still be the
    /// same one and the menu still the only open one.
    func choose(_ title: String, of root: NotificationRoot, sampleIs expected: SampleStateAtPress) throws {
        _ = try element(root)
        let item = try menuItem(title)
        try pressInCenter(item, root: root, kind: { _ = try self.element(root); _ = try self.menuItem(title); return .menuItem },
                          sampleIs: expected, name: "menu item \(title)")
    }

    /// Closes the open menu with Escape: exactly one menu is open and Notification Center is in front.
    /// U-30 `mac26` (`MacQualificationProbeTests`): the check before pressing the item `title` of the menu the
    /// root's `Options` opened, exactly as `choose` runs it, and no press. Throws as `choose` would before pressing.
    func checkMenuItemWithoutPressing(_ title: String, of root: NotificationRoot, sampleIs expected: SampleStateAtPress) throws {
        _ = try element(root)
        let item = try menuItem(title)
        try checkBeforePress(item, kind: { _ = try self.element(root); _ = try self.menuItem(title); return .menuItem },
                             sampleIs: expected, name: "menu item \(title)")
    }

    func escapeMenu(of root: NotificationRoot, anyItemTitle title: String) throws {
        _ = try element(root)
        let item = try menuItem(title)
        try checkCenterInFront(name: "menu Escape")
        _ = item
        center.typeKey(XCUIKeyboardKey.escape.rawValue, modifierFlags: [])
        try session.checkInterruption()
        let deadline = Date().addingTimeInterval(Self.menuTimeout)
        while try !NotificationCenterRead.openMenuFrames().isEmpty {
            guard Date() < deadline else {
                throw SampleUITestError(.notificationAction, "the menu did not close")
            }
            Thread.sleep(forTimeInterval: 0.1)
        }
    }

    // MARK: Reply (text input)

    /// The reply field inside the root: exactly one text view, with the keyboard focus.
    private func replyField(_ root: NotificationRoot) throws -> XCUIElement {
        let field = try exactlyOne(try element(root).textViews, "reply field in the root", step: .notificationReply)
        guard sample.hasKeyboardFocus(field) == true else {
            throw SampleUITestError(.notificationReply, "the reply field does not have the keyboard focus")
        }
        // The placeholder is empty in the 15.8.3 tree (stage 0b); compared only when it is shown.
        if let placeholder = field.placeholderValue, !placeholder.isEmpty, placeholder != Self.replyPlaceholder {
            throw SampleUITestError(.notificationReply, "the reply field has another placeholder")
        }
        return field
    }

    /// Waits for the reply field in the root, types `text` and sends it with Return. The root and the
    /// field are found again before typing and before Return (U-5).
    func reply(_ text: String, in root: NotificationRoot) throws {
        let deadline = Date().addingTimeInterval(Self.menuTimeout)
        while try element(root).textViews.count == 0 {
            guard Date() < deadline else {
                throw SampleUITestError(.notificationReply, "no reply field in the root")
            }
            Thread.sleep(forTimeInterval: 0.1)
        }
        let field = try replyField(root)
        try checkCenterInFront(name: "reply text")
        field.typeText(text)
        try session.checkInterruption()
        let again = try replyField(root)
        try checkCenterInFront(name: "reply Return")
        again.typeKey(XCUIKeyboardKey.return.rawValue, modifierFlags: [])
        try session.checkInterruption()
    }

    /// No permission prompt of the sample for `seconds` (N2, NP2. U-14 (a)). Reads only.
    func expectNoPermissionPrompt(for seconds: TimeInterval) throws {
        let deadline = Date().addingTimeInterval(seconds)
        repeat {
            guard NotificationCenterRead.permissionPromptCount() == 0 else {
                throw SampleUITestError(.permissionPrompt, "a permission prompt appeared")
            }
            Thread.sleep(forTimeInterval: 0.2)
        } while Date() < deadline
        try session.checkInterruption()
    }

    // MARK: Permission prompt (VM only. NP1〜NP3)

    /// Waits for exactly one permission prompt of the sample and remembers it.
    func waitForPermissionPrompt(_ token: NCSettingsToken, timeout: TimeInterval) throws -> NotificationRoot {
        let deadline = Date().addingTimeInterval(timeout)
        while true {
            let matches = center.groups.matching(NotificationCenterRead.permissionPromptPredicate)
            let count = matches.count
            if count > 1 {
                throw SampleUITestError(.permissionPrompt, "\(count) permission prompts")
            }
            if count == 1 {
                let element = matches.element
                guard !element.identifier.isEmpty else {
                    throw SampleUITestError(.permissionPrompt, "the permission prompt has no identifier")
                }
                try session.checkInterruption()
                return NotificationRoot(anchor: BannerAnchor(title: "", body: ""), groupIdentifier: element.identifier,
                                        appearedAt: Date())
            }
            guard Date() < deadline else {
                throw SampleUITestError(.permissionPrompt, "no permission prompt in \(timeout)s")
            }
            Thread.sleep(forTimeInterval: 0.1)
        }
    }

    private func promptElement(_ prompt: NotificationRoot) throws -> XCUIElement {
        let element = try exactlyOne(center.groups.matching(NotificationCenterRead.permissionPromptPredicate),
                                     "permission prompt", step: .permissionPrompt)
        guard element.identifier == prompt.groupIdentifier else {
            throw SampleUITestError(.permissionPrompt, "the permission prompt was replaced")
        }
        return element
    }

    /// Answers the prompt: hover, its `Options`, then `Allow` or `Don’t Allow` (exactly one each).
    func answerPermissionPrompt(_ prompt: NotificationRoot, allow: Bool, _ token: NCSettingsToken) throws {
        let wait = Self.settleAfterAppear - Date().timeIntervalSince(prompt.appearedAt)
        if wait > 0 {
            Thread.sleep(forTimeInterval: wait)
        }
        guard try NotificationCenterRead.openMenuFrames().isEmpty else {
            throw SampleUITestError(.permissionPrompt, "a menu of Notification Center is open before Options")
        }
        let rootElement = try promptElement(prompt)
        try checkBeforePress(rootElement, kind: { .banner(rootFrame: try self.promptElement(prompt).frame) },
                             sampleIs: nil, name: "hover of the permission prompt")
        rootElement.hover()
        try session.checkInterruption()
        let deadline = Date().addingTimeInterval(Self.menuTimeout)
        while optionsQuery(in: try promptElement(prompt)).count == 0 {
            guard Date() < deadline else {
                throw SampleUITestError(.permissionPrompt, "the permission prompt shows no Options")
            }
            Thread.sleep(forTimeInterval: 0.1)
        }
        let options = try exactlyOne(optionsQuery(in: try promptElement(prompt)), "Options of the prompt",
                                     step: .permissionPrompt)
        try pressInCenter(options, root: prompt, kind: { .banner(rootFrame: try self.promptElement(prompt).frame) },
                          sampleIs: nil, name: "Options of the permission prompt")
        try waitForOneOpenMenu()
        let titles = allow ? SystemLabels.permissionAllow : SystemLabels.permissionDontAllow
        let menus = try NotificationCenterRead.openMenuFrames()
        guard menus.count == 1, let menu = menus.first else {
            throw SampleUITestError(.permissionPrompt, "\(menus.count) open menus")
        }
        let items = center.menuItems.matching(NSPredicate(format: "title IN %@", titles))
            .allElementsBoundByIndex.filter { menu.contains($0.frame) && $0.frame.width > 0 }
        guard items.count == 1, let item = items.first else {
            throw SampleUITestError(.permissionPrompt, "\(items.count) items \(titles[0]) in the prompt's menu")
        }
        _ = try promptElement(prompt)
        try pressInCenter(item, root: prompt, kind: { .menuItem }, sampleIs: nil, name: "permission item \(titles[0])")
    }

    // MARK: Checks (design 5.0)

    /// Every click into Notification Center (2026-11-28: a banner of another app that came 0.2 s before the
    /// click took the press). The groups Notification Center shows are read when the check starts and again
    /// right before the click: if anything came, went or moved in between, nothing is pressed. They are read
    /// once more right after the click, and `CenterLayoutRule` says whether a notification may have arrived or
    /// the reads cannot tell (both fail the test). This is detection in the VM, not a guard: between the last
    /// read and the event XCTest synthesizes is a race of a length nobody bounds, and a notification that took
    /// the click and went away is not seen here. Where the test expects an event of the sample, a click that
    /// went elsewhere can also make that event not come; that does not hold for every click (Options, the
    /// permission prompt's items; Codex runner review v7 C-2). UI tests therefore never run on this Mac (D-21
    /// revised 2026-11-28; Codex presscenter review v1 A-1).
    private func pressInCenter(_ element: XCUIElement, root: NotificationRoot, kind: () throws -> NotificationPressKind,
                               sampleIs expected: SampleStateAtPress?, name: String) throws {
        let atCheck = try NotificationCenterRead.groups()
        try checkBeforePress(element, kind: kind, sampleIs: expected, name: name)
        let beforePress = try NotificationCenterRead.groups()
        guard CenterLayoutRule.beforeClick(atCheck: atCheck, beforeClick: beforePress) == .clear else {
            throw SampleUITestError(.overlay, "Notification Center changed between the check and \(name); nothing was pressed")
        }
        element.click()
        let afterPress = try NotificationCenterRead.groups()
        switch CenterLayoutRule.afterClick(beforeClick: beforePress, afterClick: afterPress, pressedRoot: root.groupIdentifier) {
        case .clear:
            break
        case .arrived:
            throw SampleUITestError(.overlay, "a notification arrived while pressing \(name); the press may have reached another notification")
        case .cannotTell, .changed:
            throw SampleUITestError(.overlay, "Notification Center changed while pressing \(name) in a way the reads cannot tell apart; the press may have reached another notification")
        }
        try session.checkInterruption()
    }

    /// `expected` nil: any sample state (the permission prompt).
    private func checkBeforePress(_ element: XCUIElement, kind: () throws -> NotificationPressKind,
                                  sampleIs expected: SampleStateAtPress?, name: String) throws {
        let start = Date()
        while true {
            if let expected {
                // "Behind" is AppKit's view (SampleStateAtPress.sampleIsBehind); the other states stay
                // XCUITest's (Codex FinderFront review v1 B-1).
                let behind = SampleStateAtPress.sampleIsBehind()
                SampleStateAtPress.noteDisagreement(xcuiState: sample.state, appKitBehind: behind, at: "before \(name)")
                let matches = expected == .background ? behind : sample.state == expected.state
                guard matches else {
                    throw SampleUITestError(.notificationState, "the sample is \(sample.state.rawValue) (behind for AppKit: \(SampleStateAtPress.sampleIsBehind())), not \(expected) before \(name)")
                }
            }
            let frame = element.frame
            guard frame.width > 0, frame.height > 0 else {
                throw SampleUITestError(.overlay, "\(name) has an empty frame")
            }
            let verdict = NotificationOverlayRule.verdict(point: CGPoint(x: frame.midX, y: frame.midY), kind: try kind(),
                                                          windows: try OverlayCheck.readWindows(),
                                                          displays: OverlayCheck.displays())
            if verdict == .clear { return }
            guard Date().timeIntervalSince(start) < Self.overlayTimeout else {
                throw SampleUITestError(.overlay, "\(name) is not on Notification Center's window (\(verdict))")
            }
            Thread.sleep(forTimeInterval: 0.2)
        }
    }

    private func checkCenterInFront(name: String) throws {
        let centers = OverlayCheck.pids(of: SystemLabels.notificationCenterBundleIdentifier)
        guard let front = OverlayCheck.frontmostPID(), centers.contains(front) else {
            throw SampleUITestError(.keyFocus, "Notification Center is not the frontmost app before \(name)")
        }
    }
}
