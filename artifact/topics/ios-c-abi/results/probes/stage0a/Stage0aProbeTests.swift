//
//  Stage0aProbeTests.swift
//  IosLibraryExampleUITests
//
//  Stage 0a spike of the ios-c-abi topic (throwaway). Probes which items XCUITest can automate
//  for the sample app on the simulator. Uses labels and static texts only (identifiers are 0b).
//  Every probe prints "[PROBE] ..." lines so the host can grep the xcodebuild log.
//

import XCTest

// MARK: - Shared helpers

class Stage0aProbeBase: XCTestCase {

    var app: XCUIApplication!
    let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
    }

    func probe(_ message: String) {
        print("[PROBE] \(name) \(message)")
    }

    func launchFresh() {
        app.launch()
        XCTAssertTrue(app.wait(for: .runningForeground, timeout: 10))
    }

    func openMenu(_ title: String, file: StaticString = #filePath, line: UInt = #line) {
        let card = app.staticTexts[title]
        XCTAssertTrue(card.waitForExistence(timeout: 10), "menu card \(title) missing", file: file, line: line)
        card.tap()
    }

    /// The result `Text` always starts with "✅ \nResult:" / "❌ \nResult:" once something ran.
    func resultElement() -> XCUIElement {
        app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH '✅' OR label BEGINSWITH '❌' OR label == 'Result will be displayed here'")).firstMatch
    }

    @discardableResult
    func waitResult(contains text: String, timeout: TimeInterval = 10, file: StaticString = #filePath, line: UInt = #line) -> String {
        let element = app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", text)).firstMatch
        let found = element.waitForExistence(timeout: timeout)
        let label = found ? element.label : resultElement().label
        probe("result: \(label.replacingOccurrences(of: "\n", with: " "))")
        XCTAssertTrue(found, "result does not contain \(text): \(label)", file: file, line: line)
        return label
    }

    /// Scrolls the first scroll view until the button is hittable.
    func scrollTo(_ element: XCUIElement, maxSwipes: Int = 12, file: StaticString = #filePath, line: UInt = #line) {
        var swipes = 0
        while !(element.exists && element.isHittable) && swipes < maxSwipes {
            app.scrollViews.firstMatch.swipeUp(velocity: .slow)
            swipes += 1
        }
        swipes = 0
        while !(element.exists && element.isHittable) && swipes < maxSwipes {
            app.scrollViews.firstMatch.swipeDown(velocity: .slow)
            swipes += 1
        }
        XCTAssertTrue(element.exists && element.isHittable, "\(element) not reachable", file: file, line: line)
    }

    func tapButton(_ label: String, file: StaticString = #filePath, line: UInt = #line) {
        let button = app.buttons[label]
        if !(button.exists && button.isHittable) {
            scrollTo(button, file: file, line: line)
        }
        button.tap()
    }

    func scrollToTop() {
        for _ in 0..<4 { app.scrollViews.firstMatch.swipeDown(velocity: .fast) }
    }

    /// System UI follows the simulator language (26.2 sim: en, 18.3 sim: ja).
    func systemButton(_ container: XCUIElement, _ labels: [String]) -> XCUIElement {
        for label in labels where container.buttons[label].exists { return container.buttons[label] }
        return container.buttons[labels[0]]
    }
    static let allowLabels = ["Allow", "許可"]
    static let denyLabels = ["Don’t Allow", "許可しない"]

    /// Hierarchy dumps are simulator-only: on the (private) device they could capture other
    /// notifications, contacts in the share sheet, and so on.
    func dump(_ application: XCUIApplication, _ tag: String) {
        #if targetEnvironment(simulator)
        print("[PROBE-DUMP] \(name) \(tag)\n\(application.debugDescription)\n[PROBE-DUMP-END]")
        #else
        print("[PROBE-DUMP] \(name) \(tag) skipped on device")
        #endif
    }

    static var isDevice: Bool {
        #if targetEnvironment(simulator)
        return false
        #else
        return true
        #endif
    }

    // Springboard helpers

    /// Any springboard element whose label contains `text` (banner or Notification Center cell).
    func springboardElement(containing text: String) -> XCUIElement {
        springboard.descendants(matching: .any).matching(NSPredicate(format: "label CONTAINS %@", text)).firstMatch
    }

    /// The sample's notification platter (banner or Notification Center), by its title text.
    /// Only platters whose label carries the sample's name match, and `.element` requires exactly
    /// one match: with several matches any interaction fails instead of touching something.
    func notificationView(containing text: String) -> XCUIElement {
        springboard.descendants(matching: .any).matching(NSPredicate(format: "identifier == 'NotificationShortLookView' AND label CONTAINS[c] 'IosLibraryExample' AND label CONTAINS %@", text)).element
    }

    func openNotificationCenter() {
        let top = springboard.coordinate(withNormalizedOffset: CGVector(dx: 0.25, dy: 0.005))
        let bottom = springboard.coordinate(withNormalizedOffset: CGVector(dx: 0.25, dy: 0.7))
        top.press(forDuration: 0.1, thenDragTo: bottom)
    }

    func closeNotificationCenter() {
        XCUIDevice.shared.press(.home)
    }

    /// Ensures notification permission is granted; taps "Allow" through springboard if asked.
    func ensureNotificationPermission() {
        tapButton("AuthorizationStatus")
        let label = waitResult(contains: "[authorizationStatus]")
        if label.contains("authorized") { return }
        if label.contains("notDetermined") {
            tapButton("RequestPermission")
            let alert = springboard.alerts.firstMatch
            XCTAssertTrue(alert.waitForExistence(timeout: 10), "permission alert did not appear")
            systemButton(alert, Self.allowLabels).tap()
            waitResult(contains: "[requestPermission] granted")
            return
        }
        XCTFail("permission is \(label); uninstall the app to reset")
    }
}

