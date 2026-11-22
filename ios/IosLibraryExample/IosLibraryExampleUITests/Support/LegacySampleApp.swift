//
//  LegacySampleApp.swift
//  IosLibraryExampleUITests
//
//  The 1.13.0 sample (IosLibrary 1.3.0) and the steps of the upgrade test (the upgrade test design,
//  `artifact/topics/ios-c-abi/designs/2026-11-21-ios-c-abi-upgrade-test-design.md`, U-5, U-9, U-10).
//  `scripts/test_ios_upgrade.sh` runs each step on its own: the 1.x half through a copy of the
//  xctestrun whose target app is the 1.x sample, the 2.0.0 half through the normal one, which
//  installs 2.0.0 over it. The 1.x sample has no accessibility identifiers (stage 0b came after
//  it), so its buttons are found by their titles; only its Notification screen is used.
//  Part of the trusted part (design 6.1): it uses XCUIApplication.
//

import XCTest
import Foundation

/// The six halves of the upgrade test. A test runs only when `NTK_UPGRADE_STEP` names its step
/// (passed by the script as `TEST_RUNNER_NTK_UPGRADE_STEP`); the normal runs never select the class
/// (`SCRIPT_ONLY_CLASSES` of the runner) and skip it if it is named by hand.
enum UpgradeStep: String {
    case ua1 = "UA1", ua2 = "UA2", ub1 = "UB1", ub2 = "UB2", uc1 = "UC1", uc2 = "UC2"

    static let stepVariable = "NTK_UPGRADE_STEP"
    static let signalVariable = "NTK_UPGRADE_SIGNAL"

    /// Skips the test unless the script asked for this step, and fails on a device: the upgrade
    /// test runs on the simulator only (U-1; the script and the runner keep it there too).
    func require() throws {
        guard !SampleUITestCase.isDevice else {
            throw SampleUITestError("the upgrade test runs on the simulator only")
        }
        let asked = ProcessInfo.processInfo.environment[Self.stepVariable] ?? ""
        guard asked == rawValue else {
            throw XCTSkip("NTK-UPGRADE: run by scripts/test_ios_upgrade.sh only (step \(rawValue), asked '\(asked)')")
        }
    }

    /// Writes the step's name to the signal file the script passed (U-5): the 2.0.0 half is ready
    /// for the location change that fires the 1.x notification.
    func signalReady() throws {
        guard let path = ProcessInfo.processInfo.environment[Self.signalVariable], !path.isEmpty else {
            throw SampleUITestError("\(Self.signalVariable) is not set")
        }
        try rawValue.write(toFile: path, atomically: true, encoding: .utf8)
    }
}

/// The buttons of the 1.13.0 sample's Notification screen the upgrade test presses, by title.
enum LegacyNotificationButton: String, CaseIterable {
    case requestPermission = "RequestPermission"
    case showImmediate = "ShowImmediate"
    case showTimeInterval = "ShowTimeInterval(5s)"
    case scheduleLocation = "ScheduleLocation(Tokyo Station, onEntry)"
    case getScheduled = "GetScheduled"
    case getDelivered = "GetDelivered"
    case registerCategory = "RegisterCategory"

    /// Buttons that bring up system UI or post a notification need `systemui` (as `SampleApp`).
    fileprivate var needsSystemUI: Bool {
        switch self {
        case .requestPermission, .showImmediate, .showTimeInterval, .scheduleLocation: return true
        case .getScheduled, .getDelivered, .registerCategory: return false
        }
    }
}

struct LegacySampleApp {

    private let app = XCUIApplication(bundleIdentifier: SystemLabels.sampleBundleIdentifier)
    private let session: UITestSession

    /// The 1.13.0 sample's menu card of the Notification screen.
    static let notificationMenuTitle = "Notification Example"
    static let launchTimeout: TimeInterval = 10
    static let resultTimeout: TimeInterval = 10

    init(_ token: SystemUIToken) {
        session = token.session
    }

    // MARK: Lifecycle

    func launch() throws {
        app.launch()
        guard app.wait(for: .runningForeground, timeout: Self.launchTimeout) else {
            throw SampleUITestError("the 1.x sample did not come to the foreground")
        }
        try session.checkInterruption()
    }

    func activate() throws {
        app.activate()
        guard app.wait(for: .runningForeground, timeout: Self.launchTimeout) else {
            throw SampleUITestError("the 1.x sample did not come to the foreground")
        }
        Thread.sleep(forTimeInterval: 1)  // the zoom-in from the home screen (as SampleApp.activate)
        try session.checkInterruption()
    }

