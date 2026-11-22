import AppKit
import XCTest

final class Stage0aDiscover4Tests: XCTestCase {
    @MainActor func testG1_BannerTree() {
        let probe = XCUIApplication(bundleIdentifier: probeID)
        probe.launch()
        probe.buttons["post1"].click()
        sleep(3)
        dump("banner-fg", XCUIApplication(bundleIdentifier: ncID))
        XCUIApplication(bundleIdentifier: "com.apple.finder").activate()
        probe.buttons["post1"].click()  // probe is behind Finder; click activates it? record
        sleep(3)
        dump("banner-2", XCUIApplication(bundleIdentifier: ncID))
    }

    @MainActor func testG2_PasteboardFromRunner() {
        let pb = NSPasteboard.general
        pb.clearContents()
        let ok = pb.setString("ntk synthetic paste", forType: .string)
        print("runner setString ok=\(ok) readback=\(pb.string(forType: .string) ?? "nil") home=\(NSHomeDirectory())")
        let probe = XCUIApplication(bundleIdentifier: probeID)
        probe.launch()
        sleep(1)
        dump("paste-tree", probe)
    }
}
