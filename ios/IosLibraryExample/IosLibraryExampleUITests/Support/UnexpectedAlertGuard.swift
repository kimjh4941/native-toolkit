//
//  UnexpectedAlertGuard.swift
//  IosLibraryExampleUITests
//
//  The interruption monitor of every UI test (UI test design U-8). Trusted Support file.
//
//  XCTest calls a monitor when an interrupting element blocks the next action of the test, not
//  when the element appears. If no monitor handles it, XCTest's default handler may press Allow.
//  Inside the monitor only safe operations, setting the mark and returning `true` happen: never
//  `XCTFail`. The Support wrappers read the mark right after each operation and throw.
//

import XCTest
import Foundation

enum UnexpectedAlertGuard {

    enum Mode {
        /// Press nothing for any interruption (NP1, NP2, CB1, CB2: their expected alert is waited
        /// for and pressed explicitly through springboard).
        case pressNothing
        /// U-8 (a) / (b).
        case standard
    }

    /// Tests whose monitor presses nothing: the permission classes and CB1 / CB2.
    private static let pressNothingClasses: Set<String> = ["NotificationPermissionUITests", "ClipboardPasteDenyUITests"]
    private static let pressNothingMethodPrefixes: [(className: String, methodPrefix: String)] = [
        ("ClipboardPasteUITests", "testCB1_")
    ]

    static func mode(forTestKey key: String) -> Mode {
        let parts = key.split(separator: "/")
        guard parts.count == 2 else { return .pressNothing }
        let className = String(parts[0])
        let method = String(parts[1])
        if pressNothingClasses.contains(className) { return .pressNothing }
        if pressNothingMethodPrefixes.contains(where: { $0.className == className && method.hasPrefix($0.methodPrefix) }) {
            return .pressNothing
        }
        return .standard
    }

    static func install(on testCase: XCTestCase, session: UITestSession, mode: Mode, declared: Set<DeviceCategory>) {
        let app = XCUIApplication(bundleIdentifier: SystemLabels.sampleBundleIdentifier)
        _ = testCase.addUIInterruptionMonitor(withDescription: "ntk-unexpected-alert-guard") { element in
            handle(element, app: app, session: session, mode: mode, declared: declared)
        }
    }

    private static func handle(
        _ element: XCUIElement,
        app: XCUIApplication,
        session: UITestSession,
        mode: Mode,
        declared: Set<DeviceCategory>
    ) -> Bool {
        session.monitorInvocations += 1
        let type = element.elementType
        let identifier = element.identifier
        let label = element.label

        if mode == .pressNothing {
            return stop(app, session, describe(session, type, identifier, label, "press-nothing monitor"))
        }

        // A notification banner over the app reaches the monitor (measured in stage 0c on the
        // iOS 26.2 simulator). Tests that handle banners (`systemui`) leave it to XCTest's default
        // handling; the label is not read.
        if identifier == SystemLabels.notificationShortLook && declared.contains(.systemui) {
            return false
        }

        guard type == .alert else {
            return stop(app, session, describe(session, type, identifier, label, "not an alert"))
        }
        guard label.contains(SystemLabels.quotedSampleDisplayName) else {
            return stop(app, session, describe(session, type, identifier, label, "alert without the sample's name"))
        }
        var negatives: [String] = []
        if declared.contains(.systemui) { negatives += SystemLabels.systemNegativeButtons }
        if declared.contains(.clipboard) { negatives += SystemLabels.pasteNegativeButtons }
        guard !negatives.isEmpty else {
            return stop(app, session, describe(session, type, identifier, label, "the test declares neither systemui nor clipboard"))
        }
        let candidates = element.buttons.matching(NSPredicate(format: "label IN %@", negatives))
        guard candidates.count == 1 else {
            return stop(app, session, describe(session, type, identifier, label, "\(candidates.count) known negative buttons"))
        }
        candidates.element.tap()
        session.interruption = .knownAlertDenied
        session.interruptionDetail = describe(session, type, identifier, label, "pressed the known negative button")
        return true
    }

    /// Terminates the sample without pressing anything and marks the test.
    private static func stop(_ app: XCUIApplication, _ session: UITestSession, _ detail: String) -> Bool {
        app.terminate()
        session.interruption = .unknownInterruption
        session.interruptionDetail = detail
        return true
    }

    /// Labels of system UI are written only on the simulator (U-8 (3)).
    private static func describe(
        _ session: UITestSession,
        _ type: XCUIElement.ElementType,
        _ identifier: String,
        _ label: String,
        _ reason: String
    ) -> String {
        if session.isDevice {
            return "\(reason) (elementType=\(type.rawValue))"
        }
        return "\(reason) (elementType=\(type.rawValue), identifier=\(identifier), label=\(label))"
    }
}
