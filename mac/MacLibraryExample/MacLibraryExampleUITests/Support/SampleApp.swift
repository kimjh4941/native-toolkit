//
//  SampleApp.swift
//  MacLibraryExampleUITests
//
//  The only way the new test classes operate the sample app (UI test design 6.1). Trusted Support
//  file. It owns the `XCUIApplication`, finds every element of the sample by its accessibility
//  identifier with exactly one match (U-2), runs the check before every press, scroll and key
//  (design 5.0, `OverlayCheck`), presses buttons that need a token only through the token-taking
//  entry points (U-9), reads the numbered result line (U-3), records the pressed buttons (5.7) and
//  checks the interruption mark right after each operation (U-8).
//
//  The identifier strings are copies of the sample's `*SampleIdentifiers` enums (the test bundle
//  is a separate process). Design 4.1 is the list; I1a〜I1d check the copies against the screen.
//

import XCTest
import Foundation
import AppKit

// MARK: - Identifiers of the sample

enum SampleScreen: String, CaseIterable {
    case dialog
    case notification
    case share
    case clipboard

    var menuIdentifier: String { "menu.\(rawValue)" }
    var resultIdentifier: String { "\(rawValue).result" }
    /// Prefix of every identifier of the screen.
    var identifierPrefix: String { "\(rawValue)." }
    var buttonPrefix: String { "\(rawValue).button." }
}

/// `DialogSampleIdentifiers.ButtonName`.
enum DialogButton: String, CaseIterable {
    case showDialog = "ShowDialog"
    case showFileDialog = "ShowFileDialog"
    case showMultiFileDialog = "ShowMultiFileDialog"
    case showFolderDialog = "ShowFolderDialog"
    case showMultiFolderDialog = "ShowMultiFolderDialog"
    case showSaveFileDialog = "ShowSaveFileDialog"

    var identifier: String { SampleScreen.dialog.buttonPrefix + rawValue }

    /// The panels need `panels` (design 3.3); the alert needs nothing.
    fileprivate var requiredCategory: DeviceCategory? {
        self == .showDialog ? nil : .panels
    }

    /// The start of the result line's text after `Result: ` (`ShowDialog - result: ...`).
    var resultMarker: String { "\(rawValue) - " }
}

/// `NotificationSampleIdentifiers.ButtonName`. The buttons that need no token are pressed with
/// `tap(_:)`; the rest only through the token-taking entry points.
enum NotificationButton: String, CaseIterable {
    case requestPermission = "RequestPermission"
    case hasPermission = "HasPermission"
    case authorizationStatus = "AuthorizationStatus"
    case openNotificationSettings = "OpenNotificationSettings"
    case showImmediate = "ShowImmediate"
    case showTimeInterval = "ShowTimeInterval"
    case showCalendar = "ShowCalendar"
    case updateById = "UpdateById"
    case cancelById = "CancelById"
    case cancelAll = "CancelAll"
    case removeDeliveredById = "RemoveDeliveredById"
    case removeAllDelivered = "RemoveAllDelivered"
    case scheduleTimeInterval = "ScheduleTimeInterval"
    case scheduleCalendar = "ScheduleCalendar"
    case cancelScheduledById = "CancelScheduledById"
    case cancelAllScheduled = "CancelAllScheduled"
    case getScheduled = "GetScheduled"
    case getDelivered = "GetDelivered"
    case setBadgeCount1 = "SetBadgeCount1"
    case setBadgeCount0 = "SetBadgeCount0"
    case registerCategory = "RegisterCategory"
    case removeCategory = "RemoveCategory"

    var identifier: String { SampleScreen.notification.buttonPrefix + rawValue }

    /// Buttons that post, schedule or update a notification or can ask for permission need
    /// `notification` (`runWithPermission`); the settings button `settings`; the badge buttons
    /// `badge` and `notification` (design 3.3).
    fileprivate var requiredCategory: DeviceCategory? {
        switch self {
        case .requestPermission, .showImmediate, .showTimeInterval, .showCalendar, .updateById,
             .scheduleTimeInterval, .scheduleCalendar:
            return .notification
        case .openNotificationSettings:
            return .settings
        case .setBadgeCount1, .setBadgeCount0:
            return .badge
        case .hasPermission, .authorizationStatus, .cancelById, .cancelAll, .removeDeliveredById,
             .removeAllDelivered, .cancelScheduledById, .cancelAllScheduled, .getScheduled,
             .getDelivered, .registerCategory, .removeCategory:
            return nil
        }
    }

    /// The label the sample puts in brackets. Four buttons use a label other than their name
    /// (`NotificationSampleView`).
    var resultMarker: String {
        switch self {
        case .removeDeliveredById: return "[removeDelivered] "
        case .cancelScheduledById: return "[cancelScheduled] "
        case .setBadgeCount1: return "[setBadgeCount(1)] "
        case .setBadgeCount0: return "[setBadgeCount(0)] "
        default: return "[\(rawValue.prefix(1).lowercased() + rawValue.dropFirst())] "
        }
    }

    /// The text the sample shows instead of the operation's result when the permission is not
    /// granted (`runWithPermission`); it carries no bracketed label.
    static let notGrantedText = "Notification permission is not granted. Please request permission first."
}