// MARK: - 1. Dialog (UIAlertController)

final class Stage0aDialogProbeTests: Stage0aProbeBase {

    override func setUpWithError() throws {
        try super.setUpWithError()
        launchFresh()
        openMenu("Dialog Example")
    }

    func testD1_alert() {
        tapButton("ShowAlert")
        let alert = app.alerts["Hello from iOS"]
        XCTAssertTrue(alert.waitForExistence(timeout: 5))
        XCTAssertTrue(alert.staticTexts["This is a native iOS dialog!"].exists)
        probe("alert buttons: \(alert.buttons.allElementsBoundByIndex.map(\.label))")
        alert.buttons["OK"].tap()
        waitResult(contains: "[showAlert][onButton] buttonText: OK, isSuccess: true")
        XCTAssertFalse(alert.exists)
    }

    func testD2_confirmYesAndNo() {
        tapButton("ShowConfirmDialog")
        var alert = app.alerts["Confirm Action"]
        XCTAssertTrue(alert.waitForExistence(timeout: 5))
        alert.buttons["Yes"].tap()
        waitResult(contains: "[showConfirmDialog][onConfirm] confirmButtonText: Yes")

        tapButton("ShowConfirmDialog")
        alert = app.alerts["Confirm Action"]
        XCTAssertTrue(alert.waitForExistence(timeout: 5))
        alert.buttons["No"].tap()
        waitResult(contains: "[showConfirmDialog][onCancel] cancelButtonText: No")
    }

    func testD3_destructive() {
        tapButton("ShowDestructiveDialog")
        let alert = app.alerts["Delete File"]
        XCTAssertTrue(alert.waitForExistence(timeout: 5))
        alert.buttons["Delete"].tap()
        waitResult(contains: "[showDestructiveDialog][onDestructive] destructiveButtonText: Delete")

        tapButton("ShowDestructiveDialog")
        XCTAssertTrue(app.alerts["Delete File"].waitForExistence(timeout: 5))
        app.alerts["Delete File"].buttons["Cancel"].tap()
        waitResult(contains: "[showDestructiveDialog][onCancel] cancelButtonText: Cancel")
    }

    func testD4_actionSheet() {
        tapButton("ShowActionSheet")
        let option = app.buttons["Photo Library"]
        XCTAssertTrue(option.waitForExistence(timeout: 5))
        probe("sheets: \(app.sheets.count), alerts: \(app.alerts.count)")
        if app.sheets.count > 0 {
            probe("sheet buttons: \(app.sheets.firstMatch.buttons.allElementsBoundByIndex.map(\.label))")
        } else {
            dump(app, "actionSheet")
        }
        option.tap()
        waitResult(contains: "[showActionSheet][onAction] action: Photo Library")

        tapButton("ShowActionSheet")
        XCTAssertTrue(app.buttons["Photo Library"].waitForExistence(timeout: 5))
        let cancel = app.buttons["Cancel"]
        let cancelExists = cancel.waitForExistence(timeout: 2)
        probe("Cancel exists=\(cancelExists) hittable=\(cancelExists && cancel.isHittable)")
        if cancelExists && cancel.isHittable {
            cancel.tap()
        } else {
            // iOS 26 presents the sheet as a popover without Cancel; tap the dismiss region.
            let region = app.otherElements["PopoverDismissRegion"]
            probe("Cancel not hittable; PopoverDismissRegion exists=\(region.exists) label=\(region.exists ? region.label : "-")")
            XCTAssertTrue(region.exists)
            region.tap()
        }
        waitResult(contains: "[showActionSheet][onAction] action: Cancel")
    }

    func testD5_textInput() {
        tapButton("ShowTextInputDialog")
        let alert = app.alerts["Enter Name"]
        XCTAssertTrue(alert.waitForExistence(timeout: 5))
        let ok = alert.buttons["OK"]
        probe("OK enabled while empty: \(ok.isEnabled)")
        XCTAssertFalse(ok.isEnabled, "enableConfirmWhenEmpty=false should disable OK")
        let field = alert.textFields.firstMatch
        probe("textField placeholder: \(field.placeholderValue ?? "nil")")
        field.tap()
        field.typeText("Taro 太郎")
        XCTAssertTrue(ok.isEnabled)
        ok.tap()
        waitResult(contains: "inputText: Taro 太郎")

        tapButton("ShowTextInputDialog")
        XCTAssertTrue(app.alerts["Enter Name"].waitForExistence(timeout: 5))
        app.alerts["Enter Name"].buttons["Cancel"].tap()
        waitResult(contains: "[showTextInputDialog][onCancel] cancelButtonText: Cancel")
    }

    func testD6_login() {
        tapButton("ShowLoginDialog")
        let alert = app.alerts["Login Required"]
        XCTAssertTrue(alert.waitForExistence(timeout: 5))
        let login = alert.buttons["Login"]
        probe("Login enabled while empty: \(login.isEnabled)")
        probe("textFields: \(alert.textFields.count), secureTextFields: \(alert.secureTextFields.count)")
        let user = alert.textFields.firstMatch
        user.tap()
        user.typeText("taro")
        probe("Login enabled with only username: \(login.isEnabled)")
        let password = alert.secureTextFields.firstMatch
        password.tap()
        password.typeText("secret1")
        XCTAssertTrue(login.isEnabled)
        login.tap()
        waitResult(contains: "username: taro, password: secret1")
    }
}

// MARK: - 2. Notification permission (first consent)

/// Run each test on a freshly installed app (host: `xcrun simctl uninstall <udid> <bundle>`).
final class Stage0aPermissionProbeTests: Stage0aProbeBase {

    override func setUpWithError() throws {
        try super.setUpWithError()
        launchFresh()
        openMenu("Notification Example")
    }

