//
//  SampleApp.swift
//  IosLibraryExampleUITests
//
//  The only way new test classes operate the sample app (UI test design 6.1). Trusted Support
//  file. It owns the `XCUIApplication`, finds every element of the sample by its accessibility
//  identifier with exactly one match (U-2), presses buttons that need a token only through the
//  token-taking entry points (U-9), records the pressed buttons (3.7), and checks the
//  interruption mark right after each operation (U-8).
//
//  The identifier strings are copies of the app's `*SampleIdentifiers` enums: the test bundle is
//  a separate process and cannot reference them. Design section 5.1 is the list.
//

import XCTest
import Foundation

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

enum DialogButton: String, CaseIterable {
    case showAlert
    case showConfirmDialog
    case showDestructiveDialog
    case showActionSheet
    case showTextInputDialog
    case showLoginDialog
    // Swift API (2.0.0) section (1b SA-01 to SA-05).
    case showRequestAlert
    case showRequestConfirm
    case showRequestDestructive
    case showRequestActionSheet
    case showRequestTextInput
    case showRequestLogin
    case showTwoInOneTurn
    case showThenCancel
    case showCoverThenCancel
    case showThenDismissFromOutside
    // `#if DEBUG` in the sample: the UI tests run the Debug build only (scripts/test_ios.sh builds
    // with the scheme's test action, whose configuration is Debug, for the simulator and the device).
    case showAfter3Seconds

    var identifier: String { SampleScreen.dialog.buttonPrefix + rawValue }

    fileprivate var requiredCategory: DeviceCategory? {
        self == .showLoginDialog || self == .showRequestLogin ? .credentials : nil
    }
}

/// The screen the sample presents over a dialog (`showCoverThenCancel`, D19).
enum DialogCover {
    static let identifier = "dialog.cover"
}

enum NotificationButton: String, CaseIterable {
    case requestPermission
    case hasPermission
    case authorizationStatus
    case openNotificationSettings
    case showImmediate
    case showImmediateWithAttachment
    case showTimeInterval
    case showCalendar
    case showLocation
    case updateById
    case cancelById
    case cancelAll
    case removeDeliveredById
    case removeAllDelivered
    case scheduleTimeInterval
    case scheduleCalendar
    case scheduleLocation
    case cancelScheduledById
    case cancelAllScheduled
    case getScheduled
    case getDelivered
    case setBadgeCount1
    case setBadgeCount0
    case registerCategory
    case removeCategory

    var identifier: String { SampleScreen.notification.buttonPrefix + rawValue }

    /// Buttons that post a notification or bring up system UI need `systemui` (U-9, 3.3).
    fileprivate var requiredCategory: DeviceCategory? {
        switch self {
        case .showImmediate, .showImmediateWithAttachment, .showTimeInterval, .showCalendar, .showLocation,
             .scheduleTimeInterval, .scheduleCalendar, .scheduleLocation, .updateById,
             .requestPermission, .openNotificationSettings:
            return .systemui
        case .hasPermission, .authorizationStatus, .cancelById, .cancelAll, .removeDeliveredById,
             .removeAllDelivered, .cancelScheduledById, .cancelAllScheduled, .getScheduled, .getDelivered,
             .setBadgeCount1, .setBadgeCount0, .registerCategory, .removeCategory:
            return nil
        }
    }
}

enum ShareButton: String, CaseIterable {
    case shareText
    case shareURL
    case shareURLWithPreview
    case shareImage
    case shareMultipleImages
    case shareFile
    case shareMultipleFiles
    case shareMultiple
    case shareWithSubject
    case shareExcludingActivities
    case shareEmpty
    case shareInvalidURL
    case shareMissingFile
    case shareMissingImage

    var identifier: String { SampleScreen.share.buttonPrefix + rawValue }
}

/// The Clipboard buttons the new Clipboard tests press (CB1〜CB4). Pressing any of them needs a
/// `ClipboardToken`.
enum ClipboardButton: String, CaseIterable {
    case useGeneral
    case loadText
    case mountPasteControl

    var identifier: String { SampleScreen.clipboard.buttonPrefix + rawValue }
}

/// The system paste control of the Clipboard screen (exists only after `mountPasteControl`).
enum ClipboardPasteControl {
    static let identifier = "clipboard.pasteControl"
    static let summaryIdentifier = "clipboard.pasteSummary"
}

/// The identifier inventory of each screen (design 5.1), for I1a〜I1d.
enum SampleInventory {