/// `ShareSampleIdentifiers.ButtonName`.
enum ShareButton: String, CaseIterable {
    case shareText = "ShareText"
    case shareURL = "ShareURL"
    case shareImage = "ShareImage"
    case shareFile = "ShareFile"
    case shareMultipleImages = "ShareMultipleImages"
    case shareMultipleFiles = "ShareMultipleFiles"
    case shareTextAndURL = "ShareTextAndURL"
    case shareExcludingServices = "ShareExcludingServices"
    case shareViaMail = "ShareViaMail"
    case canPerformMail = "CanPerformMail"
    case shareEmpty = "ShareEmpty"
    case shareInvalidURL = "ShareInvalidURL"
    case shareMissingFile = "ShareMissingFile"
    case shareMissingImage = "ShareMissingImage"
    case shareUnknownService = "ShareUnknownService"

    var identifier: String { SampleScreen.share.buttonPrefix + rawValue }

    /// The label the sample puts in brackets (`[shareText] ...`).
    var label: String { rawValue.prefix(1).lowercased() + rawValue.dropFirst() }

    var resultMarker: String { "[\(label)] " }

    /// The three buttons that name a service go to `realservice` (U-13); every other button can
    /// open the picker, the error ones too when the library breaks (design 5.4).
    fileprivate var requiredCategory: DeviceCategory {
        switch self {
        case .shareViaMail, .canPerformMail, .shareUnknownService:
            return .realservice
        default:
            return .sharepicker
        }
    }
}

/// The identifier inventory of each screen (design 4.1), for I1a〜I1d.
enum SampleInventory {

    static func expectedButtons(_ screen: SampleScreen) -> [String] {
        switch screen {
        case .dialog: return DialogButton.allCases.map(\.identifier)
        case .notification: return NotificationButton.allCases.map(\.identifier)
        case .share: return ShareButton.allCases.map(\.identifier)
        case .clipboard: return clipboardButtonNames.map { screen.buttonPrefix + $0 }
        }
    }

    /// Every identifier of the screen that is not a button.
    static func expectedNonButtons(_ screen: SampleScreen) -> [String] {
        switch screen {
        case .dialog:
            return [screen.resultIdentifier, "dialog.resultHistory"]
        case .notification:
            return [screen.resultIdentifier, "notification.lastEvent", "notification.launchCopy"]
                + ["permission", "show", "updateCancelRemove", "schedule", "query", "badge", "category"]
                    .map { "notification.section.\($0)" }
        case .share:
            return [screen.resultIdentifier]
                + ["pickerBasic", "pickerMultiple", "pickerFilter", "directService", "error"].map { "share.section.\($0)" }
        case .clipboard:
            return [screen.resultIdentifier, "clipboard.scopePicker", "clipboard.activeScope",
                    "clipboard.resultSequence", "clipboard.observeStatus", "clipboard.reachedCodes",
                    "clipboard.toggle.localOnly"]
                + clipboardPasteContainer
                + ["scope", "copy", "copyOptions", "append", "read", "detect", "observe", "pasteControl",
                   "clear", "errorCases"].map { "clipboard.section.\($0)" }
        }
    }

    /// `clipboard.pasteButton` (the `NSViewRepresentable` around the `PasteButton`) does not reach the
    /// accessibility tree on macOS 15 (stage 0b, 15.8.3); design 4.1 counts it. On 26 it is expected
    /// until U-30 shows otherwise.
    private static var clipboardPasteContainer: [String] {
        SampleUITestCase.osMajorVersion >= 26 ? ["clipboard.pasteButton"] : []
    }

    /// `sampleButton("<name>")` of `ClipboardSampleView`, in the order of the screen (36).
    static let clipboardButtonNames = [
        "CreateNamedPasteboard", "CreateUniquePasteboard", "RemoveCurrentPasteboard", "RemoveGeneral",
        "CreateEmptyNamedPasteboard", "CopyText", "CopyURL", "CopyImage", "CopyMultipleItems",
        "CopyMultipleRepresentations", "CopyPartialPasteContent", "CopyEmpty", "CopyEmptyRepresentations",
        "CopyWithCurrentOptions", "CopyThenAppend", "AppendWithLastOwnership", "AppendWithStaleOwnership",
        "Read", "ReadDataPlainText", "Snapshot", "SnapshotFiltered", "SnapshotEmptyFilter", "AccessBehavior",
        "DetectPatterns", "DetectValues", "DetectMetadata", "DetectEmptyPatterns", "StartObserving",
        "StartObservingInvalidInterval", "StopObserving", "CheckForegroundChange", "MakePasteButtonInvalidType",
        "MakePasteButtonUndeclaredType", "Clear", "ExpectFailureThatSucceeds", "ResetReachedCodes"
    ]
}

// MARK: - Result line (U-1, U-3)

/// The result line's value `#<n> <text>`, read as one value.
struct ShownResult: Equatable {
    let sequence: Int
    let text: String
}

enum ResultLine {

    static let initial = "Result will be displayed here"

    /// The full text written by the screens' `updateResult` (U-1).
    static func expected(success: Bool, _ body: String) -> String {
        "\(success ? "✅" : "❌") \nResult: \(body)"
    }

    /// `#<n> <text>` -> (n, text). Anything else is nil.
    static func parse(_ value: String) -> ShownResult? {
        guard value.hasPrefix("#"), let space = value.firstIndex(of: " ") else { return nil }
        let digits = value[value.index(after: value.startIndex)..<space]
        guard !digits.isEmpty, digits.allSatisfy(\.isASCII), digits.allSatisfy(\.isNumber),
              let sequence = Int(digits) else { return nil }
        return ShownResult(sequence: sequence, text: String(value[value.index(after: space)...]))
    }

    enum Verdict: Equatable {
        /// The line has not moved past `before` yet.
        case pending
        /// The next result, carrying the marker of the operation.
        case accepted
        /// The line moved past the next result (more than one completion arrived).
        case overtaken
        /// The next result does not carry the marker of the operation.
        case foreign
    }