    private func requireNotDetermined() throws {
        tapButton("AuthorizationStatus")
        let label = waitResult(contains: "[authorizationStatus]")
        if !label.contains("notDetermined") {
            throw XCTSkip("permission is not notDetermined: \(label)")
        }
    }

    func testP1_interruptionMonitor() throws {
        try requireNotDetermined()
        var handledLabel: String?
        let token = addUIInterruptionMonitor(withDescription: "notification permission") { alert in
            self.probe("monitor fired: \(alert.label) buttons: \(alert.buttons.allElementsBoundByIndex.map(\.label))")
            handledLabel = alert.label
            let allow = self.systemButton(alert, Self.allowLabels)
            if allow.exists {
                allow.tap()
                return true
            }
            return false
        }
        defer { removeUIInterruptionMonitor(token) }
        tapButton("RequestPermission")
        // The monitor only fires when the test next interacts with the app.
        let deadline = Date().addingTimeInterval(10)
        while handledLabel == nil && Date() < deadline {
            sleep(1)
            app.swipeUp(velocity: .slow) // harmless interaction to trigger the monitor
        }
        probe("handled: \(handledLabel ?? "nil")")
        XCTAssertNotNil(handledLabel, "interruption monitor did not fire")
        waitResult(contains: "[requestPermission] granted")
    }

    func testP2_springboardAlert() throws {
        try requireNotDetermined()
        tapButton("RequestPermission")
        let alert = springboard.alerts.firstMatch
        let start = Date()
        XCTAssertTrue(alert.waitForExistence(timeout: 10))
        probe("alert after \(String(format: "%.1f", Date().timeIntervalSince(start)))s label: \(alert.label) buttons: \(alert.buttons.allElementsBoundByIndex.map(\.label))")
        systemButton(alert, Self.allowLabels).tap()
        waitResult(contains: "[requestPermission] granted")
    }

    /// No monitor of our own: does XCTest's default interruption handler answer the alert?
    func testP4_defaultHandlerOnly() throws {
        try requireNotDetermined()
        tapButton("RequestPermission")
        XCTAssertTrue(springboard.alerts.firstMatch.waitForExistence(timeout: 10))
        // Interact with the app so XCTest notices the interrupting alert.
        tapButton("HasPermission")
        let label = waitResult(contains: "[requestPermission]", timeout: 10)
        probe("after default handler: \(label.replacingOccurrences(of: "\n", with: " "))")
    }

    func testP3_springboardDeny() throws {
        try requireNotDetermined()
        tapButton("RequestPermission")
        let alert = springboard.alerts.firstMatch
        XCTAssertTrue(alert.waitForExistence(timeout: 10))
        systemButton(alert, Self.denyLabels).tap()
        waitResult(contains: "[requestPermission] denied")
        tapButton("AuthorizationStatus")
        waitResult(contains: "[authorizationStatus] denied")
    }
}

// MARK: - 3〜5. Notification banner / Notification Center / actions / cold start / schedule

final class Stage0aNotificationProbeTests: Stage0aProbeBase {

    override func setUpWithError() throws {
        try super.setUpWithError()
        launchFresh()
        openMenu("Notification Example")
        ensureNotificationPermission()
        scrollToTop()
        tapButton("RemoveAllDelivered")
        waitResult(contains: "[removeAllDelivered] called")
    }

    private func waitBanner(_ title: String, timeout: TimeInterval) -> (XCUIElement, TimeInterval)? {
        let start = Date()
        let banner = notificationView(containing: title)
        guard banner.waitForExistence(timeout: timeout) else { return nil }
        return (banner, Date().timeIntervalSince(start))
    }

    func testN1_foregroundBanner() {
        tapButton("ShowImmediate")
        waitResult(contains: "[showImmediate] error: nil")
        guard let (banner, elapsed) = waitBanner("Immediate Notification", timeout: 10) else {
            dump(springboard, "noBanner")
            XCTFail("banner not found")
            return
        }
        probe(String(format: "banner after %.1fs type=%lu id=%@ label=%@", elapsed, banner.elementType.rawValue, banner.identifier, banner.label))
        XCTAssertTrue(banner.label.contains("Displayed now"), "body missing: \(banner.label)")
        dump(springboard, "banner")
    }

    func testN2_backgroundBanner() {
        tapButton("ShowImmediate")
        // Start in background: the 5 s trigger fires while the app is not frontmost.
        tapButton("ShowTimeInterval(5s)")
        waitResult(contains: "[showTimeInterval] error: nil")
        let start = Date()
        XCUIDevice.shared.press(.home)
        let banner = notificationView(containing: "5s Notification")
        let found = banner.waitForExistence(timeout: 20)
        probe(String(format: "background banner found=%@ after %.1fs (since home) label=%@", found ? "true" : "false", Date().timeIntervalSince(start), found ? banner.label : "-"))
        if !found { dump(springboard, "noBgBanner") }
        XCTAssertTrue(found)
        probe("app state while banner shown: \(app.state.rawValue)")
    }

    func testN3_scheduledTenSeconds() {
        tapButton("ScheduleTimeInterval(10s)")
        let start = Date()
        waitResult(contains: "[scheduleTimeInterval] id: scheduled-notification, error: nil")
        let banner = notificationView(containing: "Scheduled Notification")
        let found = banner.waitForExistence(timeout: 25)
        probe(String(format: "scheduled banner found=%@ after %.1fs", found ? "true" : "false", Date().timeIntervalSince(start)))
        XCTAssertTrue(found)
    }

