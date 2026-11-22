import XCTest
import Foundation
import UIKit

// Temporary probes for design 8.1 (stage 0c, second half: Notification, Share, Clipboard).
// Simulator only. Removed from the test target after the measurement and kept under
// artifact/topics/ios-c-abi/results/probes/stage0c/.

final class Stage0c2ProbeTests: SampleUITestCase {

    private var sample: SampleApp!
    private let raw = XCUIApplication(bundleIdentifier: "com.jonghyunkim.ios.nativetoolkit.example")
    private let sb = XCUIApplication(bundleIdentifier: "com.apple.springboard")

    private static let systemUIButtons: Set<NotificationButton> = [
        .showImmediate, .showImmediateWithAttachment, .showTimeInterval, .showCalendar, .showLocation,
        .scheduleTimeInterval, .scheduleCalendar, .scheduleLocation, .updateById,
        .requestPermission, .openNotificationSettings
    ]

    override func setUpAfterGate() throws {
        sample = try launchSample()
    }

    private func log(_ s: String) { print("NTKPROBE \(name) \(s.replacingOccurrences(of: "\n", with: " "))") }

    private func dump(_ a: XCUIApplication, _ tag: String) {
        print("NTKPROBE-DUMP-BEGIN \(tag)\n\(a.debugDescription)\nNTKPROBE-DUMP-END \(tag)")
    }

    @discardableResult
    private func tapN(_ b: NotificationButton) throws -> String {
        let before = try sample.updateCount(.notification)
        if Self.systemUIButtons.contains(b) {
            try sample.tap(b, try systemUIToken())
        } else {
            try sample.tap(b)
        }
        try sample.waitForUpdateCount(.notification, before + 1)
        return try sample.resultText(.notification)
    }

    private func lastEvent() throws -> String {
        try ["sequence", "kind", "notificationId", "actionId", "userText"].map { try sample.lastEventLabel($0) }.joined(separator: " ")
    }

    private func openNotificationClean() throws {
        try sample.open(.notification)
        try NotificationCleanup.inApp(sample)
    }

    private func banner(_ title: String) -> XCUIElement {
        sb.descendants(matching: .any).matching(NSPredicate(
            format: "identifier == 'NotificationShortLookView' AND label CONTAINS %@", title)).firstMatch
    }

    // MARK: Notification

    /// Expanded banner of the sample with the category: which element holds Open / Delete / Reply?
    func testQ01_expandedWithCategory() throws {
        try openNotificationClean()
        log(try tapN(.registerCategory))
        log(try tapN(.showTimeInterval))
        let springboard = Springboard(try systemUIToken())
        try springboard.goHome()
        let t0 = Date()
        let shown = try springboard.waitForBanner(title: "5s Notification", body: "Will be shown after 5 seconds", timeout: 20)
        log("banner shown=\(shown) after \(Date().timeIntervalSince(t0))")
        try springboard.longPressBanner(title: "5s Notification", body: "Will be shown after 5 seconds")
        let open = sb.buttons["Open"]
        log("Open appeared=\(open.waitForExistence(timeout: 5))")
        dump(sb, "expanded-with-category")
        for b in sb.buttons.allElementsBoundByIndex where ["Open", "Delete", "Reply"].contains(b.label) {
            log("action button id=\(b.identifier) label=\(b.label) frame=\(b.frame)")
        }
        let shortLook = sb.descendants(matching: .any).matching(identifier: "NotificationShortLookView")
        log("shortLook count=\(shortLook.count)")
        for e in sb.descendants(matching: .any).matching(NSPredicate(format: "identifier CONTAINS[c] 'LongLook' OR identifier CONTAINS[c] 'Expanded' OR identifier CONTAINS[c] 'Platter' OR identifier CONTAINS[c] 'Notification'")).allElementsBoundByIndex {
            log("candidate type=\(e.elementType.rawValue) id=\(e.identifier) label=\(e.label) frame=\(e.frame)")
        }
        try springboard.goHome()
        try sample.activate()
        try NotificationCleanup.inApp(sample)
    }

