import XCTest

final class Stage0aDiscover3Tests: XCTestCase {
    override func setUp() { continueAfterFailure = true }

    @MainActor func testF1_AuthPromptHover() {
        let probe = XCUIApplication(bundleIdentifier: probeID)
        probe.launch()
        probe.buttons["authStatus"].click()
        sleep(1)
        print("status before: \(probe.staticTexts["lastEvent"].value ?? "")")
        probe.buttons["reqAuth"].click()
        let nc = XCUIApplication(bundleIdentifier: ncID)
        let item = ncItems(nc).firstMatch
        let t0 = Date()
        print("authItem appeared=\(item.waitForExistence(timeout: 5)) after=\(Date().timeIntervalSince(t0))")
        dump("nc-auth-before-hover", nc)
        item.hover()
        sleep(1)
        dump("nc-auth-hover2", nc)
        sleep(20)
        print("authItem after 20s exists=\(item.exists)")
        dump("nc-auth-after20", nc)
    }
}
