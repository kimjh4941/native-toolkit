// Hand-off 2 probe: real notifications on the simulator. The host app logs what the C ABI hands it;
// this file only acts (allow, home, banner taps, terminate) and checks the "results" label.
import UIKit
import XCTest

final class HandoffNotificationUITests: XCTestCase {
    private let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")

    override func setUp() { continueAfterFailure = true }

    private func launch(_ arguments: [String]) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-handoff2"] + arguments
        app.launch()
        return app
    }

    private func results(_ app: XCUIApplication) -> String {
        let label = app.staticTexts["results"]
        return label.exists ? label.label : ""
    }

    @discardableResult
    private func waitResults(_ app: XCUIApplication, contains text: String, timeout: TimeInterval = 10) -> Bool {
        let end = Date().addingTimeInterval(timeout)
        while Date() < end {
            if results(app).contains(text) { return true }
            usleep(200_000)
        }
        print("HANDOFF2-UI: missing '\(text)' in: \(results(app))")
        return false
    }

    private func banner(_ title: String) -> XCUIElement {
        springboard.descendants(matching: .any)
            .matching(NSPredicate(format: "identifier == 'NotificationShortLookView' AND label CONTAINS %@", title)).firstMatch
    }

    private func report(_ name: String, _ app: XCUIApplication) {
        print("HANDOFF2-UI: \(name): \(results(app).components(separatedBy: " | "))")
    }

    /// Runs first: allow notifications for the host app (the simulator asks once per install).
    func test01Allow() {
        let app = launch(["-auth", "-install", "will", "-listen-after", "-1"])
        let alert = springboard.alerts.firstMatch
        if alert.waitForExistence(timeout: 6) {
            for label in ["Allow", "許可"] where alert.buttons[label].exists { alert.buttons[label].tap(); break }
        }
        XCTAssertTrue(waitResults(app, contains: "done tag=9 error=0 granted=1"))
        report("allow", app)
        app.terminate()
    }

    /// A library notification tapped from the home screen before the C listener exists: the event is
    /// kept and handed to the listener when it registers (5.12.7). Not a launch response (P1-22).
    func test02TapIsKeptUntilTheListenerRegisters() {
        let app = launch(["-listen-after", "12", "-schedule", "tap1", "3", "Handoff2 Tap"])
        XCTAssertTrue(waitResults(app, contains: "done tag=1 error=0"))
        XCUIDevice.shared.press(.home)
        XCTAssertTrue(banner("Handoff2 Tap").waitForExistence(timeout: 12))
        banner("Handoff2 Tap").tap()
        XCTAssertTrue(waitResults(app, contains: "id=tap1", timeout: 20))
        let text = results(app)
        report("buffered tap", app)
        XCTAssertTrue(text.contains("event kind=0 id=tap1 action=com.apple.UNNotificationDefaultActionIdentifier text=nil launch=0"))
        let added = text.range(of: "listener added error=0")?.lowerBound, event = text.range(of: "id=tap1")?.lowerBound
        XCTAssertNotNil(added)
        if let added, let event { XCTAssertLessThan(added, event, "delivered after the registration, not before") }
        app.terminate()
    }

    /// A host notification goes to the host's delegate, not to the library (5.12.3).
    func test03HostNotificationGoesToTheHost() {
        let app = launch(["-host", "forward", "-schedule-host", "host1", "3", "Handoff2 Host"])
        XCUIDevice.shared.press(.home)
        XCTAssertTrue(banner("Handoff2 Host").waitForExistence(timeout: 12))
        banner("Handoff2 Host").tap()
        XCTAssertTrue(waitResults(app, contains: "host didReceive id=host1", timeout: 15))
        sleep(1)
        report("host notification", app)
        XCTAssertFalse(results(app).contains("event kind=0 id=host1"))
        app.terminate()
    }

    /// With no host delegate, an unmarked notification is unclaimed and the library takes it (1a-6).
    func test04UnclaimedNotificationGoesToTheLibrary() {
        let app = launch(["-schedule-host", "free1", "3", "Handoff2 Free"])
        XCUIDevice.shared.press(.home)
        XCTAssertTrue(banner("Handoff2 Free").waitForExistence(timeout: 12))
        banner("Handoff2 Free").tap()
        XCTAssertTrue(waitResults(app, contains: "event kind=0 id=free1", timeout: 15))
        report("unclaimed", app)
        app.terminate()
    }

    /// P1-21: the host forwards to the library synchronously after the library was installed again.
    /// In the foreground (willPresent) the cycle ends once and the banner is shown.
    func test05CycleInWillPresent() {
        let app = launch(["-host", "cyclic", "-schedule-host", "cyc1", "3", "Handoff2 Cycle"])
        XCTAssertTrue(banner("Handoff2 Cycle").waitForExistence(timeout: 12), "the banner is shown with the library's options")
        XCTAssertTrue(waitResults(app, contains: "host willPresent id=cyc1"))
        sleep(1)
        report("cycle willPresent", app)
        XCTAssertEqual(app.state, .runningForeground)
        app.terminate()
    }

    /// The same cycle for a tap (didReceive): the host sees it once, then the library takes it as unclaimed.
    func test05bCycleInDidReceive() {
        let app = launch(["-host", "cyclic", "-schedule-host", "cyc2", "3", "Handoff2 CycTap"])
        XCUIDevice.shared.press(.home)
        XCTAssertTrue(banner("Handoff2 CycTap").waitForExistence(timeout: 12))
        banner("Handoff2 CycTap").tap()
        XCTAssertTrue(waitResults(app, contains: "event kind=0 id=cyc2", timeout: 15))
        report("cycle didReceive", app)
        let text = results(app)
        XCTAssertEqual(text.components(separatedBy: "host didReceive id=cyc2").count - 1, 1)
        XCTAssertEqual(text.components(separatedBy: "event kind=0 id=cyc2").count - 1, 1)
        XCTAssertEqual(app.state, .runningForeground)
        app.terminate()
    }

    /// U-3 shape: the app is not running, the user taps the notification; the library installed in
    /// willFinishLaunching gets the tap, keeps it until C registers two seconds later, and reports it
    /// as the launch response (P1-22).
    func test06ColdStartTapIsTheLaunchResponse() {
        let app = launch(["-arm-cold", "-listen-after", "2", "-schedule", "cold1", "4", "Handoff2 Cold"])
        XCTAssertTrue(waitResults(app, contains: "done tag=1 error=0"))
        app.terminate()
        XCTAssertTrue(banner("Handoff2 Cold").waitForExistence(timeout: 12))
        banner("Handoff2 Cold").tap()
        XCTAssertTrue(app.wait(for: .runningForeground, timeout: 10))
        XCTAssertTrue(waitResults(app, contains: "launch-response error=0 id=cold1", timeout: 15))
        XCTAssertTrue(waitResults(app, contains: "event kind=0 id=cold1"))
        report("cold start", app)
        XCTAssertTrue(results(app).contains("event kind=0 id=cold1 action=com.apple.UNNotificationDefaultActionIdentifier text=nil launch=1"))
        app.terminate()
    }
}
