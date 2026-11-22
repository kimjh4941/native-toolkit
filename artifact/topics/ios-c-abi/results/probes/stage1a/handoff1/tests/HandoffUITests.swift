// Hand-off 1 probe: taps the alert and share sheet that CApiTestHost opens through the C ABI.
import UIKit
import XCTest

final class HandoffUITests: XCTestCase {
    private func launch(_ scenario: String) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-handoff-scenario", scenario]
        app.launch()
        return app
    }

    private func results(_ app: XCUIApplication, contains text: String) -> Bool {
        let label = app.staticTexts["results"]
        let end = Date().addingTimeInterval(5)
        while Date() < end {
            if label.exists, label.label.contains(text) { return true }
            usleep(100_000)
        }
        print("HANDOFF1-UI: results = \(label.exists ? label.label : "-")")
        return false
    }

    /// The button's completion comes once on main, then release; the alert was asked for inside didFinishLaunching.
    func testAlertButtonCompletesOnceOnMain() {
        let app = launch("dialog")
        let alert = app.alerts["Handoff"]
        XCTAssertTrue(alert.waitForExistence(timeout: 5))
        alert.buttons["No"].tap()
        XCTAssertTrue(results(app, contains: "release tag=1 main=1"))
        let lines = app.staticTexts["results"].label.components(separatedBy: " | ")
        print("HANDOFF1-UI: \(lines)")
        XCTAssertEqual(lines.filter { $0.hasPrefix("dialog tag=1") }, ["dialog tag=1 id=1 error=0 button=1 main=1"])
        XCTAssertEqual(lines.filter { $0.hasPrefix("release tag=1") }.count, 1)
        XCTAssertLessThan(lines.firstIndex { $0.hasPrefix("dialog") } ?? Int.max, lines.firstIndex { $0.hasPrefix("release") } ?? -1)
    }

    /// P1-12: both alerts of one main turn are shown; the second is on top.
    func testTwoAlertsInOneTurnAreBothShown() {
        let app = launch("two")
        let second = app.alerts["Handoff 2"]
        XCTAssertTrue(second.waitForExistence(timeout: 5))
        second.buttons["Yes 2"].tap()
        let first = app.alerts["Handoff 1"]
        XCTAssertTrue(first.waitForExistence(timeout: 5))
        first.buttons["Yes 1"].tap()
        XCTAssertTrue(results(app, contains: "release tag=1 main=1"))
        let text = app.staticTexts["results"].label
        print("HANDOFF1-UI: \(text.components(separatedBy: "\n"))")
        XCTAssertTrue(text.contains("dialog tag=2 id=2 error=0 button=0 main=1"))
        XCTAssertTrue(text.contains("dialog tag=1 id=1 error=0 button=0 main=1"))
    }

    /// Closing the share sheet without choosing an activity.
    func testShareSheetClosed() {
        let app = launch("share")
        // Wait for the sheet (UI test design: UIActivityContentView or ActivityListView), then close it
        // without choosing an activity: PopoverDismissRegion (iOS 26), Close (iPhone, iOS 18), or a tap
        // outside the popover (iPad, iOS 18).
        let markers = app.descendants(matching: .any).matching(NSPredicate(format: "identifier IN %@", ["UIActivityContentView", "ActivityListView"]))
        XCTAssertTrue(markers.firstMatch.waitForExistence(timeout: 8))
        let region = app.otherElements["PopoverDismissRegion"]
        let close = app.buttons["Close"]
        if region.waitForExistence(timeout: 2) {
            print("HANDOFF1-UI: share closed through PopoverDismissRegion")
            region.tap()
        } else if close.exists {
            print("HANDOFF1-UI: share closed through Close")
            close.tap()
        } else {
            print("HANDOFF1-UI: share closed by a tap outside the popover")
            app.coordinate(withNormalizedOffset: CGVector(dx: 0.03, dy: 0.03)).tap()
        }
        XCTAssertTrue(results(app, contains: "release tag=3 main=1"))
        print("HANDOFF1-UI: \(app.staticTexts["results"].label.components(separatedBy: " | "))")
        XCTAssertTrue(app.staticTexts["results"].label.contains("share tag=3 error=0 completed=0 main=1"))
    }
}