    /// Expanded banner without the category: what marks "expanded"?
    func testQ02_expandedWithoutCategory() throws {
        try openNotificationClean()
        log(try tapN(.removeCategory))
        log(try tapN(.showTimeInterval))
        let springboard = Springboard(try systemUIToken())
        try springboard.goHome()
        let shown = try springboard.waitForBanner(title: "5s Notification", body: "Will be shown after 5 seconds", timeout: 20)
        log("banner shown=\(shown)")
        try springboard.longPressBanner(title: "5s Notification", body: "Will be shown after 5 seconds")
        Thread.sleep(forTimeInterval: 3)
        log("Open exists=\(sb.buttons["Open"].exists) Delete=\(sb.buttons["Delete"].exists) Reply=\(sb.buttons["Reply"].exists)")
        dump(sb, "expanded-without-category")
        for e in sb.descendants(matching: .any).matching(NSPredicate(format: "identifier CONTAINS[c] 'LongLook' OR identifier CONTAINS[c] 'Expanded' OR identifier CONTAINS[c] 'Platter' OR identifier CONTAINS[c] 'Notification'")).allElementsBoundByIndex {
            log("candidate type=\(e.elementType.rawValue) id=\(e.identifier) label=\(e.label) frame=\(e.frame)")
        }
        try springboard.goHome()
        try sample.activate()
        log(try tapN(.registerCategory))
        try NotificationCleanup.inApp(sample)
    }

    /// N10: ShowImmediate -> UpdateById -> GetDelivered.
    func testQ03_updateDeliveredSameId() throws {
        try openNotificationClean()
        log(try tapN(.showImmediate))
        let springboard = Springboard(try systemUIToken())
        log("first banner=\(try springboard.waitForBanner(title: "Immediate Notification", body: "Displayed now", timeout: 10))")
        log(try tapN(.getDelivered))
        log(try tapN(.updateById))
        log("updated banner=\(try springboard.waitForBanner(title: "Updated Notification", body: "This content was updated", timeout: 10))")
        for i in 0..<4 {
            log("getDelivered[\(i)] \(try tapN(.getDelivered))")
            Thread.sleep(forTimeInterval: 0.5)
        }
        log(try tapN(.getScheduled))
        try NotificationCleanup.inApp(sample)
    }

    /// N5: the bundled attachment twice.
    func testQ04_attachmentTwice() throws {
        try openNotificationClean()
        let springboard = Springboard(try systemUIToken())
        log("1: \(try tapN(.showImmediateWithAttachment))")
        log("1 banner=\(try springboard.waitForBanner(title: "Immediate Notification with Attachment", body: "Displayed with app icon attachment", timeout: 10))")
        log(try tapN(.removeAllDelivered))
        Thread.sleep(forTimeInterval: 1)
        log("2: \(try tapN(.showImmediateWithAttachment))")
        log("2 banner=\(try springboard.waitForBanner(title: "Immediate Notification with Attachment", body: "Displayed with app icon attachment", timeout: 10))")
        log(try tapN(.getDelivered))
        try NotificationCleanup.inApp(sample)
    }

    /// N26: tap the foreground banner.
    func testQ05_foregroundBannerTap() throws {
        try openNotificationClean()
        log("before: \(try lastEvent())")
        log(try tapN(.showImmediate))
        let springboard = Springboard(try systemUIToken())
        log("banner=\(try springboard.waitForBanner(title: "Immediate Notification", body: "Displayed now", timeout: 10))")
        try springboard.tapBanner(title: "Immediate Notification", body: "Displayed now")
        let t0 = Date()
        var event = try lastEvent()
        while !event.contains("sequence=1"), Date().timeIntervalSince(t0) < 10 {
            Thread.sleep(forTimeInterval: 0.3)
            event = try lastEvent()
        }
        log("after tap (\(Date().timeIntervalSince(t0))s) state=\(raw.state.rawValue): \(event)")
        Thread.sleep(forTimeInterval: 2)
        log("after 2s: \(try lastEvent())")
        try NotificationCleanup.inApp(sample)
    }

    /// N32: reply after terminate; does the background process survive until activate?
    func testQ06_coldReply() throws {
        try openNotificationClean()
        log(try tapN(.registerCategory))
        log(try tapN(.showTimeInterval))
        try sample.terminate()
        let springboard = Springboard(try systemUIToken())
        log("banner=\(try springboard.waitForBanner(title: "5s Notification", body: "Will be shown after 5 seconds", timeout: 20))")
        try springboard.expandBanner(title: "5s Notification", body: "Will be shown after 5 seconds")
        try springboard.tapAction("Reply")
        Thread.sleep(forTimeInterval: 1)
        dump(sb, "after-reply-tap")
        try springboard.sendReply("cold reply")
        for i in 0..<6 {
            log("state t+\(i)s=\(raw.state.rawValue)")
            Thread.sleep(forTimeInterval: 1)
        }
        try sample.activate()
        try sample.open(.notification)
        log("event after activate: \(try lastEvent())")
        try NotificationCleanup.inApp(sample)
    }

