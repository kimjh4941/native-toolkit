import XCTest
import Foundation

// Temporary probes for design 8.1 (stage 0c). Removed after the measurement.

final class Stage0cProbeTests: SampleUITestCase {

    private var sample: SampleApp!

    override func setUpAfterGate() throws {
        sample = try launchSample()
    }

    private func log(_ s: String) { print("NTKPROBE \(name) \(s)") }

    /// In-app UIAlertController blocks a tap on a button behind it: is the monitor invoked, and
    /// does terminate + true + the wrapper's throw stop the test?
    func testP1_inAppAlertBlocksTap() throws {
        try sample.open(.dialog)
        try sample.tap(.showAlert)
        try sample.alert("Hello from iOS").waitShown()
        log("alert shown; tapping a button behind it")
        try sample.tap(.showConfirmDialog)
        log("UNEXPECTED: tap behind the alert returned without throwing")
    }

    /// Foreground banner over the app: does tapping an element under the banner invoke the monitor?
    func testP2_bannerOverApp() throws {
        try sample.open(.notification)
        let token = try systemUIToken()
        try sample.tap(.authorizationStatus)
        log("auth: \(try sample.resultText(.notification))")
        let before = try sample.updateCount(.notification)
        try sample.tap(.showImmediate, token)
        try sample.waitForUpdateCount(.notification, before + 1)
        let sb = Springboard(token)
        let shown = try sb.waitForBanner(title: "Immediate Notification", body: "Displayed now", timeout: 10)
        log("banner shown=\(shown)")
        let raw = XCUIApplication(bundleIdentifier: "com.jonghyunkim.ios.nativetoolkit.example")
        let result = raw.staticTexts["notification.result"]
        log("result frame=\(result.frame) hittable=\(result.isHittable)")
        let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")
        let banner = springboard.descendants(matching: .any).matching(identifier: "NotificationShortLookView").firstMatch
        log("banner frame=\(banner.frame) type=\(banner.elementType.rawValue) label=\(banner.label)")
        // Tap the title text which lies under the banner.
        let title = raw.staticTexts["IosNotificationManager Example"]
        log("title frame=\(title.frame) hittable=\(title.isHittable)")
        title.tap()
        log("tapped title; app state=\(raw.state.rawValue) banner exists=\(banner.exists)")
        try sample.tap(.getDelivered)
        log("after getDelivered: \(try sample.resultText(.notification))")
        try sample.tap(.removeAllDelivered)
    }

    /// Navigation bar content and offscreen buttons in one snapshot.
    func testP3_snapshotShape() throws {
        for screen in [SampleScreen.dialog, .notification, .share] {
            try sample.open(screen)
            let snap = try sample.inventorySnapshot(screen)
            log("\(screen) buttons=\(snap.buttons.count) back=\(snap.navigationBarButtons) nonButtons=\(snap.identifiedNonButtons.count)")
            let raw = XCUIApplication(bundleIdentifier: "com.jonghyunkim.ios.nativetoolkit.example")
            for b in raw.navigationBars.buttons.allElementsBoundByIndex {
                log("\(screen) navbar button id=\(b.identifier) label=\(b.label)")
            }
            let window = raw.windows.firstMatch.frame
            let offscreen = snap.buttons.filter { !$0.frame.intersects(window) || $0.frame.maxY > window.maxY }
            log("\(screen) window=\(window) offscreen-or-partly=\(offscreen.map(\.identifier))")
            try sample.goBackToMenu()
        }
    }

    /// The action sheet on iOS 26.2: element types.
    func testP4_actionSheetShape() throws {
        try sample.open(.dialog)
        try sample.tap(.showActionSheet)
        try sample.actionSheet().waitShown(option: "Camera")
        let raw = XCUIApplication(bundleIdentifier: "com.jonghyunkim.ios.nativetoolkit.example")
        log("sheets=\(raw.sheets.count) alerts=\(raw.alerts.count) popovers=\(raw.popovers.count)")
        log("cancel count=\(raw.buttons.matching(identifier: "Cancel").count)")
        for t in raw.staticTexts.allElementsBoundByIndex { log("text id=\(t.identifier) label=\(t.label)") }
        log("result label=\(String(reflecting: try sample.resultText(.dialog))) value=\(try sample.resultValue(.dialog))")
        try sample.actionSheet().tapPopoverDismissRegion()
    }
    /// In-app alert + raw tap on a button behind it (the monitor gets an in-app alert without the
    /// sample's name -> terminate path).
    func testP5_inAppAlertRawTap() throws {
        try sample.open(.dialog)
        try sample.tap(.showAlert)
        try sample.alert("Hello from iOS").waitShown()
        let raw = XCUIApplication(bundleIdentifier: "com.jonghyunkim.ios.nativetoolkit.example")
        log("raw tap behind the alert")
        raw.buttons["dialog.button.showConfirmDialog"].tap()
        log("after raw tap: state=\(raw.state.rawValue)")
        try sample.alert("Hello from iOS").waitShown()
        log("UNEXPECTED: continued")
    }