    func testN4_notificationCenterTapOpensApp() {
        tapButton("ShowImmediate")
        waitResult(contains: "[showImmediate] error: nil")
        XCUIDevice.shared.press(.home)
        // Let the banner go away so the cell is only in Notification Center.
        sleep(7)
        openNotificationCenter()
        let cell = notificationView(containing: "Immediate Notification")
        let found = cell.waitForExistence(timeout: 10)
        probe("NC cell found=\(found) label=\(found ? cell.label : "-") frame=\(found ? "\(cell.frame)" : "-")")
        if !found { dump(springboard, "noNCcell") }
        XCTAssertTrue(found)
        sleep(1) // let the cover sheet settle
        cell.swipeRight() // a tap does not open the app from Notification Center (N4b)
        let foreground = app.wait(for: .runningForeground, timeout: 10)
        probe("app foreground after tap: \(foreground) state=\(app.state.rawValue)")
        if !foreground { dump(springboard, "afterNCtap") }
        XCTAssertTrue(foreground)
        tapButton("GetDelivered")
        waitResult(contains: "[getDelivered]")
    }

    /// Tries several ways to open the app from a Notification Center cell and logs which one works.
    func testN4b_notificationCenterTapStrategies() {
        tapButton("ShowImmediate")
        waitResult(contains: "[showImmediate] error: nil")
        XCUIDevice.shared.press(.home)
        sleep(7)
        openNotificationCenter()
        let view = notificationView(containing: "Immediate Notification")
        XCTAssertTrue(view.waitForExistence(timeout: 10))
        sleep(1)
        let strategies: [(String, () -> Void)] = [
            ("innerSeamlessButton", {
                self.springboard.buttons.matching(NSPredicate(format: "identifier == 'ShortLook.Platter.Content.Seamless' AND label CONTAINS 'Immediate Notification'")).element.tap()
            }),
            ("titleStaticText", {
                self.springboard.staticTexts.matching(NSPredicate(format: "identifier == 'NotificationTitle' AND label == 'Immediate Notification'")).element.tap()
            }),
            ("coordinateTap", {
                view.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
            }),
            ("secondTapOnView", { view.tap() })
        ]
        var opened = "none"
        for (name, action) in strategies {
            guard view.exists else { probe("view vanished before \(name)"); break }
            action()
            if app.wait(for: .runningForeground, timeout: 5) { opened = name; break }
            probe("\(name): still state=\(app.state.rawValue)")
        }
        probe("NC open strategy that worked: \(opened)")
        XCTAssertNotEqual(opened, "none")
    }