    /// N33: Delete after terminate.
    func testQ07_coldDelete() throws {
        try openNotificationClean()
        log(try tapN(.registerCategory))
        log(try tapN(.showTimeInterval))
        try sample.terminate()
        let springboard = Springboard(try systemUIToken())
        log("banner=\(try springboard.waitForBanner(title: "5s Notification", body: "Will be shown after 5 seconds", timeout: 20))")
        try springboard.longPressBanner(title: "5s Notification", body: "Will be shown after 5 seconds")
        try springboard.tapAction("Delete")
        for i in 0..<6 {
            log("state t+\(i)s=\(raw.state.rawValue)")
            Thread.sleep(forTimeInterval: 1)
        }
        try sample.activate()
        try sample.open(.notification)
        log("event after activate: \(try lastEvent())")
        try NotificationCleanup.inApp(sample)
    }

    /// N28: Delete while running in the background (not terminated).
    func testQ07b_backgroundDelete() throws {
        try openNotificationClean()
        log(try tapN(.registerCategory))
        log(try tapN(.showTimeInterval))
        let springboard = Springboard(try systemUIToken())
        try springboard.goHome()
        log("banner=\(try springboard.waitForBanner(title: "5s Notification", body: "Will be shown after 5 seconds", timeout: 20))")
        try springboard.longPressBanner(title: "5s Notification", body: "Will be shown after 5 seconds")
        try springboard.tapAction("Delete")
        Thread.sleep(forTimeInterval: 2)
        log("state after Delete+2s=\(raw.state.rawValue)")
        try sample.activate()
        log("event after activate: \(try lastEvent())")
        try NotificationCleanup.inApp(sample)
    }

    /// N3: Settings app foreground.
    func testQ08_settingsForeground() throws {
        try sample.open(.notification)
        let springboard = Springboard(try systemUIToken())
        let t0 = Date()
        log(try tapN(.openNotificationSettings))
        let fg = springboard.waitForSettingsForeground(timeout: 10)
        let settings = XCUIApplication(bundleIdentifier: "com.apple.Preferences")
        log("settings foreground=\(fg) after \(Date().timeIntervalSince(t0))s state=\(settings.state.rawValue) sample=\(raw.state.rawValue)")
        try sample.activate()
        log("sample state after activate=\(raw.state.rawValue) result=\(try sample.resultText(.notification))")
        settings.terminate()
    }

    /// N7: ShowCalendar(+1m) firing time.
    func testQ09_calendarFiring() throws {
        try openNotificationClean()
        let t0 = Date()
        log(try tapN(.showCalendar))
        log(try tapN(.getScheduled))
        let springboard = Springboard(try systemUIToken())
        let shown = try springboard.waitForBanner(title: "Calendar Notification", body: "Will be shown in one minute", timeout: 100)
        log("calendar banner=\(shown) after \(Date().timeIntervalSince(t0))s")
        try NotificationCleanup.inApp(sample)
    }

    /// N34: reading the home icon badge.
    func testQ10_badge() throws {
        try sample.open(.notification)
        log(try tapN(.setBadgeCount1))
        let springboard = Springboard(try systemUIToken())
        try springboard.goHome()
        Thread.sleep(forTimeInterval: 1)
        let icons = sb.icons.matching(identifier: "IosLibraryExample")
        log("icons count=\(icons.count)")
        for icon in icons.allElementsBoundByIndex {
            log("icon id=\(icon.identifier) label=\(icon.label) value=\(String(describing: icon.value)) hittable=\(icon.isHittable) frame=\(icon.frame)")
        }
        let byLabel = sb.icons.matching(NSPredicate(format: "label BEGINSWITH 'IosLibraryExample'"))
        for icon in byLabel.allElementsBoundByIndex {
            log("icon(label) id=\(icon.identifier) label=\(icon.label) value=\(String(describing: icon.value))")
        }
        try sample.activate()
        log(try tapN(.setBadgeCount0))
        try springboard.goHome()
        Thread.sleep(forTimeInterval: 1)
        for icon in sb.icons.matching(identifier: "IosLibraryExample").allElementsBoundByIndex {
            log("icon after 0: label=\(icon.label) value=\(String(describing: icon.value))")
        }
        try sample.activate()
    }