    /// Whether `shown` is the result of the operation started at `before` (U-3). The marker is
    /// anchored right after `Result: ` (a bare substring would let `[shareURL]` stand in for
    /// `[shareURLX]` or a detail word for a label. `common.md`).
    static func judge(_ shown: ShownResult, before: Int, marker: String) -> Verdict {
        if shown.sequence <= before { return .pending }
        if shown.sequence > before + 1 { return .overtaken }
        let anchored = [expected(success: true, marker), expected(success: false, marker)]
        return anchored.contains(where: { shown.text.hasPrefix($0) }) ? .accepted : .foreign
    }
}

// MARK: - Overlay check (design 5.0)

/// One on-screen window as the overlay check reads it: owner, layer, alpha and bounds only (no
/// name, title or hierarchy).
struct ScreenWindow: Equatable {
    let pid: Int32
    /// The owner's bundle identifier, when the owner is an app with one.
    let owner: String?
    let layer: Int
    let alpha: Double
    let bounds: CGRect
}

enum OverlayVerdict: Equatable {
    /// The frontmost window that takes the click at the point belongs to an allowed owner, and no
    /// Notification Center window in front of it overlaps the element.
    case clear
    /// A window of another owner takes the click.
    case blocked
    /// A Notification Center window covers the point or overlaps the element.
    case notificationCenter
    /// No window takes the click at the point.
    case noWindow
}

/// The pure rule of the check before a press (design 5.0). Kept as a function of its inputs so
/// that it can be checked and broken directly (`SupportRuleTests`).
enum OverlayRule {

    /// `CGWindowLevelForKey(.cursorWindow)`: the cursor and anything above it take no click.
    static let cursorLayer = 2_147_483_630

    /// Windows that take no click: fully transparent ones, the cursor level and above, and the
    /// full-display windows of the fixed system owners (`SystemLabels.passiveFullDisplayOwners`;
    /// measured on the 15.8.3 VM in stage 0c). Any other window in front of the sample blocks.
    static func isPassive(_ window: ScreenWindow, displays: [CGRect]) -> Bool {
        if window.alpha <= 0 { return true }
        if window.layer >= cursorLayer { return true }
        if let owner = window.owner, SystemLabels.passiveFullDisplayOwners.contains(owner),
           displays.contains(window.bounds) {
            return true
        }
        return false
    }

    /// `windows` are front to back (`CGWindowListCopyWindowInfo` order). `notificationAreas` are the
    /// frames of Notification Center's banner list (`AXNotificationListItems`): on the 15.8.3 VM the
    /// banners have no window of their own and are drawn inside Notification Center's full-display
    /// window, which the window rule passes over (stage 0c 2.3), so a banner over the point is found
    /// only through them.
    static func verdict(point: CGPoint, elementFrame: CGRect, windows: [ScreenWindow],
                        displays: [CGRect], allowedPIDs: Set<Int32>,
                        notificationAreas: [CGRect] = []) -> OverlayVerdict {
        let active = windows.filter { !isPassive($0, displays: displays) }
        guard let hitIndex = active.firstIndex(where: { $0.bounds.contains(point) }) else {
            return .noWindow
        }
        let hit = active[hitIndex]
        guard allowedPIDs.contains(hit.pid) else {
            return hit.owner == SystemLabels.notificationCenterBundleIdentifier ? .notificationCenter : .blocked
        }
        let notificationInFront = active[..<hitIndex].contains {
            $0.owner == SystemLabels.notificationCenterBundleIdentifier && $0.bounds.intersects(elementFrame)
        }
        if notificationInFront || notificationAreas.contains(where: { $0.contains(point) }) {
            return .notificationCenter
        }
        return .clear
    }
}

/// Reads the on-screen windows for `OverlayRule`. Read-only; needs no token (design 5.0).
enum OverlayCheck {

    /// Front to back, on screen only, without desktop elements. Throws when the list cannot be read.
    static func readWindows() throws -> [ScreenWindow] {
        guard let list = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID)
                as? [[String: Any]] else {
            throw SampleUITestError(.overlay, "the window list could not be read")
        }
        var owners: [Int32: String?] = [:]
        return try list.map { entry in
            guard let pid = (entry[kCGWindowOwnerPID as String] as? NSNumber)?.int32Value,
                  let layer = (entry[kCGWindowLayer as String] as? NSNumber)?.intValue,
                  let boundsDictionary = entry[kCGWindowBounds as String] as? NSDictionary,
                  let bounds = CGRect(dictionaryRepresentation: boundsDictionary as CFDictionary) else {
                throw SampleUITestError(.overlay, "a window lacks its owner, layer or bounds")
            }
            let alpha = (entry[kCGWindowAlpha as String] as? NSNumber)?.doubleValue ?? 1
            let owner: String?
            if let known = owners[pid] {
                owner = known
            } else {
                owner = NSRunningApplication(processIdentifier: pid)?.bundleIdentifier
                owners[pid] = owner
            }
            return ScreenWindow(pid: pid, owner: owner, layer: layer, alpha: alpha, bounds: bounds)
        }
    }

    /// Bounds of the active displays, in the same global coordinates as the window bounds.
    static func displays() -> [CGRect] {
        var count: UInt32 = 0
        guard CGGetActiveDisplayList(0, nil, &count) == .success, count > 0 else { return [] }
        var ids = [CGDirectDisplayID](repeating: 0, count: Int(count))
        guard CGGetActiveDisplayList(count, &ids, &count) == .success else { return [] }
        return ids.prefix(Int(count)).map { CGDisplayBounds($0) }
    }

    /// Frames of Notification Center's banner list (identifier `AXNotificationListItems`; no label
    /// is read). Empty when Notification Center does not run. Read from one snapshot: resolving the
    /// elements one by one failed the test when a banner went between the count and the frame
    /// (stage 0c 2.3). Throws when the tree cannot be read.
    static func notificationAreas() throws -> [CGRect] {
        guard !pids(of: SystemLabels.notificationCenterBundleIdentifier).isEmpty else { return [] }
        let center = XCUIApplication(bundleIdentifier: SystemLabels.notificationCenterBundleIdentifier)
        let root: XCUIElementSnapshot
        do {
            root = try center.snapshot()
        } catch {
            throw SampleUITestError(.overlay, "Notification Center's tree could not be read")
        }
        var frames: [CGRect] = []
        func visit(_ node: XCUIElementSnapshot) {
            if node.identifier == SystemLabels.notificationListIdentifier, node.frame.width > 0, node.frame.height > 0 {
                frames.append(node.frame)
            }
            for child in node.children {
                visit(child)
            }
        }
        visit(root)
        return frames
    }

    /// Processes of `bundleIdentifier` that run now.
    static func pids(of bundleIdentifier: String) -> Set<Int32> {
        Set(NSRunningApplication.runningApplications(withBundleIdentifier: bundleIdentifier).map(\.processIdentifier))
    }

    /// The process of the frontmost app.
    static func frontmostPID() -> Int32? {
        NSWorkspace.shared.frontmostApplication?.processIdentifier
    }
}