    /// Every button identifier of the screen.
    static func expectedButtons(_ screen: SampleScreen) -> [String] {
        switch screen {
        case .dialog:
            return DialogButton.allCases.map(\.identifier)
        case .notification:
            return NotificationButton.allCases.map(\.identifier)
        case .share:
            return ShareButton.allCases.map(\.identifier)
        case .clipboard:
            return clipboardButtonNames.map { screen.buttonPrefix + $0 }
        }
    }

    /// Every identifier of the screen that is not a button.
    static func expectedNonButtons(_ screen: SampleScreen) -> [String] {
        switch screen {
        case .dialog:
            return [screen.resultIdentifier]
        case .notification:
            return [screen.resultIdentifier]
                + ["permission", "show", "updateCancelRemove", "schedule", "query", "badge", "category"]
                    .map { "notification.section.\($0)" }
                + ["sequence", "kind", "notificationId", "actionId", "userText"]
                    .map { "notification.lastEvent.\($0)" }
        case .share:
            return [screen.resultIdentifier]
                + ["text", "url", "image", "file", "combination", "error"].map { "share.section.\($0)" }
        case .clipboard:
            return [screen.resultIdentifier, "clipboard.status", "clipboard.pasteSummary"]
                + ["scope", "copy", "copyOptions", "append", "read", "load", "detect", "observe",
                   "pasteControl", "clear", "errorCases"].map { "clipboard.section.\($0)" }
        }
    }

    /// Buttons of the screen that are excluded explicitly from the inventory: the system paste
    /// button, which exists only after it is mounted (design 3.1 I1d).
    static func excludedButtons(_ screen: SampleScreen) -> [String] {
        screen == .clipboard ? ["clipboard.pasteControl"] : []
    }

    /// `ClipboardSampleIdentifiers.Action` (52) and `ControlAction` (2).
    private static let clipboardButtonNames = [
        "useGeneral", "createNamed", "useFixedNamed", "createUnique", "removeActive", "probeRemoved",
        "copyPlainText", "copyPlainTextEmpty", "copyHtml", "copyURL", "copyImageFile", "copyImageData",
        "copyColor", "copyCustomData", "copyFileFixture", "copyMultipleText", "copyMultiRepresentation",
        "copyDetectionFixture", "copyNumberFixture", "copySearchFixture",
        "copyLocalOnlyTrue", "copyLocalOnlyFalse", "copyBBaseline", "copyExpiring",
        "appendPlainText", "appendURL", "appendUniversalMarker",
        "read", "readData", "snapshot", "snapshotMatching",
        "loadText", "loadURL", "loadImage", "loadFile",
        "detectPatterns", "detectValues",
        "startObserving", "stopObserving", "checkForeground",
        "clear",
        "errMultipleEmpty", "errMultiRepEmpty", "errImageMissing", "errCopyInvalidUTI", "errInvalidURL",
        "errInvalidColor", "errReadInvalidUTI", "errRemoveGeneral", "errObserveMissing", "errEmptyPatterns",
        "errEmptyAcceptedTypes",
        "cancelLoads", "mountPasteControl"
    ]
}

// MARK: - Result line

/// `completion=<n>,callback=<n>` of the Dialog result line (U-3).
struct DialogCounts: Equatable, CustomStringConvertible {
    let completion: Int
    let callback: Int

    var description: String { "completion=\(completion),callback=\(callback)" }

    static func parse(_ value: String) -> DialogCounts? {
        let parts = value.split(separator: ",", omittingEmptySubsequences: false)
        guard parts.count == 2,
              parts[0].hasPrefix("completion="), parts[1].hasPrefix("callback="),
              let completion = Int(parts[0].dropFirst("completion=".count)),
              let callback = Int(parts[1].dropFirst("callback=".count)) else {
            return nil
        }
        return DialogCounts(completion: completion, callback: callback)
    }
}

enum ResultLine {
    /// The full text of a result line written by `updateResult` (U-1).
    static func expected(success: Bool, _ body: String) -> String {
        "\(success ? "✅" : "❌") \nResult: \(body)"
    }

    static let initial = "Result will be displayed here"
}

/// `[getScheduled] count: <n>, ids: [<id>, ...]` / `[getDelivered] ...` of the Notification
/// screen (U-6).
struct NotificationList: Equatable {
    let count: Int
    let ids: [String]