    /// N8 / N18: location registration result.
    func testQ11_location() throws {
        try openNotificationClean()
        log(try tapN(.showLocation))
        log(try tapN(.getScheduled))
        log(try tapN(.scheduleLocation))
        log(try tapN(.getScheduled))
        try NotificationCleanup.inApp(sample)
    }

    /// N23 / N24: category Task timing, 3 rounds.
    func testQ12_categoryTiming() throws {
        try openNotificationClean()
        let springboard = Springboard(try systemUIToken())
        for round in 1...3 {
            log("r\(round) \(try tapN(.removeCategory))")
            log(try tapN(.showTimeInterval))
            try springboard.goHome()
            _ = try springboard.waitForBanner(title: "5s Notification", body: "Will be shown after 5 seconds", timeout: 20)
            try springboard.expandBanner(title: "5s Notification", body: "Will be shown after 5 seconds")
            Thread.sleep(forTimeInterval: 3)
            log("r\(round) removed: actions=\(springboard.actionCount(["Open", "Delete", "Reply"])) expanded=\(springboard.isExpanded)")
            try springboard.goHome()
            try sample.activate()
            try NotificationCleanup.inApp(sample)
            log("r\(round) \(try tapN(.registerCategory))")
            log(try tapN(.showTimeInterval))
            try springboard.goHome()
            _ = try springboard.waitForBanner(title: "5s Notification", body: "Will be shown after 5 seconds", timeout: 20)
            try springboard.expandBanner(title: "5s Notification", body: "Will be shown after 5 seconds")
            let t0 = Date()
            let open = sb.buttons["Open"].waitForExistence(timeout: 5)
            log("r\(round) registered: actions=\(springboard.actionCount(["Open", "Delete", "Reply"]))")
            log("r\(round) registered: Open=\(open) after \(Date().timeIntervalSince(t0))s")
            try springboard.goHome()
            try sample.activate()
            try NotificationCleanup.inApp(sample)
        }
    }

    // MARK: Share

    private func tapShare(_ b: ShareButton) throws {
        try sample.tap(b, try shareSheetToken())
    }

    /// S5: preview title as an element.
    func testQ13_sharePreviewTitle() throws {
        try sample.open(.share)
        let sheet = ShareSheet(try shareSheetToken())
        let before = try sample.updateCount(.share)
        try tapShare(.shareURLWithPreview)
        let t0 = Date()
        log("sheet open=\(try sheet.waitOpen()) after \(Date().timeIntervalSince(t0))s")
        log("header titles in 2s: \(sheet.observeHeaderTitle(for: 2))")
        let apple = raw.staticTexts.matching(identifier: "Apple")
        log("Apple texts (immediately)=\(apple.count)")
        for e in raw.descendants(matching: .any).matching(NSPredicate(format: "label == 'Apple' OR label CONTAINS 'apple.com'")).allElementsBoundByIndex {
            log("element type=\(e.elementType.rawValue) id=\(e.identifier) label=\(e.label) at \(Date().timeIntervalSince(t0))s")
        }
        dump(raw, "share-preview")
        Thread.sleep(forTimeInterval: 2)
        for e in raw.descendants(matching: .any).matching(NSPredicate(format: "label == 'Apple' OR label CONTAINS 'apple.com'")).allElementsBoundByIndex {
            log("element+2s type=\(e.elementType.rawValue) id=\(e.identifier) label=\(e.label)")
        }
        try sheet.close()
        try sample.waitForUpdateCount(.share, before + 1)
        log(try sample.resultText(.share))
    }