/// What an element pressed through `SampleApp.guardedClick` belongs to (design 5.0).
enum PressTarget {
    /// A button or scroll view of the sample's window, an alert or the picker of the sample.
    case sampleWindow
    /// An open or save panel: the sample, or the panel view service when it owns the window.
    case panel
}

// MARK: - Inventory snapshot

struct InventorySnapshot {
    /// Identifiers of the screen's buttons, except the excluded kinds below ("" = none).
    let buttons: [String]
    /// Non-button elements whose identifier starts with the screen's prefix.
    let identifiedNonButtons: [String]
    /// Buttons whose identifier starts with `_XCUI:` (close, minimize, full screen).
    let windowButtons: Int
    /// Buttons with the back button's identifier inside the toolbar.
    let backButtons: Int
    /// Buttons inside a scroll bar (its page areas, no identifier).
    let scrollBarParts: Int
    /// The Clipboard screen's `PasteButton` (no identifier; one of `SystemLabels.paste`).
    let pasteButtons: Int
}

// MARK: - Sample app

final class SampleApp {

    private let app = XCUIApplication()
    let session: UITestSession

    static let launchTimeout: TimeInterval = 10
    static let elementTimeout: TimeInterval = 10
    /// Alerts, panels and the picker (design 6.2).
    static let systemUITimeout: TimeInterval = 5
    /// "No extra completion" (U-3, U-14 (a)).
    static let quietPeriod: TimeInterval = 2
    /// How long a window of another owner may cover an element before the press fails.
    static let overlayTimeout: TimeInterval = 5
    /// How long a Notification Center window may cover an element before the press fails (5.0).
    static let notificationOverlayTimeout: TimeInterval = 10

    /// When the last guarded click was sent (after the checks). The cold start's T0 is the click of
    /// ShowTimeInterval, not the start of its scrolling and checks (NC1〜NC3).
    private(set) var lastClickAt: Date?

    init(session: UITestSession) {
        self.session = session
    }

    /// The sample's `XCUIApplication`, for the other trusted Support files (`Panels`, `SharePicker`,
    /// `SampleAlert`). Test classes do not use it (closed source rule, design 6.1).
    var supportRoot: XCUIApplication { app }

    /// Moves the pointer onto the result line of `screen` (the sample's window), for example off a
    /// banner it hovered (a banner under the pointer does not hide itself. Stage 0c 2.3). Not a click.
    func hoverOnResult(_ screen: SampleScreen) throws {
        let element = try exactlyOne(app.staticTexts.matching(identifier: screen.resultIdentifier),
                                     screen.resultIdentifier, step: .resultShape)
        try checkBeforePress(element, .sampleWindow, name: "hover on \(screen.resultIdentifier)")
        element.hover()
        try session.checkInterruption()
    }

    // MARK: Lifecycle

    /// Launches the sample (a new process). The window is not placed by the test; it is checked to
    /// lie on a display (U-15).
    func launch() throws {
        app.launchArguments = ["-ApplePersistenceIgnoreState", "YES"]
        app.launch()
        guard app.wait(for: .runningForeground, timeout: Self.launchTimeout) else {
            throw SampleUITestError(.launch, "the sample did not come to the foreground")
        }
        try session.checkInterruption()
        let window = try exactlyOne(app.windows, "window of the sample", step: .launch)
        let frame = window.frame
        guard OverlayCheck.displays().contains(where: { $0.contains(frame) }) else {
            throw SampleUITestError(.launch, "the sample's window is not inside a display: \(frame)")
        }
    }

    /// Terminates the sample at the end of a test; never throws.
    func terminateQuietly() {
        if app.state != .notRunning {
            app.terminate()
        }
    }

    var state: XCUIApplication.State { app.state }

    /// Waits until the sample is in `state` (no press).
    func waitForState(_ state: XCUIApplication.State, timeout: TimeInterval, step: StepCode) throws {
        guard app.wait(for: state, timeout: timeout) else {
            throw SampleUITestError(step, "the sample did not become \(state.rawValue) in \(timeout)s (now \(app.state.rawValue))")
        }
        try session.checkInterruption()
    }