    /// Parses the full result line for `marker` (`[getScheduled]` or `[getDelivered]`).
    static func parse(_ text: String, marker: String) -> NotificationList? {
        let prefix = ResultLine.expected(success: true, "\(marker) count: ")
        guard text.hasPrefix(prefix) else { return nil }
        let rest = text.dropFirst(prefix.count)
        guard let comma = rest.range(of: ", ids: [") else { return nil }
        guard let count = Int(rest[rest.startIndex..<comma.lowerBound]), rest.hasSuffix("]") else { return nil }
        let inner = rest[comma.upperBound..<rest.index(before: rest.endIndex)]
        let ids = inner.isEmpty ? [] : inner.components(separatedBy: ", ")
        return NotificationList(count: count, ids: ids)
    }
}

// MARK: - Inventory snapshot

struct InventoryElement: Equatable {
    let identifier: String
    let frame: CGRect
}

/// A button of the sample's navigation bar. The label is the sample's own text (the back button
/// carries the previous screen's title); nothing of the system is read.
struct NavigationBarButton: Equatable {
    let identifier: String
    let label: String
}

struct InventorySnapshot {
    /// Every button of the screen, except the navigation bar's buttons and the buttons in
    /// `SampleInventory.excludedButtons`. Buttons without an identifier have `""`.
    let buttons: [InventoryElement]
    /// Non-button elements whose identifier starts with the screen's prefix.
    let identifiedNonButtons: [InventoryElement]
    /// The navigation bar's buttons, excluded from `buttons` (the test checks it is only the back
    /// button).
    let navigationBarButtons: [NavigationBarButton]
    /// Buttons excluded by `SampleInventory.excludedButtons`.
    let excludedListedButtons: Int
}

// MARK: - Sample app

struct SampleApp {

    private let app = XCUIApplication(bundleIdentifier: SystemLabels.sampleBundleIdentifier)
    private let session: UITestSession

    static let launchTimeout: TimeInterval = 10
    static let elementTimeout: TimeInterval = 10
    static let dialogTimeout: TimeInterval = 5

    init(session: UITestSession) {
        self.session = session
    }

    // MARK: Lifecycle

    func launch() throws {
        app.launch()
        guard app.wait(for: .runningForeground, timeout: Self.launchTimeout) else {
            throw SampleUITestError("the sample did not come to the foreground")
        }
        try session.checkInterruption()
    }

    func activate() throws {
        app.activate()
        guard app.wait(for: .runningForeground, timeout: Self.launchTimeout) else {
            throw SampleUITestError("the sample did not come to the foreground")
        }
        try waitForSettledWindow()
        try session.checkInterruption()
    }

    /// Waits until the zoom-in animation from the home screen has ended: the window is at the
    /// origin and its frame reads the same twice in a row. Right after `runningForeground` the
    /// frames are still scaled (stage 0c, iOS 26.2), and a tap lands on a stale point.
    private func waitForSettledWindow(timeout: TimeInterval = SampleApp.launchTimeout) throws {
        let deadline = Date().addingTimeInterval(timeout)
        var previous = CGRect.null
        while true {
            let frame = app.windows.firstMatch.frame
            if frame.origin == .zero, frame.width > 0, frame == previous {
                return
            }
            guard Date() < deadline else {
                throw SampleUITestError("the sample's window did not settle: \(frame)")
            }
            previous = frame
            Thread.sleep(forTimeInterval: 0.25)
        }
    }

    func terminate() throws {
        app.terminate()
        guard app.wait(for: .notRunning, timeout: Self.launchTimeout) else {
            throw SampleUITestError("the sample did not stop")
        }
    }

    var isForeground: Bool { app.state == .runningForeground }

    /// Waits until the sample is in the foreground (opened by the system, e.g. from a banner) and
    /// its window has settled. Returns false when it did not come to the foreground.
    func waitForForeground(timeout: TimeInterval) throws -> Bool {
        guard app.wait(for: .runningForeground, timeout: timeout) else { return false }
        try waitForSettledWindow()
        try session.checkInterruption()
        return true
    }

    /// The sample's state now (`notRunning`, `runningBackground`, `runningForeground`, ...).
    var state: XCUIApplication.State { app.state }

    // MARK: Navigation

    /// Opens Dialog, Notification or Share from the menu. Clipboard needs `ClipboardToken`.
    func open(_ screen: SampleScreen) throws {
        guard screen != .clipboard else {
            throw SampleUITestError("the Clipboard screen needs a ClipboardToken")
        }
        try openScreen(screen)
    }

    func openClipboard(_ token: ClipboardToken) throws {
        try openScreen(.clipboard)
    }

