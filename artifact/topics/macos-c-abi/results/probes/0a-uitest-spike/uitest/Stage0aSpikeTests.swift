// Spike for macos-c-abi 0a / 1a-8. Runs only inside the qualified macOS 15 VM (no personal
// account, no shared clipboard or folders). Drives the probe app (dev.ntkprobe.notif0a) and the
// system UI (Notification Center, share picker, panels). Nothing is sent: the share picker is only
// listed and closed. Run S01 first on a fresh authorization state (ncreset.sh).
import AppKit
import XCTest

let finderID = "com.apple.finder"

func mark(_ s: String) {
    // The runner is sandboxed and cannot write the probe's log; print a timed marker instead.
    let f = DateFormatter(); f.dateFormat = "HH:mm:ss.SSS"; f.timeZone = TimeZone(identifier: "UTC")
    print("MARK \(f.string(from: Date())) \(s)")
}

final class Stage0aSpikeTests: XCTestCase {
    let probe = XCUIApplication(bundleIdentifier: probeID)
    let nc = XCUIApplication(bundleIdentifier: ncID)

    override func setUp() { continueAfterFailure = false; mark(name) }

    func lastEvent() -> String { (probe.staticTexts["lastEvent"].value as? String) ?? "" }
    func waitEvent(_ text: String, timeout: TimeInterval = 8) -> Bool {
        probe.staticTexts.matching(NSPredicate(format: "value CONTAINS %@", text)).firstMatch.waitForExistence(timeout: timeout)
    }
    func banner(_ title: String) -> XCUIElement {
        nc.groups.matching(NSPredicate(format: "label CONTAINS %@", title)).firstMatch
    }
    func waitReceive(_ text: String, timeout: TimeInterval = 8) -> Bool {
        let ok = probe.staticTexts.matching(NSPredicate(format: "value CONTAINS %@", text)).firstMatch.waitForExistence(timeout: timeout)
        print("lastReceive=\((probe.staticTexts["lastReceive"].value as? String) ?? "-")")
        return ok
    }
    func toBackground() {
        XCUIApplication(bundleIdentifier: finderID).activate()
        sleep(1)
    }
    /// Posts a notification that fires after `seconds` and returns its title.
    func post(_ button: String) -> String {
        probe.buttons["clearAll"].click()
        probe.buttons[button].click()
        XCTAssertTrue(waitEvent("added id="), "add failed: \(lastEvent())")
        let id = lastEvent().components(separatedBy: "added id=")[1].components(separatedBy: " ")[0]
        return "NTK probe \(id)"
    }
    func chooseOption(on b: XCUIElement, _ title: String) {
        b.hover()
        let options = nc.menuButtons["Options"].firstMatch
        XCTAssertTrue(options.waitForExistence(timeout: 3), "no Options button")
        options.click()
        let item = nc.menuItems[title].firstMatch
        if !item.waitForExistence(timeout: 3) { dump("options-menu-missing-\(title)", nc) }
        XCTAssertTrue(item.exists, "no menu item \(title)")
        item.click()
    }

    // MARK: authorization

    @MainActor func testS01_AuthorizationPromptAllow() {
        probe.launch()
        probe.buttons["authStatus"].click()
        XCTAssertTrue(waitEvent("authStatus=0"), "not notDetermined: \(lastEvent())")
        probe.buttons["reqAuth"].click()
        let item = banner("“NtkProbe0a” Notifications")
        let t0 = Date()
        XCTAssertTrue(item.waitForExistence(timeout: 5))
        print("auth prompt after \(Date().timeIntervalSince(t0))s")
        item.hover()
        nc.menuButtons["Options"].firstMatch.click()
        sleep(1)
        dump("auth-options-menu", nc)
        nc.menuItems["Allow"].firstMatch.click()
        XCTAssertTrue(waitEvent("auth granted=true"), lastEvent())
    }

    // MARK: banners and actions while the app runs (1a-8 running cases)

    @MainActor func testS02_ForegroundBanner() {
        probe.launch()
        let title = post("post1")
        let b = banner(title)
        let t0 = Date()
        XCTAssertTrue(b.waitForExistence(timeout: 6))
        print("foreground banner after \(Date().timeIntervalSince(t0))s")
        dump("banner-foreground", nc)
        XCTAssertTrue(waitEvent("willPresent"), lastEvent())
        b.hover()
        sleep(1)
        dump("banner-foreground-hover", nc)
        sleep(1)
        b.click()
        XCTAssertTrue(waitReceive("didReceive action=com.apple.UNNotificationDefaultActionIdentifier"))
    }