    private func shareCopy(_ b: ShareButton) throws {
        try sample.open(.share)
        let sheet = ShareSheet(try shareSheetToken())
        let before = try sample.updateCount(.share)
        try tapShare(b)
        log("sheet open=\(try sheet.waitOpen()) copyCount(now)=\(sheet.copyCount)")
        log("copy appeared=\(try sheet.waitForCopy()) count=\(sheet.copyCount)")
        if sheet.copyCount == 1 {
            try sheet.copy(try clipboardToken())
            try sample.waitForUpdateCount(.share, before + 1, timeout: 15)
        } else {
            dump(raw, "share-copy-\(b.rawValue)")
            try sheet.close()
        }
        log(try sample.resultText(.share))
        log("pasteboard types=\(UIPasteboard.general.types) items=\(UIPasteboard.general.numberOfItems)")
    }

    func testQ14_shareImageCopy() throws { try shareCopy(.shareImage) }
    func testQ15_shareMultipleCopy() throws { try shareCopy(.shareMultiple) }
    func testQ16_shareMultipleImagesCopy() throws { try shareCopy(.shareMultipleImages) }

    private func shareSave(_ b: ShareButton) throws {
        try sample.open(.share)
        let sheet = ShareSheet(try shareSheetToken())
        let before = try sample.updateCount(.share)
        try tapShare(b)
        log("sheet open=\(try sheet.waitOpen())")
        let t0 = Date()
        try sheet.saveToFiles(try filesToken()) { try sample.updateCount(.share) > before }
        Thread.sleep(forTimeInterval: 3)
        if try sample.updateCount(.share) == before {
            dump(raw, "after-save-\(b.rawValue)")
            for e in raw.buttons.allElementsBoundByIndex where !e.identifier.hasPrefix("share.") { log("button id=\(e.identifier) label=\(e.label) enabled=\(e.isEnabled)") }
        }
        try sample.waitForUpdateCount(.share, before + 1, timeout: 15)
        log("result after \(Date().timeIntervalSince(t0))s: \(try sample.resultText(.share))")
    }

    func testQ17_shareFileSave() throws { try shareSave(.shareFile) }
    func testQ18_shareMultipleFilesSave() throws { try shareSave(.shareMultipleFiles) }

    // MARK: Clipboard