    private func openScreen(_ screen: SampleScreen) throws {
        let card = try exactlyOne(app.buttons.matching(identifier: screen.menuIdentifier), screen.menuIdentifier)
        card.tap()
        try session.checkInterruption()
        try waitForExistence(app.staticTexts.matching(identifier: screen.resultIdentifier), screen.resultIdentifier)
    }

    /// Taps the navigation bar's back button.
    func goBackToMenu() throws {
        let back = try exactlyOne(app.navigationBars.buttons, "navigation bar back button")
        back.tap()
        try session.checkInterruption()
        try waitForExistence(app.buttons.matching(identifier: SampleScreen.dialog.menuIdentifier), "menu")
    }

    /// Whether the menu card of `screen` is shown.
    func menuCardExists(_ screen: SampleScreen) -> Bool {
        app.buttons.matching(identifier: screen.menuIdentifier).count == 1
    }

    // MARK: Buttons

    func tap(_ button: DialogButton) throws {
        guard button.requiredCategory == nil else {
            throw SampleUITestError("\(button.identifier) needs a token")
        }
        try tapButton(button.identifier)
    }

    func tap(_ button: DialogButton, _ token: CredentialsToken) throws {
        guard button.requiredCategory == .credentials else {
            throw SampleUITestError("\(button.identifier) is not a credentials button")
        }
        try tapButton(button.identifier)
    }

    func tap(_ button: NotificationButton) throws {
        guard button.requiredCategory == nil else {
            throw SampleUITestError("\(button.identifier) needs a token")
        }
        try tapButton(button.identifier)
    }

    func tap(_ button: NotificationButton, _ token: SystemUIToken) throws {
        guard button.requiredCategory == .systemui else {
            throw SampleUITestError("\(button.identifier) is not a systemui button")
        }
        try tapButton(button.identifier)
    }

    func tap(_ button: ShareButton, _ token: ShareSheetToken) throws {
        try tapButton(button.identifier)
    }

    func tap(_ button: ClipboardButton, _ token: ClipboardToken) throws {
        try tapButton(button.identifier)
    }

    /// Taps a Notification button that needs no token and returns the new result line once
    /// `updates=<n>` has grown by one (U-3).
    @discardableResult
    func press(_ button: NotificationButton) throws -> String {
        let before = try updateCount(.notification)
        try tap(button)
        try waitForUpdateCount(.notification, before + 1)
        return try resultText(.notification)
    }

    /// `press(_:)` for the buttons that need a `SystemUIToken`.
    @discardableResult
    func press(_ button: NotificationButton, _ token: SystemUIToken) throws -> String {
        let before = try updateCount(.notification)
        try tap(button, token)
        try waitForUpdateCount(.notification, before + 1)
        return try resultText(.notification)
    }

    private func tapButton(_ identifier: String) throws {
        let button = try exactlyOne(app.buttons.matching(identifier: identifier), identifier)
        try scrollUntilHittable(button, identifier)
        button.tap()
        session.recordPressed(identifier)
        try session.checkInterruption()
    }

    // MARK: Result line

    /// The label of the result line (the full text).
    func resultText(_ screen: SampleScreen) throws -> String {
        try exactlyOne(app.staticTexts.matching(identifier: screen.resultIdentifier), screen.resultIdentifier).label
    }

    /// The `accessibilityValue` of the result line.
    func resultValue(_ screen: SampleScreen) throws -> String {
        let element = try exactlyOne(app.staticTexts.matching(identifier: screen.resultIdentifier), screen.resultIdentifier)
        return (element.value as? String) ?? ""
    }

    func dialogCounts() throws -> DialogCounts {
        let value = try resultValue(.dialog)
        guard let counts = DialogCounts.parse(value) else {
            throw SampleUITestError("dialog.result value is not completion=<n>,callback=<n>: \(value)")
        }
        return counts
    }

    /// Waits until the Dialog counts are exactly `expected`. Fails at once when a count passes
    /// the expected value.
    func waitForDialogCounts(_ expected: DialogCounts, timeout: TimeInterval = SampleApp.elementTimeout) throws {
        let deadline = Date().addingTimeInterval(timeout)
        var last = try dialogCounts()
        while last != expected {
            if last.completion > expected.completion || last.callback > expected.callback {
                throw SampleUITestError("dialog counts passed the expected \(expected): \(last)")
            }
            guard Date() < deadline else {
                throw SampleUITestError("dialog counts did not reach \(expected) in \(timeout)s: \(last)")
            }
            Thread.sleep(forTimeInterval: 0.2)
            last = try dialogCounts()
        }
        try session.checkInterruption()
    }