    /// Control: a plain XCTest failure (tap on a missing element) with continueAfterFailure=false.
    func testP7_plainFailure() throws {
        try sample.open(.dialog)
        let raw = XCUIApplication(bundleIdentifier: "com.jonghyunkim.ios.nativetoolkit.example")
        log("tapping a missing element")
        raw.buttons["no-such-button"].tap()
        log("UNEXPECTED: continued")
    }

    /// Control: our wrapper throws (no XCTest-internal failure).
    func testP8_wrapperThrow() throws {
        try sample.open(.dialog)
        log("throwing from the wrapper")
        try sample.alert("Never").waitShown(timeout: 1)
        log("UNEXPECTED: continued")
    }
}


final class NotificationPermissionUITests: SampleUITestCase {

    private var sample: SampleApp!

    override func setUpAfterGate() throws {
        sample = try launchSample()
        try sample.open(.notification)
    }

    private func log(_ s: String) { print("NTKPROBE \(name) \(s)") }

    /// Press-nothing monitor + explicit springboard press: does the monitor stay silent?
    func testProbeA_explicitAllow() throws {
        let token = try systemUIToken()
        try sample.tap(.authorizationStatus)
        log("auth before: \(try sample.resultText(.notification))")
        let before = try sample.updateCount(.notification)
        try sample.tap(.requestPermission, token)
        let sb = Springboard(token)
        log("alert appeared=\(sb.waitForAlert())")
        let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")
        let alert = springboard.alerts.firstMatch
        log("alert label=\(alert.label) buttons=\(alert.buttons.allElementsBoundByIndex.map(\.label))")
        log("alert names sample=\(try sb.alertNamesSample())")
        try sb.tapAlertButton(SystemLabels.allow)
        try sample.waitForUpdateCount(.notification, before + 1)
        log("after allow: \(try sample.resultText(.notification))")
        try sample.tap(.authorizationStatus)
        log("auth after: \(try sample.resultText(.notification))")
    }
}

final class Stage0cMonitorDenyProbeTests: SampleUITestCase {

    private var sample: SampleApp!

    override func setUpAfterGate() throws {
        sample = try launchSample()
        try sample.open(.notification)
    }

    private func log(_ s: String) { print("NTKPROBE \(name) \(s)") }

    /// Standard monitor (systemui declared): permission alert left unanswered, then the test taps
    /// an app button. Expect: monitor presses Don't Allow, marks, wrapper throws.
    func testProbeB_monitorDeniesSampleAlert() throws {
        let token = try systemUIToken()
        try sample.tap(.requestPermission, token)
        let sb = Springboard(token)
        log("alert appeared=\(sb.waitForAlert())")
        log("tapping hasPermission behind the alert")
        try sample.tap(.hasPermission)
        log("UNEXPECTED: no throw; result=\(try sample.resultText(.notification))")
    }
}

final class Stage0cPasteProbeTests: SampleUITestCase {

    private var sample: SampleApp!

    override func setUpAfterGate() throws {
        sample = try launchSample()
    }

    private func log(_ s: String) { print("NTKPROBE \(name) \(s)") }

    /// Paste alert label: does it contain the sample's display name (en)?
    func testProbeC_pasteAlertLabel() throws {
        let clip = try clipboardToken()
        let sbToken = try systemUIToken()
        _ = RunnerPasteboard(clip).write("ntk-probe-\(Int(Date().timeIntervalSince1970))")
        try sample.openClipboard(clip)
        let raw = XCUIApplication(bundleIdentifier: "com.jonghyunkim.ios.nativetoolkit.example")
        let load = raw.buttons["clipboard.button.loadText"]
        var n = 0
        while !load.isHittable && n < 20 {
            raw.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.8)).press(forDuration: 0.1, thenDragTo: raw.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)))
            n += 1
        }
        load.tap()
        let sb = Springboard(sbToken)
        let appeared = sb.waitForAlert()
        log("paste alert appeared(springboard)=\(appeared) appAlerts=\(raw.alerts.count)")
        let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")
        if appeared {
            let alert = springboard.alerts.firstMatch
            log("paste alert label=\(alert.label) buttons=\(alert.buttons.allElementsBoundByIndex.map(\.label))")
            try sb.tapAlertButton(SystemLabels.allowPaste)
        } else if raw.alerts.count > 0 {
            let alert = raw.alerts.firstMatch
            log("paste alert (app) label=\(alert.label) buttons=\(alert.buttons.allElementsBoundByIndex.map(\.label))")
            alert.buttons["Allow Paste"].tap()
        }
        Thread.sleep(forTimeInterval: 2)
        log("result=\(raw.staticTexts["clipboard.result"].label)")
    }
}