    /// Holds the state after an NC tap so the host can take screenshots (`simctl io screenshot`).
    func testN4c_holdAfterNCTap() {
        tapButton("ShowImmediate")
        waitResult(contains: "[showImmediate] error: nil")
        XCUIDevice.shared.press(.home)
        sleep(7)
        probe("HOLD-1 home, before NC \(Date().timeIntervalSince1970)")
        openNotificationCenter()
        let view = notificationView(containing: "Immediate Notification")
        XCTAssertTrue(view.waitForExistence(timeout: 10))
        sleep(4)
        probe("HOLD-2 NC open, tapping \(Date().timeIntervalSince1970)")
        view.tap()
        sleep(8)
        probe("HOLD-3 after tap state=\(app.state.rawValue) \(Date().timeIntervalSince1970)")
        // Try a swipe up from the bottom edge (the lock screen's "open" gesture).
        springboard.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.995))
            .press(forDuration: 0.05, thenDragTo: springboard.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.4)))
        let foreground = app.wait(for: .runningForeground, timeout: 8)
        probe("HOLD-4 after bottom swipe foreground=\(foreground) \(Date().timeIntervalSince1970)")
    }

    func testN4d_notificationCenterOtherGestures() {
        tapButton("ShowImmediate")
        waitResult(contains: "[showImmediate] error: nil")
        XCUIDevice.shared.press(.home)
        sleep(7)
        openNotificationCenter()
        let view = notificationView(containing: "Immediate Notification")
        XCTAssertTrue(view.waitForExistence(timeout: 10))
        sleep(2)
        var opened = "none"
        // 1. short press (0.3 s)
        view.press(forDuration: 0.3)
        if app.wait(for: .runningForeground, timeout: 4) { opened = "press0.3" }
        // 2. swipe right (reveals "Open" on older iOS)
        if opened == "none", view.exists {
            view.swipeRight()
            sleep(1)
            if !Self.isDevice {
                let openButtons = springboard.buttons.allElementsBoundByIndex.map(\.label).filter { !$0.isEmpty }
                probe("after swipeRight buttons: \(openButtons.prefix(30))")
            }
            for label in ["Open", "開く"] where springboard.buttons[label].exists {
                springboard.buttons[label].tap()
            }
            if app.wait(for: .runningForeground, timeout: 4) { opened = "swipeRight" }
        }
        // 3. long press -> tap the expanded (long look) content
        if opened == "none", view.exists {
            view.press(forDuration: 1.5)
            sleep(1)
            dump(springboard, "longLookNC")
            let longLook = springboard.descendants(matching: .any).matching(NSPredicate(format: "identifier CONTAINS 'LongLook' OR identifier CONTAINS 'Expanded'")).firstMatch
            probe("longLook exists=\(longLook.exists) id=\(longLook.exists ? longLook.identifier : "-")")
            let title = springboard.staticTexts.matching(NSPredicate(format: "label == 'Immediate Notification'")).firstMatch
            if title.exists { title.tap() }
            if app.wait(for: .runningForeground, timeout: 4) { opened = "longPressThenTapContent" }
        }
        probe("NC other gesture that worked: \(opened)")
    }

    /// Which long-press variant expands a Notification Center cell (18.3 did not expand with 1.5 s).
    func testN9b_ncExpandVariants() {
        tapButton("RegisterCategory")
        waitResult(contains: "[registerCategory] Registered")
        scrollToTop()
        tapButton("ShowImmediate")
        waitResult(contains: "[showImmediate] error: nil")
        XCUIDevice.shared.press(.home)
        sleep(7)
        openNotificationCenter()
        let cell = notificationView(containing: "Immediate Notification")
        XCTAssertTrue(cell.waitForExistence(timeout: 10))
        sleep(3)
        let open = springboard.buttons["Open"]
        let variants: [(String, () -> Void)] = [
            ("cell 1.5s", { cell.press(forDuration: 1.5) }),
            ("inner button 2.5s", {
                self.springboard.buttons.matching(NSPredicate(format: "identifier == 'ShortLook.Platter.Content.Seamless' AND label CONTAINS 'Immediate Notification'")).element.press(forDuration: 2.5)
            }),
            ("coordinate 3.0s", { cell.coordinate(withNormalizedOffset: CGVector(dx: 0.3, dy: 0.5)).press(forDuration: 3.0) })
        ]
        var worked = "none"
        for (name, action) in variants {
            action()
            if open.waitForExistence(timeout: 4) { worked = name; break }
            probe("\(name): Open not shown")
        }
        probe("NC expand variant that worked: \(worked)")
        if worked != "none" {
            open.tap()
            probe("foreground after Open: \(app.wait(for: .runningForeground, timeout: 10))")
        }
    }

    /// Cold start by tapping the banner of a notification that fires after the app was terminated.
    func testN10_coldStartFromBannerTap() {
        tapButton("ShowTimeInterval(5s)")
        waitResult(contains: "[showTimeInterval] error: nil")
        app.terminate()
        XCTAssertTrue(app.wait(for: .notRunning, timeout: 10))
        let banner = notificationView(containing: "5s Notification")
        XCTAssertTrue(banner.waitForExistence(timeout: 15))
        probe("app state when banner shown: \(app.state.rawValue)")
        banner.tap()
        let foreground = app.wait(for: .runningForeground, timeout: 15)
        probe("cold start via banner tap foreground=\(foreground)")
        XCTAssertTrue(foreground)
    }

    /// Cold start through the banner's "Open" action (expanded by long press).
    func testN11_coldStartFromBannerAction() {
        tapButton("RegisterCategory")
        waitResult(contains: "[registerCategory] Registered")
        scrollToTop()
        tapButton("ShowTimeInterval(5s)")
        waitResult(contains: "[showTimeInterval] error: nil")
        app.terminate()
        XCTAssertTrue(app.wait(for: .notRunning, timeout: 10))
        let banner = notificationView(containing: "5s Notification")
        XCTAssertTrue(banner.waitForExistence(timeout: 15))
        banner.press(forDuration: 1.5)
        let open = springboard.buttons["Open"]
        let found = open.waitForExistence(timeout: 5)
        probe("banner long press (app terminated) -> Open found=\(found)")
        XCTAssertTrue(found)
        open.tap()
        let foreground = app.wait(for: .runningForeground, timeout: 15)
        probe("cold start via banner Open foreground=\(foreground)")
        XCTAssertTrue(foreground)
    }

    func testN1b_foregroundBannerTap() {
        tapButton("ShowTimeInterval(5s)")
        waitResult(contains: "[showTimeInterval] error: nil")
        XCUIDevice.shared.press(.home)
        let banner = notificationView(containing: "5s Notification")
        XCTAssertTrue(banner.waitForExistence(timeout: 20))
        banner.tap()
        let foreground = app.wait(for: .runningForeground, timeout: 10)
        probe("banner tap from home -> foreground=\(foreground)")
        XCTAssertTrue(foreground)
    }

    func testN5_actionButtonOpen() {
        tapButton("RegisterCategory")
        waitResult(contains: "[registerCategory] Registered")
        scrollToTop()
        tapButton("ShowImmediate")
        guard let (banner, _) = waitBanner("Immediate Notification", timeout: 10) else {
            XCTFail("banner not found"); return
        }
        banner.press(forDuration: 1.5)
        let open = springboard.buttons["Open"]
        let found = open.waitForExistence(timeout: 5)
        probe("expanded: Open=\(found) Delete=\(springboard.buttons["Delete"].exists) Reply=\(springboard.buttons["Reply"].exists)")
        dump(springboard, "expanded")
        XCTAssertTrue(found)
        open.tap()
        XCTAssertTrue(app.wait(for: .runningForeground, timeout: 10))
        probe("app state after Open: \(app.state.rawValue)")
    }

    func testN6_actionButtonFromBackground() {
        tapButton("RegisterCategory")
        waitResult(contains: "[registerCategory] Registered")
        scrollToTop()
        tapButton("ShowTimeInterval(5s)")
        waitResult(contains: "[showTimeInterval] error: nil")
        XCUIDevice.shared.press(.home)
        let banner = notificationView(containing: "5s Notification")
        XCTAssertTrue(banner.waitForExistence(timeout: 20))
        // Expand by pulling the banner down (the other common gesture).
        banner.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
            .press(forDuration: 0.1, thenDragTo: springboard.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)))
        var delete = springboard.buttons["Delete"]
        if !delete.waitForExistence(timeout: 3) {
            probe("drag-down did not expand; trying long press")
            if banner.exists { banner.press(forDuration: 1.5) }
            delete = springboard.buttons["Delete"]
        }
        let found = delete.waitForExistence(timeout: 5)
        probe("Delete found=\(found)")
        XCTAssertTrue(found)
        delete.tap()
        sleep(2)
        probe("app state after Delete (background action): \(app.state.rawValue)")
    }

    func testN7_textInputAction() {
        tapButton("RegisterCategory")
        waitResult(contains: "[registerCategory] Registered")
        scrollToTop()
        tapButton("ShowImmediate")
        guard let (banner, _) = waitBanner("Immediate Notification", timeout: 10) else {
            XCTFail("banner not found"); return
        }
        banner.press(forDuration: 1.5)
        let reply = springboard.buttons["Reply"]
        XCTAssertTrue(reply.waitForExistence(timeout: 5))
        reply.tap()
        // The reply input is a TextView (placeholder "Type a message"), not a TextField.
        let field = springboard.textViews.matching(NSPredicate(format: "placeholderValue == 'Type a message'")).firstMatch
        let fieldFound = field.waitForExistence(timeout: 5)
        probe("reply field found=\(fieldFound) placeholder=\(fieldFound ? (field.placeholderValue ?? "nil") : "-")")
        if !fieldFound { dump(springboard, "noReplyField") }
        XCTAssertTrue(fieldFound)
        field.typeText("hello probe")
        let send = springboard.buttons["Send"]
        probe("Send found=\(send.exists)")
        if !send.exists { dump(springboard, "replyField") }
        XCTAssertTrue(send.waitForExistence(timeout: 3))
        send.tap()
        sleep(2)
        probe("app state after Send: \(app.state.rawValue)")
    }

    func testN8_coldStartFromNotificationCenter() {
        tapButton("ShowImmediate")
        waitResult(contains: "[showImmediate] error: nil")
        sleep(1)
        app.terminate()
        XCTAssertTrue(app.wait(for: .notRunning, timeout: 10))
        sleep(6)
        openNotificationCenter()
        let cell = notificationView(containing: "Immediate Notification")
        XCTAssertTrue(cell.waitForExistence(timeout: 10))
        sleep(1)
        let start = Date()
        cell.swipeRight()
        let foreground = app.wait(for: .runningForeground, timeout: 15)
        probe(String(format: "cold start foreground=%@ after %.1fs", foreground ? "true" : "false", Date().timeIntervalSince(start)))
        XCTAssertTrue(foreground)
        // What does the freshly launched sample show? (It only prints the tap.)
        XCTAssertTrue(app.staticTexts["Native Toolkit iOS Example"].waitForExistence(timeout: 10))
        probe("first screen texts: \(app.staticTexts.allElementsBoundByIndex.prefix(8).map(\.label))")
    }

    /// Device variant of N8: on the device a tap (not a swipe right) opens from Notification Center.
    func testN8b_coldStartFromNotificationCenterTap() {
        tapButton("ShowImmediate")
        waitResult(contains: "[showImmediate] error: nil")
        sleep(1)
        app.terminate()
        XCTAssertTrue(app.wait(for: .notRunning, timeout: 10))
        sleep(6)
        openNotificationCenter()
        let cell = notificationView(containing: "Immediate Notification")
        XCTAssertTrue(cell.waitForExistence(timeout: 10))
        sleep(1)
        let start = Date()
        springboard.buttons.matching(NSPredicate(format: "identifier == 'ShortLook.Platter.Content.Seamless' AND label CONTAINS 'Immediate Notification'")).element.tap()
        let foreground = app.wait(for: .runningForeground, timeout: 15)
        probe(String(format: "cold start (NC tap) foreground=%@ after %.1fs", foreground ? "true" : "false", Date().timeIntervalSince(start)))
        XCTAssertTrue(foreground)
    }

    func testN9_coldStartFromActionButton() {
        tapButton("RegisterCategory")
        waitResult(contains: "[registerCategory] Registered")
        scrollToTop()
        tapButton("ShowImmediate")
        waitResult(contains: "[showImmediate] error: nil")
        sleep(1)
        app.terminate()
        XCTAssertTrue(app.wait(for: .notRunning, timeout: 10))
        sleep(6)
        openNotificationCenter()
        let cell = notificationView(containing: "Immediate Notification")
        XCTAssertTrue(cell.waitForExistence(timeout: 10))
        sleep(1)
        cell.press(forDuration: 1.5)
        let open = springboard.buttons["Open"]
        let openFound = open.waitForExistence(timeout: 5)
        probe("NC long press -> Open found=\(openFound)")
        if !openFound { dump(springboard, "ncLongPressNoOpen") }
        XCTAssertTrue(openFound)
        open.tap()
        let foreground = app.wait(for: .runningForeground, timeout: 15)
        probe("cold start via Open foreground=\(foreground)")
        XCTAssertTrue(foreground)
    }
}