    /// Opens the Notification screen from the menu and waits for its first button.
    func openNotification() throws {
        let card = app.staticTexts.matching(NSPredicate(format: "label == %@", Self.notificationMenuTitle))
        guard card.firstMatch.waitForExistence(timeout: Self.launchTimeout) else {
            throw SampleUITestError("the 1.x menu card \(Self.notificationMenuTitle) did not appear")
        }
        try exactlyOne(card, Self.notificationMenuTitle).tap()
        guard button(.requestPermission).firstMatch.waitForExistence(timeout: Self.launchTimeout) else {
            throw SampleUITestError("the 1.x Notification screen did not open")
        }
        try session.checkInterruption()
    }

    /// The number of elements with an identifier of the 2.0.0 sample (`menu.` or `notification.`).
    /// Zero shows that the app in the foreground is the 1.x sample (U-4).
    var newSampleIdentifierCount: Int {
        app.descendants(matching: .any)
            .matching(NSPredicate(format: "identifier BEGINSWITH %@ OR identifier BEGINSWITH %@", "menu.", "notification."))
            .count
    }

    // MARK: Buttons

    func tap(_ button: LegacyNotificationButton) throws {
        guard !button.needsSystemUI else {
            throw SampleUITestError("\(button.rawValue) needs a SystemUIToken")
        }
        try tapButton(button)
    }

    func tap(_ button: LegacyNotificationButton, _ token: SystemUIToken) throws {
        guard button.needsSystemUI else {
            throw SampleUITestError("\(button.rawValue) is not a systemui button")
        }
        try tapButton(button)
    }

    private func button(_ button: LegacyNotificationButton) -> XCUIElementQuery {
        app.buttons.matching(NSPredicate(format: "label == %@", button.rawValue))
    }

    private func tapButton(_ legacy: LegacyNotificationButton) throws {
        let element = try exactlyOne(button(legacy), legacy.rawValue)
        try scrollUntilHittable(element, legacy.rawValue)
        element.tap()
        // Not recorded with `recordPressed`: the button coverage lists the 2.0.0 sample's identifiers.
        try session.checkInterruption()
    }

    // MARK: Scrolling (the same steps as `SampleApp`: no inertia, both directions)

    private static let sweepAttempts = 30
    /// Steps in a row without movement before a direction is given up (as `SampleApp`).
    private static let stalledStepsLimit = 2

    /// The buttons are in the screen's only scroll view, below the result line (which does not
    /// scroll; a swipe on the whole app can land on it and move nothing).
    private func scrollUntilHittable(_ element: XCUIElement, _ name: String) throws {
        if element.isHittable { return }
        let scrollView = try exactlyOne(app.scrollViews, "the 1.x scroll view")
        let downFirst = element.frame.midY >= scrollView.frame.midY
        for direction in [downFirst, !downFirst] {
            var previousY = element.frame.origin.y
            var stalled = 0
            for _ in 0..<Self.sweepAttempts {
                let offsets: (start: CGFloat, end: CGFloat) = direction ? (0.85, 0.20) : (0.20, 0.85)
                scrollView.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: offsets.start))
                    .press(forDuration: 0.1, thenDragTo: scrollView.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: offsets.end)))
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
        throw SampleUITestError("\(name) did not become hittable: frame \(element.frame)")
    }

    // MARK: Result line

    /// The 1.x result line (`✅ \nResult: …`, `❌ \nResult: …`, or the initial text). It has no
    /// identifier, so it is the only static text with one of those shapes.
    func resultText() throws -> String {
        let shape = NSPredicate(format: "label BEGINSWITH %@ OR label BEGINSWITH %@ OR label == %@",
                                "✅ \nResult: ", "❌ \nResult: ", ResultLine.initial)
        return try exactlyOne(app.staticTexts.matching(shape), "the 1.x result line").label
    }

    /// Reads the result line every 0.5 s until it is `expected` (10 s at most. The 1.x line has no
    /// update count; the design does not press two buttons in a row that write the same text).
    func waitForResult(_ expected: String, timeout: TimeInterval = LegacySampleApp.resultTimeout) throws {
        let deadline = Date().addingTimeInterval(timeout)
        var last = try resultText()
        while last != expected {
            guard Date() < deadline else {
                throw SampleUITestError("the 1.x result line did not become '\(expected)' in \(timeout)s: '\(last)'")
            }
            Thread.sleep(forTimeInterval: 0.5)
            last = try resultText()
        }
        try session.checkInterruption()
    }
}
