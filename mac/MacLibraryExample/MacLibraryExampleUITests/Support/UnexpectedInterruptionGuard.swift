//
//  UnexpectedInterruptionGuard.swift
//  MacLibraryExampleUITests
//
//  The interruption monitor of every new UI test (UI test design U-8). Trusted Support file.
//
//  XCTest calls a monitor when an interrupting element blocks the next action of a test. This
//  monitor presses nothing and reads no label: it terminates the sample, marks the test and
//  returns `true`. Expected system UI (alerts, panels, the picker) is waited for and operated
//  explicitly before the monitor could be reached. The Support wrappers read the mark right after
//  each operation and throw; after the mark the ordinary cleanup is not run.
//

import XCTest
import Foundation

enum UnexpectedInterruptionGuard {

    static func install(on testCase: XCTestCase, session: UITestSession) {
        let app = XCUIApplication()
        _ = testCase.addUIInterruptionMonitor(withDescription: "ntk-unexpected-interruption-guard") { element in
            handle(element, app: app, session: session)
        }
    }

    private static func handle(_ element: XCUIElement, app: XCUIApplication, session: UITestSession) -> Bool {
        session.monitorInvocations += 1
        app.terminate()
        session.interruption = .unknownInterruption
        session.interruptionDetail = "elementType=\(element.elementType.rawValue)"
        return true
    }
}
