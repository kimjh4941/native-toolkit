// Discovery 2: hover the authorization item in Notification Center, then banners.
import XCTest

func ncItems(_ nc: XCUIApplication) -> XCUIElementQuery {
    nc.descendants(matching: .any).matching(NSPredicate(format: "label CONTAINS %@", "NtkProbe0a"))
}

final class Stage0aDiscover2Tests: XCTestCase {
    override func setUp() { continueAfterFailure = true }

    @MainActor func testE1_AuthHover() {
        let nc = XCUIApplication(bundleIdentifier: ncID)
        let item = ncItems(nc).firstMatch
        print("authItem exists=\(item.exists)")
        if item.exists {
            item.hover()
            sleep(1)
            dump("nc-auth-hover", nc)
            shot("auth-hover")
        }
    }

    @MainActor func testE2_SandboxPanels() {
        let probe = XCUIApplication(bundleIdentifier: sbxID)
        probe.launch()
        probe.buttons["openPanel"].click()
        sleep(2)
        dump("sbx-openPanel", probe)
        shot("sbx-open")
        probe.typeKey(.escape, modifierFlags: [])
        sleep(1)
        probe.buttons["savePanel"].click()
        sleep(2)
        dump("sbx-savePanel", probe)
        probe.typeKey(.escape, modifierFlags: [])
        sleep(1)
        probe.terminate()
    }
}