// MARK: - 6. Share sheet

final class Stage0aShareProbeTests: Stage0aProbeBase {

    // System UI follows the simulator language (26.2: en, 18.3: ja).
    static let copyLabels = ["Copy", "コピー"]
    static let saveToFilesLabels = ["Save to Files", "“ファイル”に保存", "\"ファイル\"に保存"]
    static let closeLabels = ["Close", "閉じる"]
    static let saveLabels = ["Save", "保存"]

    override func setUpWithError() throws {
        try super.setUpWithError()
        launchFresh()
        openMenu("Share Example")
    }

    /// On the device the sheet lists contacts and real apps, so only known action labels are logged.
    private func safeCellLabels() -> [String] {
        let labels = app.cells.allElementsBoundByIndex.map(\.label)
        guard Self.isDevice else { return labels }
        let known = Set(Self.copyLabels + Self.saveToFilesLabels + ["Add to Reading List", "リーディングリストに追加"])
        return labels.map { known.contains($0) ? $0 : "<other>" }
    }

    private func anyLabeled(_ labels: [String]) -> XCUIElement {
        app.descendants(matching: .any).matching(NSPredicate(format: "label IN %@", labels)).firstMatch
    }

    private func waitSheet() -> XCUIElement {
        let copy = anyLabeled(Self.copyLabels)
        let start = Date()
        let found = copy.waitForExistence(timeout: 10)
        probe(String(format: "Copy found=%@ after %.1fs type=%lu", found ? "true" : "false", Date().timeIntervalSince(start), found ? copy.elementType.rawValue : 0))
        return copy
    }