    @MainActor func testS03_RunningBackgroundBodyClick() {
        probe.launch()
        let title = post("post8")
        toBackground()
        let b = banner(title)
        let t0 = Date()
        XCTAssertTrue(b.waitForExistence(timeout: 15))
        print("background banner (8s trigger) after \(Date().timeIntervalSince(t0))s")
        sleep(1)
        b.click()
        XCTAssertTrue(probe.wait(for: .runningForeground, timeout: 5))
        XCTAssertTrue(waitReceive("action=com.apple.UNNotificationDefaultActionIdentifier text=- first=true dbaSoFar=1"))
    }

    @MainActor func testS04_RunningBackgroundForegroundAction() {
        probe.launch()
        let title = post("post1")
        toBackground()
        let b = banner(title)
        XCTAssertTrue(b.waitForExistence(timeout: 6))
        chooseOption(on: b, "Open FG")
        XCTAssertTrue(probe.wait(for: .runningForeground, timeout: 5))
        XCTAssertTrue(waitReceive("action=FG text=- first=true dbaSoFar=1"))
    }

    @MainActor func testS05_RunningBackgroundBackgroundAction() {
        probe.launch()
        let title = post("post1")
        toBackground()
        let b = banner(title)
        XCTAssertTrue(b.waitForExistence(timeout: 6))
        chooseOption(on: b, "Mark BG")
        XCTAssertTrue(waitReceive("action=BG text=- first=true dbaSoFar=1"))
        sleep(1)
        print("probe state after BG action: \(probe.state.rawValue)")
    }

    @MainActor func testS06_RunningBackgroundTextInput() {
        probe.launch()
        let title = post("post1")
        toBackground()
        let b = banner(title)
        XCTAssertTrue(b.waitForExistence(timeout: 6))
        chooseOption(on: b, "Reply")
        sleep(1)
        dump("reply-ui", nc)
        let field = nc.textFields.firstMatch.exists ? nc.textFields.firstMatch : nc.textViews.firstMatch
        XCTAssertTrue(field.waitForExistence(timeout: 3), "no reply field")
        field.typeText("hello ntk")
        if nc.buttons["Send"].exists { nc.buttons["Send"].click() } else { field.typeKey(.return, modifierFlags: []) }
        XCTAssertTrue(waitReceive("action=TXT text=hello ntk first=true dbaSoFar=1"))
        sleep(1)
        print("probe state after text action: \(probe.state.rawValue)")
    }

    @MainActor func testS07_ScheduledTenSeconds() {
        probe.launch()
        let title = post("post10")
        let posted = Date()
        toBackground()
        let b = banner(title)
        XCTAssertTrue(b.waitForExistence(timeout: 25))
        print("scheduled 10s banner seen after \(Date().timeIntervalSince(posted))s")
        sleep(6)
        print("banner still present after 6s: \(b.exists)")
    }

    // MARK: cold start (1a-8 stopped cases)

    func coldStart(_ choose: (XCUIElement) -> Void, expectForeground: Bool, expect: String) {
        probe.launch()
        probe.buttons["clearAll"].click()
        let title = post("post8")
        probe.terminate()
        XCTAssertEqual(probe.state, .notRunning)
        mark("\(name) terminated")
        let b = banner(title)
        XCTAssertTrue(b.waitForExistence(timeout: 15))
        sleep(1)
        choose(b)
        if expectForeground {
            XCTAssertTrue(probe.wait(for: .runningForeground, timeout: 8), "state=\(probe.state.rawValue)")
        } else {
            sleep(4)
        }
        XCTAssertTrue(waitReceive(expect, timeout: 10))
        print("cold start state=\(probe.state.rawValue)")
    }

    @MainActor func testS08_ColdStartBodyClick() {
        coldStart({ $0.click() }, expectForeground: true, expect: "action=com.apple.UNNotificationDefaultActionIdentifier text=- first=true dbaSoFar=0")
    }

    @MainActor func testS09_ColdStartForegroundAction() {
        coldStart({ self.chooseOption(on: $0, "Open FG") }, expectForeground: true, expect: "action=FG text=- first=true dbaSoFar=0")
    }

    @MainActor func testS10_ColdStartBackgroundAction() {
        coldStart({ self.chooseOption(on: $0, "Mark BG") }, expectForeground: false, expect: "action=BG text=- first=true dbaSoFar=0")
    }

    @MainActor func testS11_ColdStartTextInput() {
        coldStart({ b in
            self.chooseOption(on: b, "Reply")
            let field = self.nc.textFields.firstMatch.exists ? self.nc.textFields.firstMatch : self.nc.textViews.firstMatch
            XCTAssertTrue(field.waitForExistence(timeout: 3), "no reply field")
            field.typeText("cold ntk")
            if self.nc.buttons["Send"].exists { self.nc.buttons["Send"].click() } else { field.typeKey(.return, modifierFlags: []) }
        }, expectForeground: false, expect: "action=TXT text=cold ntk first=true dbaSoFar=0")
    }