    /// `updates=<n>` of the Notification and Share result lines.
    func updateCount(_ screen: SampleScreen) throws -> Int {
        let value = try resultValue(screen)
        guard value.hasPrefix("updates="), let count = Int(value.dropFirst("updates=".count)) else {
            throw SampleUITestError("\(screen.resultIdentifier) value is not updates=<n>: \(value)")
        }
        return count
    }

    /// Waits until `updates=<n>` is exactly `expected`, failing at once when it passes it.
    func waitForUpdateCount(_ screen: SampleScreen, _ expected: Int, timeout: TimeInterval = SampleApp.elementTimeout) throws {
        let deadline = Date().addingTimeInterval(timeout)
        var last = try updateCount(screen)
        while last != expected {
            if last > expected {
                throw SampleUITestError("\(screen.resultIdentifier) updates passed \(expected): \(last)")
            }
            guard Date() < deadline else {
                throw SampleUITestError("\(screen.resultIdentifier) updates did not reach \(expected) in \(timeout)s: \(last)")
            }
            Thread.sleep(forTimeInterval: 0.2)
            last = try updateCount(screen)
        }
        try session.checkInterruption()
    }

    /// Reads `notification.lastEvent.<field>` (its full label).
    func lastEventLabel(_ field: String) throws -> String {
        let identifier = "notification.lastEvent.\(field)"
        return try exactlyOne(app.staticTexts.matching(identifier: identifier), identifier).label
    }

    /// The five labels of the last event, in the order sequence, kind, notificationId, actionId,
    /// userText (design 5.2).
    func lastEvent() throws -> [String] {
        try ["sequence", "kind", "notificationId", "actionId", "userText"].map { try lastEventLabel($0) }
    }

    /// Waits until the last event's sequence is exactly `sequence`, failing at once when it passes.
    func waitForEventSequence(_ sequence: Int, timeout: TimeInterval = SampleApp.elementTimeout) throws {
        let expected = "sequence=\(sequence)"
        let deadline = Date().addingTimeInterval(timeout)
        var last = try lastEventLabel("sequence")
        while last != expected {
            if let value = Int(last.dropFirst("sequence=".count)), value > sequence {
                throw SampleUITestError("the event sequence passed \(sequence): \(last)")
            }
            guard Date() < deadline else {
                throw SampleUITestError("the event sequence did not reach \(sequence) in \(timeout)s: \(last)")
            }
            Thread.sleep(forTimeInterval: 0.2)
            last = try lastEventLabel("sequence")
        }
        try session.checkInterruption()
    }

    /// Presses `GetScheduled` or `GetDelivered` every 0.5 s until the ids are `expected` as a set
    /// (10 s at most. U-6). Each reading must have `count:` equal to the number of ids and no
    /// duplicated id; otherwise it fails at once. Returns the last result line.
    @discardableResult
    func waitForNotificationIDs(
        _ button: NotificationButton,
        _ expected: Set<String>,
        timeout: TimeInterval = SampleApp.elementTimeout
    ) throws -> String {
        let marker: String
        switch button {
        case .getScheduled: marker = "[getScheduled]"
        case .getDelivered: marker = "[getDelivered]"
        default: throw SampleUITestError("\(button.identifier) is not a query button")
        }
        let deadline = Date().addingTimeInterval(timeout)
        while true {
            let text = try press(button)
            guard let list = NotificationList.parse(text, marker: marker) else {
                throw SampleUITestError("unexpected \(marker) result: \(text)")
            }
            guard list.count == list.ids.count else {
                throw SampleUITestError("\(marker) count \(list.count) differs from the ids \(list.ids)")
            }
            guard Set(list.ids).count == list.ids.count else {
                throw SampleUITestError("\(marker) has duplicated ids: \(list.ids)")
            }
            if Set(list.ids) == expected { return text }
            guard Date() < deadline else {
                throw SampleUITestError("\(marker) ids did not become \(expected.sorted()) in \(timeout)s: \(list.ids)")
            }
            Thread.sleep(forTimeInterval: 0.5)
        }
    }

    /// Whether the result line of `screen` is shown (the screen is open).
    func isShowing(_ screen: SampleScreen) -> Bool {
        app.staticTexts.matching(identifier: screen.resultIdentifier).count == 1
    }

    // MARK: Clipboard screen (CB1〜CB4)

