// Spike part 2: cold start by clicking the banner body, the Notification Center list, paste.
import AppKit
import XCTest

final class Stage0aSpike2Tests: XCTestCase {
    let probe = XCUIApplication(bundleIdentifier: probeID)
    let nc = XCUIApplication(bundleIdentifier: ncID)
    override func setUp() { continueAfterFailure = true; mark(name) }

    func banner(_ title: String) -> XCUIElement {
        nc.groups.matching(NSPredicate(format: "label CONTAINS %@", title)).firstMatch
    }
    func postAndTerminate() -> String {
        probe.launch()
        probe.buttons["clearAll"].click()
        probe.buttons["post8"].click()
        let p = probe.staticTexts.matching(NSPredicate(format: "value CONTAINS 'added id='")).firstMatch
        XCTAssertTrue(p.waitForExistence(timeout: 5))
        let id = (p.value as! String).components(separatedBy: "added id=")[1].components(separatedBy: " ")[0]
        probe.terminate()
        mark("\(name) terminated")
        return "NTK probe \(id)"
    }

    @MainActor func testC1_ColdBodyClickAfterHover() {
        let b = banner(postAndTerminate())
        XCTAssertTrue(b.waitForExistence(timeout: 15))
        b.hover()
        sleep(1)
        b.staticTexts["title"].click()
        mark("\(name) clicked")
        sleep(6)
        print("C1 running=\(NSRunningApplication.runningApplications(withBundleIdentifier: probeID).count)")
    }

    @MainActor func testC2_ColdBodyClickPlain() {
        let b = banner(postAndTerminate())
        XCTAssertTrue(b.waitForExistence(timeout: 15))
        sleep(1)
        b.click()
        mark("\(name) clicked")
        sleep(6)
        print("C2 running=\(NSRunningApplication.runningApplications(withBundleIdentifier: probeID).count)")
    }

    @MainActor func testC3_ColdBodyClickCoordinate() {
        let b = banner(postAndTerminate())
        XCTAssertTrue(b.waitForExistence(timeout: 15))
        sleep(1)
        b.coordinate(withNormalizedOffset: CGVector(dx: 0.3, dy: 0.5)).click()
        mark("\(name) clicked")
        sleep(6)
        print("C3 running=\(NSRunningApplication.runningApplications(withBundleIdentifier: probeID).count)")
    }

    @MainActor func testN1_NotificationCenterList() {
        let title = postAndTerminate()
        let b = banner(title)
        XCTAssertTrue(b.waitForExistence(timeout: 15))
        // Let the banner time out, then open the Notification Center from the menu bar clock.
        sleep(8)
        print("N1 banner after timeout exists=\(b.exists)")
        let cc = XCUIApplication(bundleIdentifier: "com.apple.controlcenter")
        dump("controlcenter", cc)
        let clock = cc.statusItems.matching(NSPredicate(format: "identifier CONTAINS[c] 'clock' OR label CONTAINS[c] 'clock'")).firstMatch
        if clock.exists { clock.click() } else { cc.statusItems.allElementsBoundByIndex.last?.click() }
        sleep(2)
        dump("nc-open", nc)
        let cell = banner(title)
        print("N1 cell in list exists=\(cell.exists)")
        print("N1 cell label=\(cell.exists ? cell.label : "-")")
        if cell.exists { cell.click(); mark("\(name) clicked"); sleep(6) }
        if NSRunningApplication.runningApplications(withBundleIdentifier: probeID).isEmpty {
            dump("nc-after-first-click", nc)
            let again = nc.descendants(matching: .any).matching(NSPredicate(format: "label CONTAINS %@", title)).firstMatch
            if again.exists { again.click(); mark("\(name) clicked again"); sleep(6) }
        }
        print("N1 running=\(NSRunningApplication.runningApplications(withBundleIdentifier: probeID).count)")
        XCUIApplication(bundleIdentifier: finderID).activate()
    }

    @MainActor func testP1_PasteButtonAndRead() {
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.setString("ntk synthetic paste", forType: .string)
        probe.launch()
        sleep(1)
        probe.buttons["pasteButton"].click()
        let allow = probe.buttons["Allow Paste"].firstMatch
        let prompted = allow.waitForExistence(timeout: 2)
        print("P1 pasteButton prompted=\(prompted)")
        if prompted { allow.click() }
        let got = probe.staticTexts.matching(NSPredicate(format: "value CONTAINS 'pasteButton=ntk synthetic paste'")).firstMatch.waitForExistence(timeout: 3)
        print("P1 pasteButton got=\(got)")
        probe.buttons["readPasteboard"].click()
        let deny = probe.buttons["Don’t Allow Paste"].firstMatch
        let prompted2 = deny.waitForExistence(timeout: 2)
        print("P1 read prompted=\(prompted2)")
        if prompted2 { deny.click() }
        sleep(1)
        print("P1 read result=\((probe.staticTexts["lastEvent"].value as? String) ?? "")")
    }
}