    @MainActor func testS12_RunningActiveBodyClick() {
        probe.launch()
        let title = post("post1")
        let b = banner(title)
        XCTAssertTrue(b.waitForExistence(timeout: 6))
        sleep(1)
        b.click()
        XCTAssertTrue(waitReceive("action=com.apple.UNNotificationDefaultActionIdentifier text=- first=true dbaSoFar=1"))
    }

    // MARK: share picker, alert, panels, paste

    @MainActor func testS20_SharePickerListsServices() {
        probe.launch()
        probe.buttons["share"].click()
        let pop = probe.popovers.firstMatch
        XCTAssertTrue(pop.waitForExistence(timeout: 3))
        let names = pop.buttons.allElementsBoundByIndex.map { $0.label }
        print("share services: \(names)")
        XCTAssertTrue(names.contains("Mail"))
        print("Copy present: \(names.contains("Copy"))")
        probe.typeKey(.escape, modifierFlags: [])
        XCTAssertTrue(waitEvent("share didChoose=nil"), lastEvent())
    }

    @MainActor func testS21_AlertHelpAndButtons() {
        probe.launch()
        probe.buttons["alert"].click()
        let alert = probe.dialogs.matching(NSPredicate(format: "label == 'alert'")).firstMatch
        XCTAssertTrue(alert.waitForExistence(timeout: 3))
        alert.buttons["Help"].click()
        XCTAssertTrue(waitEvent("alertShowHelp"), lastEvent())
        alert.buttons["OK"].click()
        XCTAssertTrue(waitEvent("alert result=1000"), lastEvent())
        probe.buttons["alert"].click()
        XCTAssertTrue(alert.waitForExistence(timeout: 3))
        alert.buttons["action-button-2"].click()
        XCTAssertTrue(waitEvent("alert result=1001"), lastEvent())
    }

    func panels(_ app: XCUIApplication) {
        app.launch()
        app.buttons["savePanel"].click()
        let save = app.dialogs["save-panel"].exists ? app.dialogs["save-panel"] : app.dialogs.firstMatch
        XCTAssertTrue(save.waitForExistence(timeout: 5))
        dump("save-panel-\(app.identifier)", app)
        save.buttons["Save"].firstMatch.click()
        // A second save asks to replace; accept it.
        if app.buttons["Replace"].waitForExistence(timeout: 2) { app.buttons["Replace"].click() }
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "value CONTAINS 'savePanel result=1'")).firstMatch.waitForExistence(timeout: 5))
        app.buttons["openPanel"].click()
        let open = app.dialogs["open-panel"]
        XCTAssertTrue(open.waitForExistence(timeout: 5))
        let file = open.descendants(matching: .any).matching(NSPredicate(format: "value == 'probe-save.txt' OR label == 'probe-save.txt' OR title == 'probe-save.txt'")).firstMatch
        XCTAssertTrue(file.waitForExistence(timeout: 5), "saved file not listed")
        file.click()
        open.buttons["Open"].firstMatch.click()
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "value CONTAINS 'openPanel result=1 urls=[\"probe-save.txt\"]'")).firstMatch.waitForExistence(timeout: 5),
                      (app.staticTexts["lastEvent"].value as? String) ?? "")
        app.terminate()
    }

    @MainActor func testS22_PanelsNotSandboxed() { panels(probe) }
    @MainActor func testS23_PanelsSandboxed() { panels(XCUIApplication(bundleIdentifier: sbxID)) }

    @MainActor func testS24_PasteButtonAndPrivacyPrompt() {
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.setString("ntk synthetic paste", forType: .string)
        probe.launch()
        sleep(1)
        probe.buttons["pasteButton"].click()
        let allowPaste = probe.buttons["Allow Paste"].firstMatch
        print("pasteButton prompted=\(allowPaste.waitForExistence(timeout: 2))")
        if allowPaste.exists { allowPaste.click() }
        XCTAssertTrue(waitEvent("pasteButton=ntk synthetic paste"), lastEvent())
        pb.clearContents()
        pb.setString("ntk synthetic paste 2", forType: .string)
        probe.buttons["readPasteboard"].click()
        let deny = probe.buttons["Don’t Allow Paste"].firstMatch
        print("programmatic read prompted=\(deny.waitForExistence(timeout: 2))")
        if deny.exists { deny.click() }
        sleep(1)
        print("after programmatic read: \(lastEvent())")
    }
}