    private func rawTap(_ id: String) {
        let b = raw.buttons[id]
        for down in [true, false] {
            var n = 0
            while !(b.exists && b.isHittable) && n < 40 {
                let s: CGFloat = down ? 0.8 : 0.5, e: CGFloat = down ? 0.5 : 0.8
                raw.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: s)).press(forDuration: 0.1, thenDragTo: raw.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: e)))
                n += 1
            }
            if b.isHittable { break }
        }
        b.tap()
    }

    private var clipResult: String { raw.staticTexts["clipboard.result"].label }

    private func loadAndAnswer(_ tag: String, answer: [String]?) {
        let before = clipResult
        rawTap("clipboard.button.loadText")
        let alert = sb.alerts.firstMatch
        let t0 = Date()
        let shown = alert.waitForExistence(timeout: 5)
        log("\(tag): alert shown=\(shown) after \(Date().timeIntervalSince(t0))s label=\(shown ? alert.label : "-")")
        if shown, let answer {
            alert.buttons.matching(NSPredicate(format: "label IN %@", answer)).firstMatch.tap()
        }
        let t1 = Date()
        while clipResult == before && Date().timeIntervalSince(t1) < 5 { Thread.sleep(forTimeInterval: 0.2) }
        log("\(tag): result=\(clipResult)")
    }

    /// CB2: when does the paste alert appear again?
    func testQ19_pasteAlertConditions() throws {
        let clip = try clipboardToken()
        let pb = RunnerPasteboard(clip)
        log("cc0=\(pb.write("ntk-q19-a-\(Date().timeIntervalSince1970)"))")
        try sample.openClipboard(clip)
        rawTap("clipboard.button.useGeneral")
        loadAndAnswer("fresh A, allow", answer: SystemLabels.allowPaste)
        loadAndAnswer("same A again", answer: SystemLabels.allowPaste)
        log("cc1=\(pb.write("ntk-q19-b-\(Date().timeIntervalSince1970)"))")
        loadAndAnswer("fresh B, deny", answer: SystemLabels.dontAllowPaste)
        loadAndAnswer("same B again", answer: SystemLabels.dontAllowPaste)
        try sample.terminate()
        try sample.launch()
        try sample.openClipboard(clip)
        rawTap("clipboard.button.useGeneral")
        loadAndAnswer("B after relaunch", answer: SystemLabels.dontAllowPaste)
        log("cc2=\(pb.write("ntk-q19-c-\(Date().timeIntervalSince1970)"))")
        loadAndAnswer("fresh C after relaunch, deny", answer: SystemLabels.dontAllowPaste)
    }

    /// CB2 alone in a separate xcodebuild after Q19.
    func testQ20_pasteDenyFresh() throws {
        let clip = try clipboardToken()
        let pb = RunnerPasteboard(clip)
        log("cc=\(pb.write("ntk-q20-\(Date().timeIntervalSince1970)"))")
        try sample.openClipboard(clip)
        rawTap("clipboard.button.useGeneral")
        loadAndAnswer("fresh, deny", answer: SystemLabels.dontAllowPaste)
    }

    /// CB4: image-only paste through the paste control.
    func testQ21_imageOnlyPaste() throws {
        let clip = try clipboardToken()
        let pb = RunnerPasteboard(clip)
        let cc = pb.writeImageOnly()
        log("cc=\(cc) types=\(UIPasteboard.general.types)")
        try sample.openClipboard(clip)
        rawTap("clipboard.button.mountPasteControl")
        let control = raw.buttons["clipboard.pasteControl"]
        log("control exists=\(control.waitForExistence(timeout: 5)) enabled=\(control.isEnabled) label=\(control.label) type=\(control.elementType.rawValue)")
        let others = raw.descendants(matching: .any).matching(identifier: "clipboard.pasteControl")
        log("pasteControl any-type count=\(others.count)")
        let summary = raw.staticTexts["clipboard.pasteSummary"]
        log("summary before=\(summary.label)")
        try pb.requireUnchanged(since: cc)
        if !control.isHittable { rawTap("clipboard.pasteControl") } else { control.tap() }
        let t0 = Date()
        while summary.label == "Paste result: -" && Date().timeIntervalSince(t0) < 5 { Thread.sleep(forTimeInterval: 0.2) }
        log("summary after \(Date().timeIntervalSince(t0))s=\(summary.label) sbAlerts=\(sb.alerts.count) appAlerts=\(raw.alerts.count)")
    }

    /// CB3: text through the paste control.
    func testQ22_textPasteControl() throws {
        let clip = try clipboardToken()
        let pb = RunnerPasteboard(clip)
        let cc = pb.write("ntk-q22-\(Date().timeIntervalSince1970)")
        try sample.openClipboard(clip)
        rawTap("clipboard.button.mountPasteControl")
        let control = raw.buttons["clipboard.pasteControl"]
        log("control exists=\(control.waitForExistence(timeout: 5)) enabled=\(control.isEnabled) hittable=\(control.isHittable)")
        try pb.requireUnchanged(since: cc)
        if !control.isHittable { rawTap("clipboard.pasteControl") } else { control.tap() }
        let summary = raw.staticTexts["clipboard.pasteSummary"]
        let t0 = Date()
        while summary.label == "Paste result: -" && Date().timeIntervalSince(t0) < 5 { Thread.sleep(forTimeInterval: 0.2) }
        log("summary after \(Date().timeIntervalSince(t0))s=\(summary.label) sbAlerts=\(sb.alerts.count)")
    }

    /// After home + activate: element frames and hittability over time.
    func testQ23_activateFrames() throws {
        try sample.open(.notification)
        log(try tapN(.registerCategory))
        let springboard = Springboard(try systemUIToken())
        try springboard.goHome()
        Thread.sleep(forTimeInterval: 1)
        try sample.activate()
        for i in 0..<8 {
            let b = raw.buttons["notification.button.removeAllDelivered"]
            let c = raw.buttons["notification.button.setBadgeCount0"]
            let r = raw.staticTexts["notification.result"]
            log("t\(i): removeAll frame=\(b.frame) setBadge0 frame=\(c.frame) result frame=\(r.frame) sv=\(raw.scrollViews.count) svframe=\(raw.scrollViews.firstMatch.frame) win=\(raw.windows.firstMatch.frame)")
            Thread.sleep(forTimeInterval: 0.5)
        }
        let before = try sample.updateCount(.notification)
        try sample.tap(.setBadgeCount0)
        Thread.sleep(forTimeInterval: 2)
        log("after tap setBadge0: updates \(before) -> \(try sample.updateCount(.notification)) \(try sample.resultText(.notification))")
        log(try tapN(.removeAllDelivered))
    }
}