    /// Brings the running sample to the front (U-15, N3, N24). Not a press: no element is clicked.
    func activate() throws {
        guard app.state == .runningBackground || app.state == .runningForeground else {
            throw SampleUITestError(.notForeground, "the sample is not running (\(app.state.rawValue))")
        }
        app.activate()
        try waitForState(.runningForeground, timeout: Self.launchTimeout, step: .notForeground)
    }

    /// Stops the sample for a cold start (NC1〜NC3): `terminate()` and wait for `notRunning`.
    /// Returns the time it became `notRunning`.
    func terminateForColdStart(_ token: ColdStartToken) throws -> Date {
        app.terminate()
        try waitForState(.notRunning, timeout: Self.launchTimeout, step: .coldStart)
        return Date()
    }

    /// After a notification woke the sample: waits for the foreground without `launch()` (that
    /// would replace the woken process) and checks that the window lies on a display (U-15; the woken
    /// process did not get `-ApplePersistenceIgnoreState`).
    func adoptWokenProcess(_ token: ColdStartToken, timeout: TimeInterval) throws {
        try waitForState(.runningForeground, timeout: timeout, step: .coldStart)
        _ = try samplePID()
        let window = try waitForExactlyOne(app.windows, "window of the woken sample", timeout: Self.launchTimeout,
                                           step: .coldStart)
        let frame = window.frame
        guard OverlayCheck.displays().contains(where: { $0.contains(frame) }) else {
            throw SampleUITestError(.coldStart, "the woken sample's window is not inside a display: \(frame)")
        }
    }

    /// The process of the sample: exactly one must run.
    func samplePID() throws -> Int32 {
        let pids = OverlayCheck.pids(of: SystemLabels.sampleBundleIdentifier)
        guard pids.count == 1, let pid = pids.first else {
            throw SampleUITestError(.overlay, "expected exactly one sample process, found \(pids.count)")
        }
        return pid
    }

    // MARK: Navigation

    /// Opens a screen from the menu by its card (`menu.<screen>`). Opening the Clipboard screen only
    /// registers the paste button's receiver; it does not touch the pasteboard (design 5.1 M1a).
    func open(_ screen: SampleScreen) throws {
        let card = try exactlyOne(app.buttons.matching(identifier: screen.menuIdentifier), screen.menuIdentifier,
                                  step: .openScreen)
        try guardedClick(card, .sampleWindow, name: screen.menuIdentifier)
        try waitForExactlyOne(app.staticTexts.matching(identifier: screen.resultIdentifier), screen.resultIdentifier,
                              timeout: Self.elementTimeout, step: .openScreen)
    }

    /// Presses the toolbar's back button (exactly one `chevron.backward`) and waits for the menu.
    /// macOS 15.8.3 does not return with it (design 5.1, U-33); the tests that use it are 26 only.
    func goBack(from screen: SampleScreen) throws {
        let back = try exactlyOne(app.toolbars.buttons.matching(identifier: SystemLabels.backButtonIdentifier),
                                  "back button", step: .goBack)
        try guardedClick(back, .sampleWindow, name: "back button")
        try waitUntil("the menu after going back", timeout: Self.elementTimeout, step: .goBack) {
            self.menuCardsShown && !self.isShowing(screen)
        }
    }

    /// Whether all four menu cards are shown, once each.
    var menuCardsShown: Bool {
        SampleScreen.allCases.allSatisfy { app.buttons.matching(identifier: $0.menuIdentifier).count == 1 }
    }

    /// Whether the result line of `screen` is shown (the screen is open).
    func isShowing(_ screen: SampleScreen) -> Bool {
        app.staticTexts.matching(identifier: screen.resultIdentifier).count == 1
    }

    // MARK: Buttons

    func tap(_ button: DialogButton) throws {
        guard button.requiredCategory == nil else {
            throw SampleUITestError(.gate, "\(button.identifier) needs a token")
        }
        try tapButton(button.identifier)
    }

    func tap(_ button: DialogButton, _ token: PanelsToken) throws {
        guard button.requiredCategory == .panels else {
            throw SampleUITestError(.gate, "\(button.identifier) is not a panel button")
        }
        try tapButton(button.identifier)
    }

    func tap(_ button: NotificationButton) throws {
        guard button.requiredCategory == nil else {
            throw SampleUITestError(.gate, "\(button.identifier) needs a token")
        }
        try tapButton(button.identifier)
    }

    /// Show*, Schedule*, UpdateById and RequestPermission (`notification`).
    func tap(_ button: NotificationButton, _ token: NotificationToken) throws {
        guard button.requiredCategory == .notification else {
            throw SampleUITestError(.gate, "\(button.identifier) is not a notification button")
        }
        try tapButton(button.identifier)
    }

    /// OpenNotificationSettings (`settings`).
    func tap(_ button: NotificationButton, _ token: SettingsToken) throws {
        guard button.requiredCategory == .settings else {
            throw SampleUITestError(.gate, "\(button.identifier) is not the settings button")
        }
        try tapButton(button.identifier)
    }

    /// SetBadgeCount(1) and SetBadgeCount(0): `badge`, and `notification` because they can ask for
    /// permission (`runWithPermission`. Design 3.3).
    func tap(_ button: NotificationButton, _ token: BadgeToken, _ notification: NotificationToken) throws {
        guard button.requiredCategory == .badge else {
            throw SampleUITestError(.gate, "\(button.identifier) is not a badge button")
        }
        try tapButton(button.identifier)
    }

    func tap(_ button: ShareButton, _ token: SharePickerToken) throws {
        guard button.requiredCategory == .sharepicker else {
            throw SampleUITestError(.gate, "\(button.identifier) is not a picker button")
        }
        try tapButton(button.identifier)
    }