    /// The Clipboard result line (`<kind> #<n> [<marker>] <payload>`).
    func clipboardResult(_ token: ClipboardToken) throws -> String {
        try resultText(.clipboard)
    }

    /// The `#<n>` of the Clipboard result line (0 before the first result).
    func clipboardSequence(_ token: ClipboardToken) throws -> Int {
        let text = try resultText(.clipboard)
        guard let hash = text.firstIndex(of: "#") else { return 0 }
        return Int(text[text.index(after: hash)...].prefix { $0.isNumber }) ?? 0
    }

    /// Waits until the Clipboard result line has the sequence `sequence` and returns it.
    @discardableResult
    func waitForClipboardResult(_ token: ClipboardToken, sequence: Int, timeout: TimeInterval = SampleApp.elementTimeout) throws -> String {
        let deadline = Date().addingTimeInterval(timeout)
        var last = try clipboardSequence(token)
        while last != sequence {
            if last > sequence {
                throw SampleUITestError("clipboard.result passed #\(sequence): #\(last)")
            }
            guard Date() < deadline else {
                throw SampleUITestError("clipboard.result did not reach #\(sequence) in \(timeout)s: #\(last)")
            }
            Thread.sleep(forTimeInterval: 0.2)
            last = try clipboardSequence(token)
        }
        try session.checkInterruption()
        return try resultText(.clipboard)
    }

    /// `Paste result: <summary>` of the Clipboard screen.
    func pasteSummary(_ token: ClipboardToken) throws -> String {
        try exactlyOne(app.staticTexts.matching(identifier: ClipboardPasteControl.summaryIdentifier), ClipboardPasteControl.summaryIdentifier).label
    }

    /// Waits until the paste summary is `expected`.
    func waitForPasteSummary(_ token: ClipboardToken, _ expected: String, timeout: TimeInterval = SampleApp.elementTimeout) throws {
        let deadline = Date().addingTimeInterval(timeout)
        var last = try pasteSummary(token)
        while last != expected {
            guard Date() < deadline else {
                throw SampleUITestError("the paste summary did not become \(expected) in \(timeout)s: \(last)")
            }
            Thread.sleep(forTimeInterval: 0.2)
            last = try pasteSummary(token)
        }
        try session.checkInterruption()
    }

    /// Waits for the mounted paste control and taps it.
    func tapPasteControl(_ token: ClipboardToken) throws {
        let query = app.buttons.matching(identifier: ClipboardPasteControl.identifier)
        guard query.firstMatch.waitForExistence(timeout: Self.elementTimeout) else {
            throw SampleUITestError("the paste control did not appear")
        }
        let control = try exactlyOne(query, ClipboardPasteControl.identifier)
        try scrollUntilHittable(control, ClipboardPasteControl.identifier)
        control.tap()
        session.recordPressed(ClipboardPasteControl.identifier)
        try session.checkInterruption()
    }

    // MARK: Alerts and action sheet of the sample

    /// The sample's `UIAlertController` alert with the title `title`.
    func alert(_ title: String) -> SampleAlert {
        SampleAlert(title: title, app: app, session: session)
    }

    /// The sample's action sheet (Sheet on iOS 18, Popover on iOS 26).
    func actionSheet() -> SampleActionSheet {
        SampleActionSheet(app: app, session: session)
    }

    /// Whether the screen the sample presents over a dialog is shown (D19).
    var dialogCoverExists: Bool {
        app.otherElements.matching(identifier: DialogCover.identifier).count == 1
    }

    /// Number of alerts of the sample's process (U-8 (1)). Labels are not read.
    var appAlertCount: Int { app.alerts.count }

    /// Number of alerts left in the sample and in springboard after an operation that can raise
    /// system UI (U-8 (1)). Only counts are read: no label, no interaction.
    var remainingAlertCount: Int {
        app.alerts.count + XCUIApplication(bundleIdentifier: SystemLabels.springboardBundleIdentifier).alerts.count
    }

    // MARK: Inventory

