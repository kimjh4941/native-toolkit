//
//  CApiUITestCase.swift
//  IosLibraryCApiUITests
//

import XCTest

/// A plain `Error` (not `XCTSkip`), so that the test fails and stops at that point.
struct CApiUITestError: Error, CustomStringConvertible {
    let description: String

    init(_ description: String) {
        self.description = description
    }
}

/// Base of every UI test class of the C ABI.
///
/// These tests run on the simulator only (C ABI design part 2, 12.2): they answer permission alerts
/// and use springboard, and they have none of the guards of the sample's UI tests for the private
/// device (UI test design U-9). Both targets support the simulator only, so a device is not a
/// destination for them, and `scripts/test_ios.sh --capi-ui` refuses the device. A command-line
/// override can still force a device build; `agent-rules/device-testing.md` covers that. This base is
/// the next guard: `setUpWithError` is `final`, and `launch` checks again.
class CApiUITestCase: XCTestCase {

    /// Whether the interruption monitor saw something. Without a monitor XCTest's default handler may
    /// press Allow and change the state the next test starts from (UI test design U-8).
    fileprivate(set) var interrupted = false

    private let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")

    /// Throws anywhere but on the simulator, before any operation.
    static func requireSimulator() throws {
        #if !targetEnvironment(simulator)
        throw CApiUITestError("the UI tests of the C ABI run on the simulator only; nothing was done")
        #endif
    }

    final override func setUpWithError() throws {
        continueAfterFailure = false
        try Self.requireSimulator()
        XCUIDevice.shared.orientation = .portrait
        interrupted = false
        addUIInterruptionMonitor(withDescription: "ntk-capi-press-nothing") { [weak self] _ in
            self?.interrupted = true
            return true
        }
    }

    /// An alert a test left open survives the deletion of its app and stops the tests after it until
    /// the simulator restarts, which would hide it (stage 2 working notes, 5.4). So a test that leaves
    /// one fails, even if it passed. The label is not in the message, as on the device (U-8).
    final override func tearDownWithError() throws {
        try Self.requireSimulator()
        if springboard.alerts.count > 0 {
            throw CApiUITestError("the test left a system alert open; nothing was pressed")
        }
    }

    /// Launches the app for this test (a new process for every test), with only `section` drawn.
    func launchApp(section: CApiSection) throws -> CApiUITestApp {
        try Self.requireSimulator()
        let app = CApiUITestApp(test: self, section: section)
        try app.launch()
        return app
    }

    /// Throws when something interrupted the test. Nothing was pressed.
    func checkInterruption() throws {
        if interrupted {
            throw CApiUITestError("an unexpected alert interrupted the test; nothing was pressed")
        }
    }
}