    /// 18.3: a "閉じる"/"Close" button. 26.2: a popover without a close button -> dismiss region.
    private func closeSheet() {
        let close = app.buttons.matching(NSPredicate(format: "label IN %@", Self.closeLabels)).firstMatch
        let region = app.otherElements["PopoverDismissRegion"]
        probe("Close button exists: \(close.exists), PopoverDismissRegion exists: \(region.exists)")
        if close.exists { close.tap() } else { region.tap() }
    }

    func testS1_copyCompletes() {
        tapButton("ShareText")
        let copy = waitSheet()
        XCTAssertTrue(copy.exists)
        dump(app, "shareSheet")
        copy.tap()
        waitResult(contains: "[shareText] completed=true, activityType=com.apple.UIKit.activity.CopyToPasteboard")
    }

    func testS2_listTargetsAndClose() {
        tapButton("ShareText")
        XCTAssertTrue(waitSheet().exists)
        sleep(2) // the target row fills in asynchronously
        let content = app.navigationBars["UIActivityContentView"]
        probe("UIActivityContentView exists: \(content.exists)")
        probe("sheet cells: \(safeCellLabels())")
        closeSheet()
        waitResult(contains: "[shareText] completed=false")
    }

    func testS3_swipeDownDismiss() {
        tapButton("ShareURL")
        XCTAssertTrue(waitSheet().exists)
        // Drag the sheet by its header (UIActivityContentView navigation bar).
        let header = app.navigationBars["UIActivityContentView"]
        XCTAssertTrue(header.waitForExistence(timeout: 5))
        header.coordinate(withNormalizedOffset: CGVector(dx: 0.3, dy: 0.3))
            .press(forDuration: 0.1, thenDragTo: app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.99)))
        waitResult(contains: "[shareURL] completed=false", timeout: 10)
    }

    func testS4_excludedCopyIsAbsent() {
        tapButton("ShareExcludingActivities")
        XCTAssertTrue(app.navigationBars["UIActivityContentView"].waitForExistence(timeout: 10))
        sleep(2)
        let copyExists = anyLabeled(Self.copyLabels).exists
        probe("Copy exists with exclusion: \(copyExists); cells: \(safeCellLabels())")
        XCTAssertFalse(copyExists)
        closeSheet()
        waitResult(contains: "[shareExcludingActivities] completed=false")
    }

    func testS5_saveToFiles() {
        tapButton("ShareFile")
        XCTAssertTrue(waitSheet().exists)
        let save = anyLabeled(Self.saveToFilesLabels)
        if !save.exists { app.swipeUp(velocity: .slow) }
        let found = save.waitForExistence(timeout: 5)
        probe("Save to Files found=\(found)")
        if !found { dump(app, "noSaveToFiles") }
        XCTAssertTrue(found)
        save.tap()
        let saveButton = app.buttons.matching(NSPredicate(format: "label IN %@", Self.saveLabels)).firstMatch
        let pickerShown = saveButton.waitForExistence(timeout: 8)
        probe("Files picker Save exists: \(pickerShown)")
        if !pickerShown { dump(app, "filesPicker") }
        XCTAssertTrue(pickerShown)
        // Save only into "On My iPhone" (このiPhone内); otherwise cancel and report it as unchecked.
        let onMy = ["On My iPhone", "このiPhone内"]
        let atOnMy = { self.app.navigationBars.matching(NSPredicate(format: "identifier IN %@", onMy)).count > 0
            || self.app.navigationBars.staticTexts.matching(NSPredicate(format: "label IN %@", onMy)).count > 0 }
        probe("picker initially at On My iPhone: \(atOnMy())")
        if !atOnMy() {
            let browse = app.navigationBars.buttons.matching(NSPredicate(format: "label IN %@", ["Browse", "ブラウズ"])).firstMatch
            if browse.exists { browse.tap() }
            let location = app.descendants(matching: .any).matching(NSPredicate(format: "label IN %@ AND (elementType == %d OR elementType == %d OR elementType == %d)", onMy, XCUIElement.ElementType.cell.rawValue, XCUIElement.ElementType.button.rawValue, XCUIElement.ElementType.staticText.rawValue)).firstMatch
            if location.waitForExistence(timeout: 5) { location.tap() }
            sleep(1)
            probe("picker after navigation at On My iPhone: \(atOnMy())")
        }
        guard atOnMy() else {
            let cancel = app.buttons.matching(NSPredicate(format: "label IN %@", ["Cancel", "キャンセル"])).firstMatch
            if cancel.exists { cancel.tap() }
            XCTFail("未確認: could not select On My iPhone; cancelled the picker")
            return
        }
        saveButton.tap()
        // A replace prompt may appear on reruns. "Replace" fails on the 18.3 simulator (cannot move to Trash), so keep both.
        let replace = app.buttons.matching(NSPredicate(format: "label IN %@", ["Keep Both", "両方とも残す"])).firstMatch
        if replace.waitForExistence(timeout: 3) { probe("replace prompt shown"); replace.tap() }
        if !app.staticTexts.matching(NSPredicate(format: "label CONTAINS '[shareFile] completed='")).firstMatch.waitForExistence(timeout: 3) {
            dump(app, "afterSave")
        }
        waitResult(contains: "[shareFile] completed=", timeout: 15)
    }
}

// MARK: - 7. Clipboard paste permission / UIPasteControl

final class Stage0aClipboardProbeTests: Stage0aProbeBase {

    override func setUpWithError() throws {
        try super.setUpWithError()
        launchFresh()
        let card = app.buttons["menu.clipboard"]
        XCTAssertTrue(card.waitForExistence(timeout: 10))
        card.tap()
    }

    private func clipboardResult() -> String {
        app.staticTexts["clipboard.result"].label
    }

