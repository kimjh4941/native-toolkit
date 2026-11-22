// Stage 1a throwaway: drives DelegateProbe from a UI test runner (copied into a scratch copy of
// IosLibraryExampleUITests by run.sh). Scenarios come from TEST_RUNNER_PROBE_SCENARIOS (space
// separated) and the app from TEST_RUNNER_PROBE_BUNDLE. The app logs what it receives; this file
// only acts (banner taps, home, terminate, Settings) and prints what it saw as [PROBE-UI] lines.
import XCTest

final class Stage1aDelegateProbeTests: XCTestCase {
    let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")
    let settings = XCUIApplication(bundleIdentifier: "com.apple.Preferences")

    override func setUp() { continueAfterFailure = true }

    private func env(_ key: String) -> String { ProcessInfo.processInfo.environment[key] ?? "" }
    private func say(_ s: String) { print("[PROBE-UI] \(s)") }

    private func waitState(_ app: XCUIApplication, _ value: String, _ timeout: TimeInterval) -> Bool {
        let label = app.staticTexts["probe.state"]
        let p = NSPredicate(format: "label == %@", value)
        return XCTWaiter().wait(for: [XCTNSPredicateExpectation(predicate: p, object: label)], timeout: timeout) == .completed
    }

    private func banner(_ text: String) -> XCUIElement {
        springboard.descendants(matching: .any)
            .matching(NSPredicate(format: "identifier == 'NotificationShortLookView' AND label CONTAINS %@", text)).firstMatch
    }

    /// Seconds until the banner appears, or nil.
    private func waitBanner(_ text: String, _ timeout: TimeInterval) -> Double? {
        let start = Date()
        return banner(text).waitForExistence(timeout: timeout) ? Date().timeIntervalSince(start) : nil
    }

    func testScenarios() {
        let bundle = env("PROBE_BUNDLE")
        for s in env("PROBE_SCENARIOS").split(separator: " ").map(String.init) {
            runOne(s, bundle)
        }
    }

    private func runOne(_ s: String, _ bundle: String) {
        say("begin \(s)")
        let app = XCUIApplication(bundleIdentifier: bundle)
        if s.contains("os.") { settings.terminate() }
        app.launchEnvironment = ["PROBE_SCENARIO": s]
        app.launch()
        let parts = s.split(separator: ".").map(String.init)
        let method = parts[0] == "raw" ? parts[1] : parts[0]
        switch method {
        case "auth":
            let alert = springboard.alerts.firstMatch
            if alert.waitForExistence(timeout: 8) {
                for l in ["Allow", "許可"] where alert.buttons[l].exists { alert.buttons[l].tap(); break }
                say("auth tapped")
            } else {
                say("auth noAlert")
            }
            _ = waitState(app, "done", 8)
        case "wp":
            _ = waitState(app, "armed", 8)
            let a = waitBanner("A \(s)", 9)
            say("banner \(s) A=\(a.map { String(format: "%.1f", $0) } ?? "none")")
            let b = waitBanner("B \(s)", 9)
            say("banner \(s) B=\(b.map { String(format: "%.1f", $0) } ?? "none")")
            _ = waitState(app, "done", 8)
        case "dr":
            _ = waitState(app, "armed", 8)
            XCUIDevice.shared.press(.home)
            if let t = waitBanner("T \(s)", s.contains("late") ? 20 : 12) {
                if s.contains("bga") {
                    banner("T \(s)").press(forDuration: 1.5)
                    let button = springboard.buttons["BgAct"]
                    if button.waitForExistence(timeout: 5) {
                        button.tap()
                        say("bgAction \(s) after=\(String(format: "%.1f", t))")
                        for wait in [2.0, 8.0, 25.0, 15.0] {
                            Thread.sleep(forTimeInterval: wait)
                            say("bgState \(s) appState=\(app.state.rawValue)")
                        }
                    } else {
                        say("noBgButton \(s)")
                    }
                } else {
                    banner("T \(s)").tap()
                    say("tapped \(s) after=\(String(format: "%.1f", t))")
                    _ = waitState(app, "done", 25)
                }
            } else {
                say("noBanner \(s)")
            }
        case "cold":
            _ = waitState(app, "armed", 8)
            app.terminate()
            if waitBanner("P \(s)", 12) != nil {
                banner("P \(s)").tap()
                say("coldTapped \(s)")
                _ = waitState(app, "done", 15)
                say("coldState \(s) running=\(app.state.rawValue)")
            } else {
                say("noBanner \(s)")
            }
        case "os":
            _ = waitState(app, "armed", 8)
            let link = settings.descendants(matching: .any)
                .matching(NSPredicate(format: "label CONTAINS 'Notification Settings' OR label CONTAINS '通知設定'")).firstMatch
            if !link.waitForExistence(timeout: 4) {
                // The deep link stops at the root on the simulator: go Apps -> the app -> Notifications.
                let apps = settings.buttons["com.apple.settings.apps"]
                for _ in 0..<4 where !(apps.exists && apps.isHittable) { settings.swipeUp() }
                if apps.exists { apps.tap() }
                say("settingsNav apps=\(apps.exists) bar=\(settings.navigationBars.firstMatch.identifier)")
                let appName = bundle.hasSuffix(".scene") ? "DelegateProbeScene" : "DelegateProbe"
                let row = settings.descendants(matching: .any).matching(NSPredicate(format: "label == %@", appName)).firstMatch
                if !row.waitForExistence(timeout: 5) {
                    let field = settings.searchFields.firstMatch
                    if field.exists { field.tap(); field.typeText(appName) }
                }
                if row.waitForExistence(timeout: 5) {
                    for _ in 0..<6 where !row.isHittable { settings.swipeUp() }
                    row.tap()
                }
                say("settingsNav row=\(row.exists) bar=\(settings.navigationBars.firstMatch.identifier)")
                let notif = settings.descendants(matching: .any).matching(NSPredicate(format: "label BEGINSWITH '通知' OR label BEGINSWITH 'Notifications'")).firstMatch
                if notif.waitForExistence(timeout: 5) { notif.tap() }
            }
            if link.waitForExistence(timeout: 6) {
                say("settingsLink \(link.label)")
                link.tap()
                _ = waitState(app, "done", 30)
            } else {
                let tree = settings.debugDescription.split(separator: "\n").filter { $0.contains("label:") }.prefix(60)
                say("noSettingsLink \(s) tree=\(tree.joined(separator: " | "))")
            }
        default:
            _ = waitState(app, "done", 20)
        }
        say("end \(s) appState=\(app.state.rawValue)")
        app.terminate()
    }
}