    /// Collects the buttons and identified elements of `screen` from one snapshot, without
    /// scrolling (design 3.1).
    func inventorySnapshot(_ screen: SampleScreen) throws -> InventorySnapshot {
        let root = try app.snapshot()
        var buttons: [InventoryElement] = []
        var nonButtons: [InventoryElement] = []
        var barButtons: [NavigationBarButton] = []
        var listed = 0
        let excluded = Set(SampleInventory.excludedButtons(screen))

        func visit(_ node: XCUIElementSnapshot, inNavigationBar: Bool) {
            let inBar = inNavigationBar || node.elementType == .navigationBar
            if node.elementType == .button {
                if inBar {
                    barButtons.append(NavigationBarButton(identifier: node.identifier, label: node.label))
                } else if excluded.contains(node.identifier) {
                    listed += 1
                } else {
                    buttons.append(InventoryElement(identifier: node.identifier, frame: node.frame))
                }
            } else if node.identifier.hasPrefix(screen.identifierPrefix) {
                nonButtons.append(InventoryElement(identifier: node.identifier, frame: node.frame))
            }
            for child in node.children {
                visit(child, inNavigationBar: inBar)
            }
        }
        visit(root, inNavigationBar: false)
        try session.checkInterruption()
        return InventorySnapshot(
            buttons: buttons,
            identifiedNonButtons: nonButtons,
            navigationBarButtons: barButtons,
            excludedListedButtons: listed
        )
    }

    // MARK: Waiting

    /// Fixed wait used only to confirm that something does not happen (U-14).
    func observeQuietly(for seconds: TimeInterval) {
        Thread.sleep(forTimeInterval: seconds)
    }

    // MARK: Scrolling (no inertia, as `ClipboardUITests.scrollStep`)

    private static let sweepAttempts = 30
    /// Steps in a row without movement before a direction is given up. A single drag that starts
    /// on a button sometimes does not move the content (Notification screen, iOS 26.2).
    private static let stalledStepsLimit = 2

    private func scrollUntilHittable(_ element: XCUIElement, _ name: String) throws {
        if element.isHittable { return }
        // Toward the element first: down when it lies below the scroll view's middle.
        let scrollView = try exactlyOne(app.scrollViews, "scroll view of the screen")
        let downFirst = element.frame.midY >= scrollView.frame.midY
        for direction in [downFirst, !downFirst] {
            var previousY = element.frame.origin.y
            var stalled = 0
            for _ in 0..<Self.sweepAttempts {
                try scrollStep(down: direction)
                try session.checkInterruption()
                if element.isHittable { return }
                let currentY = element.frame.origin.y
                if abs(currentY - previousY) < 1 {
                    stalled += 1
                    if stalled >= Self.stalledStepsLimit { break }
                } else {
                    stalled = 0
                }
                previousY = currentY
            }
        }
        throw SampleUITestError("\(name) did not become hittable")
    }

    /// Drags the screen's only scroll view by about two thirds of its height (a pressed drag, no
    /// inertia; every button is still hittable in at least one position).
    private func scrollStep(down: Bool) throws {
        let scrollView = try exactlyOne(app.scrollViews, "scroll view of the screen")
        let offsets: (start: CGFloat, end: CGFloat) = down ? (0.85, 0.20) : (0.20, 0.85)
        let start = scrollView.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: offsets.start))
        let end = scrollView.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: offsets.end))
        start.press(forDuration: 0.1, thenDragTo: end)
    }

    // MARK: Queries

    private func waitForExistence(_ query: XCUIElementQuery, _ name: String, timeout: TimeInterval = SampleApp.elementTimeout) throws {
        guard query.firstMatch.waitForExistence(timeout: timeout) else {
            throw SampleUITestError("\(name) did not appear in \(timeout)s")
        }
        _ = try exactlyOne(query, name)
    }
}

/// Returns the only element of `query`; with 0 or 2+ matches it throws without touching anything
/// (U-2).
func exactlyOne(_ query: XCUIElementQuery, _ name: String) throws -> XCUIElement {
    let count = query.count
    guard count == 1 else {
        throw SampleUITestError("expected exactly one \(name), found \(count)")
    }
    return query.element
}

// MARK: - Alert of the sample

struct SampleAlert {
    let title: String
    fileprivate let app: XCUIApplication
    fileprivate let session: UITestSession

    private var query: XCUIElementQuery { app.alerts.matching(identifier: title) }

    func waitShown(timeout: TimeInterval = SampleApp.dialogTimeout) throws {
        guard query.firstMatch.waitForExistence(timeout: timeout) else {
            throw SampleUITestError("alert \(title) did not appear")
        }
        _ = try exactlyOne(query, "alert \(title)")
        try session.checkInterruption()
    }

    func waitGone(timeout: TimeInterval = SampleApp.dialogTimeout) throws {
        guard query.firstMatch.waitForNonExistence(timeout: timeout) else {
            throw SampleUITestError("alert \(title) did not close")
        }
    }

    var exists: Bool { query.count > 0 }

