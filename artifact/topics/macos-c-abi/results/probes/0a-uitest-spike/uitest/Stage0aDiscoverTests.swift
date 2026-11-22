// Discovery for macos-c-abi 0a: dumps the accessibility trees of system UI after the probe app
// triggers it. Runs only inside the qualified VM. Nothing is chosen in the share picker.
import XCTest

let probeID = "dev.ntkprobe.notif0a"
let sbxID = "dev.ntkprobe.sbx0a"
let ncID = "com.apple.notificationcenterui"

func dump(_ name: String, _ app: XCUIApplication) {
    print("=== DUMP \(name) state=\(app.state.rawValue) ===")
    print(app.debugDescription)
    print("=== END \(name) ===")
}

extension XCTestCase {
    func shot(_ name: String) {
        let a = XCTAttachment(screenshot: XCUIScreen.main.screenshot()); a.name = name; a.lifetime = .keepAlways; add(a)
    }
}

final class Stage0aDiscoverTests: XCTestCase {
    override func setUp() { continueAfterFailure = true }

    @MainActor func testD1_AuthPrompt() {
        let probe = XCUIApplication(bundleIdentifier: probeID)
        probe.launch()
        XCTAssertTrue(probe.buttons["reqAuth"].waitForExistence(timeout: 5))
        probe.buttons["reqAuth"].click()
        sleep(3)
        dump("nc-after-reqAuth", XCUIApplication(bundleIdentifier: ncID))
        dump("UserNotificationCenter", XCUIApplication(bundleIdentifier: "com.apple.UserNotificationCenter"))
        shot("auth")
    }

    @MainActor func testD2_SharePicker() {
        let probe = XCUIApplication(bundleIdentifier: probeID)
        probe.launch()
        probe.buttons["share"].click()
        sleep(2)
        dump("probe-share", probe)
        shot("share")
        probe.typeKey(.escape, modifierFlags: [])
        sleep(1)
    }

    @MainActor func testD3_AlertAndPanels() {
        for id in [probeID, sbxID] {
            let probe = XCUIApplication(bundleIdentifier: id)
            probe.launch()
            probe.buttons["alert"].click()
            sleep(1)
            dump("\(id)-alert", probe)
            probe.typeKey(.escape, modifierFlags: [])
            sleep(1)
            probe.buttons["openPanel"].click()
            sleep(2)
            dump("\(id)-openPanel", probe)
            dump("openSavePanelService-open", XCUIApplication(bundleIdentifier: "com.apple.appkit.xpc.openAndSavePanelService"))
            shot("\(id)-open")
            probe.typeKey(.escape, modifierFlags: [])
            sleep(1)
            probe.buttons["savePanel"].click()
            sleep(2)
            dump("\(id)-savePanel", probe)
            dump("openSavePanelService-save", XCUIApplication(bundleIdentifier: "com.apple.appkit.xpc.openAndSavePanelService"))
            probe.typeKey(.escape, modifierFlags: [])
            sleep(1)
            probe.terminate()
        }
    }
}