    func tap(_ button: ShareButton, _ token: RealServiceToken) throws {
        guard button.requiredCategory == .realservice else {
            throw SampleUITestError(.gate, "\(button.identifier) is not a service button")
        }
        try tapButton(button.identifier)
    }

    private func tapButton(_ identifier: String) throws {
        let button = try exactlyOne(app.buttons.matching(identifier: identifier), identifier, step: .elementNotUnique)
        try guardedClick(button, .sampleWindow, name: identifier)
        session.recordPressed(identifier)
    }

    // MARK: Result line

    /// The result line of `screen` as one value (`#<n> <text>`).
    func result(_ screen: SampleScreen) throws -> ShownResult {
        let element = try exactlyOne(app.staticTexts.matching(identifier: screen.resultIdentifier),
                                     screen.resultIdentifier, step: .resultShape)
        let value = (element.value as? String) ?? ""
        guard let shown = ResultLine.parse(value) else {
            throw SampleUITestError(.resultShape, "\(screen.resultIdentifier) is not #<n> <text>: \(value)")
        }
        return shown
    }

    func resultSequence(_ screen: SampleScreen) throws -> Int {
        try result(screen).sequence
    }

    /// The second step of an operation (U-3): waits until the result line holds the next result
    /// after `before` with `marker`, and returns its text. Fails at once when the line passes it or
    /// the next result is not of this operation.
    @discardableResult
    func waitForNextResult(_ screen: SampleScreen, after before: Int, marker: String,
                           timeout: TimeInterval = SampleApp.elementTimeout) throws -> String {
        let deadline = Date().addingTimeInterval(timeout)
        var last = try result(screen)
        while true {
            switch ResultLine.judge(last, before: before, marker: marker) {
            case .accepted:
                try session.checkInterruption()
                return last.text
            case .overtaken:
                throw SampleUITestError(.extraResult, "\(screen.resultIdentifier) passed #\(before + 1): #\(last.sequence) \(last.text)")
            case .foreign:
                throw SampleUITestError(.resultShape, "\(screen.resultIdentifier) #\(last.sequence) is not of \(marker): \(last.text)")
            case .pending:
                guard Date() < deadline else {
                    throw SampleUITestError(.resultTimeout, "\(screen.resultIdentifier) stayed at #\(last.sequence) for \(timeout)s waiting for \(marker)")
                }
                Thread.sleep(forTimeInterval: 0.1)
                last = try result(screen)
            }
        }
    }

    /// No further result arrives for 2 seconds after the result `sequence` (U-3, U-14 (a)).
    func expectNoFurtherResult(_ screen: SampleScreen, sequence: Int) throws {
        let deadline = Date().addingTimeInterval(Self.quietPeriod)
        repeat {
            let now = try result(screen)
            guard now.sequence == sequence else {
                throw SampleUITestError(.extraResult, "\(screen.resultIdentifier) moved from #\(sequence) to #\(now.sequence): \(now.text)")
            }
            Thread.sleep(forTimeInterval: 0.1)
        } while Date() < deadline
        try session.checkInterruption()
    }

    /// The value of `notification.lastEvent` (design 4.3), parsed.
    func lastEvent() throws -> LastEvent {
        let element = try exactlyOne(app.staticTexts.matching(identifier: "notification.lastEvent"),
                                     "notification.lastEvent", step: .lastEvent)
        let value = (element.value as? String) ?? ""
        guard let event = LastEvent.parse(value) else {
            throw SampleUITestError(.lastEvent, "notification.lastEvent is not #<n> kind=...: \(value)")
        }
        return event
    }

    /// The value of `notification.launchCopy` (`copy=<12 hex digits>`. U-21).
    func launchCopy() throws -> String {
        let element = try exactlyOne(app.staticTexts.matching(identifier: "notification.launchCopy"),
                                     "notification.launchCopy", step: .launchCopy)
        let value = (element.value as? String) ?? ""
        guard LaunchCopy.isWellFormed(value) else {
            throw SampleUITestError(.launchCopy, "notification.launchCopy is not copy=<12 hex>: \(value)")
        }
        return value
    }

    /// The value of `dialog.resultHistory` (D5).
    func dialogResultHistory() throws -> String {
        let element = try exactlyOne(app.staticTexts.matching(identifier: "dialog.resultHistory"),
                                     "dialog.resultHistory", step: .resultShape)
        return (element.value as? String) ?? ""
    }

    // MARK: Dialog's alert

    /// The sample's `NSAlert` (the dialog that holds `action-button-1`).
    func alert() -> SampleAlert {
        SampleAlert(sample: self)
    }

    // MARK: Guarded operations (design 5.0)

    /// Scrolls the element into its scroll view when needed, runs the check before the press, clicks
    /// (with `modifiers` held) and reads the interruption mark.
    func guardedClick(_ element: XCUIElement, _ target: PressTarget, name: String,
                      modifiers: XCUIElement.KeyModifierFlags = []) throws {
        if target == .sampleWindow {
            try scrollIntoViewIfNeeded(element, name: name)
        }
        try checkBeforePress(element, target, name: name)
        lastClickAt = Date()
        if modifiers.isEmpty {
            element.click()
        } else {
            XCUIElement.perform(withKeyModifiers: modifiers) {
                element.click()
            }
        }
        try session.checkInterruption()
    }