    private func tapClipboard(_ marker: String) {
        let button = app.buttons["clipboard.button.\(marker)"]
        if !(button.exists && button.isHittable) { scrollTo(button, maxSwipes: 40) }
        button.tap()
    }

    /// Writes the general pasteboard from the test runner (another app), then reads in the app.
    func testC1_allowPasteAlert() {
        UIPasteboard.general.string = "from-runner-\(Int(Date().timeIntervalSince1970))"
        tapClipboard("useGeneral")
        tapClipboard("loadText")
        var alertSource = "none"
        let start = Date()
        var allow: XCUIElement?
        while Date().timeIntervalSince(start) < 8 {
            if app.alerts.firstMatch.exists { alertSource = "app"; allow = app.alerts.firstMatch.buttons["Allow Paste"]; break }
            if springboard.alerts.firstMatch.exists { alertSource = "springboard"; allow = springboard.alerts.firstMatch.buttons["Allow Paste"]; break }
            usleep(300_000)
        }
        probe("paste alert source=\(alertSource)")
        if alertSource == "app" {
            probe("alert label=\(app.alerts.firstMatch.label) buttons=\(app.alerts.firstMatch.buttons.allElementsBoundByIndex.map(\.label))")
        } else if alertSource == "springboard" {
            probe("alert label=\(springboard.alerts.firstMatch.label) buttons=\(springboard.alerts.firstMatch.buttons.allElementsBoundByIndex.map(\.label))")
        } else {
            dump(app, "noPasteAlertApp")
        }
        if alertSource != "none" {
            let container = alertSource == "app" ? app.alerts.firstMatch : springboard.alerts.firstMatch
            allow = systemButton(container, ["Allow Paste", "ペーストを許可"])
        }
        if let allow, allow.exists {
            allow.tap()
        }
        sleep(2)
        probe("result after allow: \(clipboardResult().replacingOccurrences(of: "\n", with: " "))")
    }

    /// Host writes the pasteboard first (`xcrun simctl pbcopy <udid>`); the app then reads it.
    func testC3_allowPasteAfterHostPbcopy() {
        tapClipboard("useGeneral")
        tapClipboard("loadText")
        let start = Date()
        var source = "none"
        while Date().timeIntervalSince(start) < 8 {
            if app.alerts.firstMatch.exists { source = "app"; break }
            if springboard.alerts.firstMatch.exists { source = "springboard"; break }
            usleep(300_000)
        }
        let alert = source == "app" ? app.alerts.firstMatch : springboard.alerts.firstMatch
        probe("host pbcopy: paste alert source=\(source) label=\(source == "none" ? "-" : alert.label) buttons=\(source == "none" ? [] : alert.buttons.allElementsBoundByIndex.map(\.label))")
        if source != "none" {
            systemButton(alert, ["Allow Paste", "ペーストを許可"]).tap()
        }
        sleep(2)
        probe("result: \(clipboardResult().replacingOccurrences(of: "\n", with: " "))")
    }

    /// Same as C1 but answers "Don't Allow Paste".
    func testC4_dontAllowPaste() {
        UIPasteboard.general.string = "deny-\(Int(Date().timeIntervalSince1970))"
        tapClipboard("useGeneral")
        tapClipboard("loadText")
        let alert = springboard.alerts.firstMatch
        let shown = alert.waitForExistence(timeout: 8)
        probe("paste alert shown=\(shown) label=\(shown ? alert.label : "-") buttons=\(shown ? alert.buttons.allElementsBoundByIndex.map(\.label) : [])")
        XCTAssertTrue(shown)
        systemButton(alert, ["Don’t Allow Paste", "ペーストを許可しない"]).tap()
        sleep(2)
        probe("result after deny: \(clipboardResult().replacingOccurrences(of: "\n", with: " "))")
    }

    func testC2_pasteControlTap() {
        UIPasteboard.general.string = "paste-control-\(Int(Date().timeIntervalSince1970))"
        tapClipboard("mountPasteControl")
        sleep(1)
        let summaryBefore = app.staticTexts["clipboard.pasteSummary"].label
        let paste = app.buttons.matching(NSPredicate(format: "label CONTAINS[c] 'Paste' AND NOT (identifier BEGINSWITH 'clipboard.')")).firstMatch
        let found = paste.waitForExistence(timeout: 5)
        probe("paste control found=\(found) label=\(found ? paste.label : "-") id=\(found ? paste.identifier : "-")")
        if !found { dump(app, "noPasteControl") }
        XCTAssertTrue(found)
        if !paste.isHittable { scrollTo(paste, maxSwipes: 40) }
        paste.tap()
        sleep(2)
        let alertShown = app.alerts.firstMatch.exists || springboard.alerts.firstMatch.exists
        probe("alert after paste control tap: \(alertShown)")
        let summary = app.staticTexts["clipboard.pasteSummary"].label
        probe("pasteSummary before=\(summaryBefore) after=\(summary)")
        XCTAssertNotEqual(summaryBefore, summary)
    }
}

// MARK: - Environment

final class Stage0aEnvProbeTests: XCTestCase {
    func testE1_languages() {
        print("[PROBE] env preferredLanguages=\(Locale.preferredLanguages) current=\(Locale.current.identifier) isDevice=\(Stage0aProbeBase.isDevice)")
    }
}

/// Reads what the sample left on the device (its own delivered / scheduled notifications, permission).
final class Stage0aStateProbeTests: Stage0aProbeBase {
    func testZ_sampleState() {
        launchFresh()
        openMenu("Notification Example")
        tapButton("AuthorizationStatus")
        waitResult(contains: "[authorizationStatus]")
        tapButton("GetDelivered")
        waitResult(contains: "[getDelivered]")
        tapButton("GetScheduled")
        waitResult(contains: "[getScheduled]")
    }
}