    func staticTextLabels() throws -> [String] {
        try exactlyOne(query, "alert \(title)").staticTexts.allElementsBoundByIndex.map(\.label)
    }

    func buttonLabels() throws -> [String] {
        try exactlyOne(query, "alert \(title)").buttons.allElementsBoundByIndex.map(\.label)
    }

    func isButtonEnabled(_ label: String) throws -> Bool {
        try button(label).isEnabled
    }

    func tapButton(_ label: String) throws {
        try button(label).tap()
        try session.checkInterruption()
    }

    private func button(_ label: String) throws -> XCUIElement {
        let alert = try exactlyOne(query, "alert \(title)")
        return try exactlyOne(alert.buttons.matching(identifier: label), "button \(label) of alert \(title)")
    }

    // Text fields

    var textFieldCount: Int { (try? exactlyOne(query, "alert").textFields.count) ?? 0 }
    var secureTextFieldCount: Int { (try? exactlyOne(query, "alert").secureTextFields.count) ?? 0 }

    func textFieldPlaceholder(at index: Int) throws -> String? {
        try textField(at: index).placeholderValue
    }

    func secureTextFieldPlaceholder(at index: Int) throws -> String? {
        try secureTextField(at: index).placeholderValue
    }

    func typeText(_ text: String, intoTextFieldAt index: Int) throws {
        let field = try textField(at: index)
        field.tap()
        field.typeText(text)
        try session.checkInterruption()
    }

    func typeText(_ text: String, intoSecureTextFieldAt index: Int) throws {
        let field = try secureTextField(at: index)
        field.tap()
        field.typeText(text)
        try session.checkInterruption()
    }

    /// Deletes `count` characters from the text field (Delete key).
    func deleteCharacters(_ count: Int, fromTextFieldAt index: Int) throws {
        let field = try textField(at: index)
        field.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: count))
        try session.checkInterruption()
    }

    private func textField(at index: Int) throws -> XCUIElement {
        let fields = try exactlyOne(query, "alert \(title)").textFields
        guard index < fields.count else {
            throw SampleUITestError("alert \(title) has no text field \(index)")
        }
        return fields.element(boundBy: index)
    }

    private func secureTextField(at index: Int) throws -> XCUIElement {
        let fields = try exactlyOne(query, "alert \(title)").secureTextFields
        guard index < fields.count else {
            throw SampleUITestError("alert \(title) has no secure text field \(index)")
        }
        return fields.element(boundBy: index)
    }
}

// MARK: - Action sheet of the sample

struct SampleActionSheet {
    fileprivate let app: XCUIApplication
    fileprivate let session: UITestSession

    /// Waits until the option `label` is shown.
    func waitShown(option label: String, timeout: TimeInterval = SampleApp.dialogTimeout) throws {
        let query = app.buttons.matching(identifier: label)
        guard query.firstMatch.waitForExistence(timeout: timeout) else {
            throw SampleUITestError("action sheet option \(label) did not appear")
        }
        _ = try exactlyOne(query, "action sheet option \(label)")
        try session.checkInterruption()
    }

    func waitGone(option label: String, timeout: TimeInterval = SampleApp.dialogTimeout) throws {
        guard app.buttons.matching(identifier: label).firstMatch.waitForNonExistence(timeout: timeout) else {
            throw SampleUITestError("action sheet did not close")
        }
    }

    /// Number of buttons whose label is `label`.
    func optionCount(_ label: String) -> Int {
        app.buttons.matching(identifier: label).count
    }

    /// Number of static texts whose label is `text`.
    func textCount(_ text: String) -> Int {
        app.staticTexts.matching(identifier: text).count
    }

    func tapOption(_ label: String) throws {
        try exactlyOne(app.buttons.matching(identifier: label), "action sheet option \(label)").tap()
        try session.checkInterruption()
    }

    /// Whether a hittable `Cancel` button exists (iOS 18: yes, iOS 26.2 popover: no).
    var hasHittableCancel: Bool {
        let query = app.buttons.matching(identifier: "Cancel")
        return query.count == 1 && query.element.isHittable
    }

    func tapCancel() throws {
        try exactlyOne(app.buttons.matching(identifier: "Cancel"), "action sheet Cancel").tap()
        try session.checkInterruption()
    }

    /// iOS 26: the popover has no Cancel; tapping outside cancels it.
    func tapPopoverDismissRegion() throws {
        try exactlyOne(app.otherElements.matching(identifier: SystemLabels.popoverDismissRegion), SystemLabels.popoverDismissRegion).tap()
        try session.checkInterruption()
    }
}