    /// Sends a key to `element` after the check for keys (design 5.0): the sample is the frontmost
    /// app, and `focused` (when given) has the keyboard focus.
    func guardedTypeKey(_ key: String, modifiers: XCUIElement.KeyModifierFlags = [], to element: XCUIElement,
                        focused: XCUIElement? = nil, name: String) throws {
        try checkBeforeKey(focused: focused, name: name)
        element.typeKey(key, modifierFlags: modifiers)
        try session.checkInterruption()
    }

    /// Types text into `field` after the check for keys; `field` must have the keyboard focus.
    func guardedTypeText(_ text: String, into field: XCUIElement, name: String) throws {
        try checkBeforeKey(focused: field, name: name)
        field.typeText(text)
        try session.checkInterruption()
    }

    /// Whether `element` has the keyboard focus; nil when it cannot be read.
    func hasKeyboardFocus(_ element: XCUIElement) -> Bool? {
        element.value(forKey: "hasKeyboardFocus") as? Bool
    }

    private func checkBeforeKey(focused: XCUIElement?, name: String) throws {
        guard app.state == .runningForeground else {
            throw SampleUITestError(.notForeground, "the sample is not in the foreground before the key for \(name)")
        }
        let pid = try samplePID()
        guard OverlayCheck.frontmostPID() == pid else {
            throw SampleUITestError(.keyFocus, "the sample is not the frontmost app before the key for \(name)")
        }
        if let focused {
            guard hasKeyboardFocus(focused) == true else {
                throw SampleUITestError(.keyFocus, "\(name) does not have the keyboard focus")
            }
        }
    }

    private func checkBeforePress(_ element: XCUIElement, _ target: PressTarget, name: String) throws {
        let start = Date()
        while true {
            let verdict = try overlayVerdict(element, target, name: name)
            let waited = Date().timeIntervalSince(start)
            switch verdict {
            case .clear:
                return
            case .notificationCenter:
                guard waited < Self.notificationOverlayTimeout else {
                    throw SampleUITestError(.notificationOverlay, "a Notification Center window stayed over \(name)")
                }
            case .blocked, .noWindow:
                guard waited < Self.overlayTimeout else {
                    throw SampleUITestError(.overlay, "\(name) is covered by another owner's window or no window takes the click (\(verdict))")
                }
            }
            Thread.sleep(forTimeInterval: 0.2)
        }
    }

    private func overlayVerdict(_ element: XCUIElement, _ target: PressTarget, name: String) throws -> OverlayVerdict {
        guard app.state == .runningForeground else {
            throw SampleUITestError(.notForeground, "the sample is not in the foreground before pressing \(name)")
        }
        let frame = element.frame
        guard frame.width > 0, frame.height > 0 else {
            throw SampleUITestError(.overlay, "\(name) has an empty frame")
        }
        var allowed: Set<Int32> = [try samplePID()]
        if target == .panel {
            allowed.formUnion(OverlayCheck.pids(of: SystemLabels.openAndSavePanelServiceBundleIdentifier))
        }
        return OverlayRule.verdict(point: CGPoint(x: frame.midX, y: frame.midY), elementFrame: frame,
                                   windows: try OverlayCheck.readWindows(), displays: OverlayCheck.displays(),
                                   allowedPIDs: allowed, notificationAreas: try OverlayCheck.notificationAreas())
    }

    // MARK: Scrolling

    /// Scrolls until `element` lies wholly inside the scroll view that holds it. A button outside
    /// the viewport still reports a frame and sometimes `isHittable`, and the click lands on
    /// whatever sits there (stage 0b 5: on the Notification screen it hit nothing).
    private func scrollIntoViewIfNeeded(_ element: XCUIElement, name: String) throws {
        let holders = app.scrollViews.containing(NSPredicate(format: "identifier == %@", element.identifier))
        guard !element.identifier.isEmpty, holders.count > 0 else { return }
        let scrollView = try exactlyOne(holders, "scroll view holding \(name)", step: .scroll)
        var direction: CGFloat = -1
        var distances: [CGFloat] = []
        for _ in 0..<16 {
            let viewport = scrollView.frame
            let frame = element.frame
            if viewport.minY <= frame.minY && frame.maxY <= viewport.maxY { return }
            let offset = frame.midY - viewport.midY
            distances.append(abs(offset))
            // The sign of a scroll delta is not the sign of the movement on every input device, and
            // a boundary can absorb a scroll; judging each attempt by whether it got closer covers
            // both (as the Clipboard tests' `scrollIntoView`).
            if distances.count >= 2, distances[distances.count - 1] >= distances[distances.count - 2] {
                direction = -direction
            }
            try checkBeforePress(scrollView, .sampleWindow, name: "scroll view holding \(name)")
            scrollView.scroll(byDeltaX: 0, deltaY: direction * min(abs(offset), 200))
            try session.checkInterruption()
        }
        throw SampleUITestError(.scroll, "\(name) could not be scrolled into view")
    }

    // MARK: Inventory

    /// Collects the buttons and identified elements of `screen` from one snapshot, without
    /// scrolling (design 5.1). Window buttons, the toolbar's back button, scroll bar parts and the
    /// Clipboard screen's `PasteButton` are counted apart, so the test can check each kind.
    func inventorySnapshot(_ screen: SampleScreen) throws -> InventorySnapshot {
        let root = try app.snapshot()
        var buttons: [String] = []
        var nonButtons: [String] = []
        var windowButtons = 0
        var backButtons = 0
        var scrollBarParts = 0
        var pasteButtons = 0

        func visit(_ node: XCUIElementSnapshot, parent: XCUIElement.ElementType?, inToolbar: Bool) {
            let toolbar = inToolbar || node.elementType == .toolbar
            if node.elementType == .button {
                if node.identifier.hasPrefix(SystemLabels.windowButtonPrefix) {
                    windowButtons += 1
                } else if toolbar && node.identifier == SystemLabels.backButtonIdentifier {
                    backButtons += 1
                } else if parent == .scrollBar && node.identifier.isEmpty {
                    scrollBarParts += 1
                } else if screen == .clipboard && node.identifier.isEmpty && SystemLabels.paste.contains(node.label) {
                    pasteButtons += 1
                } else {
                    buttons.append(node.identifier)
                }
            } else if node.identifier.hasPrefix(screen.identifierPrefix) {
                nonButtons.append(node.identifier)
            }
            for child in node.children {
                visit(child, parent: node.elementType, inToolbar: toolbar)
            }
        }
        visit(root, parent: nil, inToolbar: false)
        try session.checkInterruption()
        return InventorySnapshot(buttons: buttons, identifiedNonButtons: nonButtons, windowButtons: windowButtons,
                                 backButtons: backButtons, scrollBarParts: scrollBarParts, pasteButtons: pasteButtons)
    }

    // MARK: Waiting

    /// Fixed wait used only to confirm that something does not happen (U-14 (a)).
    func observeQuietly(for seconds: TimeInterval) {
        Thread.sleep(forTimeInterval: seconds)
    }

    /// Polls `condition` every 0.1 s until it holds (no fixed wait. U-14).
    func waitUntil(_ what: String, timeout: TimeInterval, step: StepCode, _ condition: () throws -> Bool) throws {
        let deadline = Date().addingTimeInterval(timeout)
        while try !condition() {
            guard Date() < deadline else {
                throw SampleUITestError(step, "\(what) did not happen in \(timeout)s")
            }
            Thread.sleep(forTimeInterval: 0.1)
        }
        try session.checkInterruption()
    }

    /// Waits until `query` has a match, then requires exactly one (U-2).
    @discardableResult
    func waitForExactlyOne(_ query: XCUIElementQuery, _ name: String, timeout: TimeInterval,
                           step: StepCode) throws -> XCUIElement {
        guard query.firstMatch.waitForExistence(timeout: timeout) else {
            throw SampleUITestError(step, "\(name) did not appear in \(timeout)s")
        }
        let element = try exactlyOne(query, name, step: step)
        try session.checkInterruption()
        return element
    }
}

/// Returns the only element of `query`; with 0 or 2+ matches it throws without touching anything
/// (U-2).
func exactlyOne(_ query: XCUIElementQuery, _ name: String, step: StepCode) throws -> XCUIElement {
    let count = query.count
    guard count == 1 else {
        throw SampleUITestError(step, "expected exactly one \(name), found \(count)")
    }
    return query.element
}

// MARK: - Alert of the sample

/// The sample's `NSAlert` (ShowDialog). Found as the one dialog that holds `action-button-1`.
struct SampleAlert {
    fileprivate let sample: SampleApp

    private var query: XCUIElementQuery {
        sample.supportRoot.dialogs.containing(.button, identifier: SystemLabels.alertButtonIdentifier(1))
    }

    @discardableResult
    func waitShown() throws -> XCUIElement {
        try sample.waitForExactlyOne(query, "alert", timeout: SampleApp.systemUITimeout, step: .alert)
    }

    func waitGone() throws {
        guard query.firstMatch.waitForNonExistence(timeout: SampleApp.systemUITimeout) else {
            throw SampleUITestError(.alert, "the alert did not close")
        }
        try sample.session.checkInterruption()
    }

    var count: Int { query.count }

    /// The values of the alert's static texts (the sample's own title and message).
    func texts() throws -> [String] {
        try exactlyOne(query, "alert", step: .alert).staticTexts.allElementsBoundByIndex.map { ($0.value as? String) ?? "" }
    }

    /// `action-button-<n>`'s title.
    func buttonTitle(_ number: Int) throws -> String {
        try button(number).title
    }

    var buttonCount: Int { (try? exactlyOne(query, "alert", step: .alert).buttons.count) ?? -1 }

    func helpButtonCount() throws -> Int {
        try exactlyOne(query, "alert", step: .alert).buttons.matching(NSPredicate(format: "label IN %@", SystemLabels.help)).count
    }

    func suppressionCheckbox() throws -> XCUIElement {
        try exactlyOne(try exactlyOne(query, "alert", step: .alert).checkBoxes.matching(identifier: SystemLabels.alertSuppressionCheckbox),
                       "suppression checkbox", step: .alert)
    }

    func press(_ number: Int) throws {
        try sample.guardedClick(try button(number), .sampleWindow, name: SystemLabels.alertButtonIdentifier(number))
    }

    func pressHelp() throws {
        let help = try exactlyOne(try exactlyOne(query, "alert", step: .alert).buttons.matching(NSPredicate(format: "label IN %@", SystemLabels.help)),
                                  "help button", step: .alert)
        try sample.guardedClick(help, .sampleWindow, name: "help button")
    }

    func toggleSuppression() throws {
        try sample.guardedClick(try suppressionCheckbox(), .sampleWindow, name: "suppression checkbox")
    }

    /// Sends a key to the alert (Return, Escape or a key equivalent). The sample must be in front
    /// and exactly one alert open.
    func typeKey(_ key: String) throws {
        let alert = try exactlyOne(query, "alert", step: .alert)
        try sample.guardedTypeKey(key, to: alert, name: "alert key")
    }

    private func button(_ number: Int) throws -> XCUIElement {
        try exactlyOne(try exactlyOne(query, "alert", step: .alert).buttons.matching(identifier: SystemLabels.alertButtonIdentifier(number)),
                       SystemLabels.alertButtonIdentifier(number), step: .alert)
    }
}
