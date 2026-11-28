//
//  SupportRuleTests.swift
//  MacLibraryExampleUITests
//
//  Checks the pure rules of the Support files without launching anything (`common.md`: a rule that
//  decides is cut out as a pure function and broken directly). The overlay rule (design 5.0), the
//  result rule (U-3), the gate's host and allowance (U-9), the test key, the declaration table and
//  the fixture path (U-11), and the Notification rules (5.0 for Notification Center, U-6, U-14 (c),
//  4.3).
//

import XCTest
import Foundation

final class SupportRuleTests: SampleUITestCase {

    // MARK: - Overlay rule (5.0)

    private static let display = CGRect(x: 0, y: 0, width: 1024, height: 768)
    private static let samplePID: Int32 = 100
    private static let button = CGRect(x: 100, y: 300, width: 200, height: 40)
    private static var point: CGPoint { CGPoint(x: button.midX, y: button.midY) }

    private static func window(_ pid: Int32, _ owner: String?, layer: Int = 0, alpha: Double = 1,
                               _ bounds: CGRect) -> ScreenWindow {
        ScreenWindow(pid: pid, owner: owner, layer: layer, alpha: alpha, bounds: bounds)
    }

    private static let sampleWindow = window(samplePID, SystemLabels.sampleBundleIdentifier,
                                             CGRect(x: 50, y: 80, width: 900, height: 600))

    /// The full-display windows in front of every app on the 15.8.3 VM (stage 0c).
    private static let passiveFront: [ScreenWindow] = [
        window(10, "com.apple.dt.AutomationModeUI", layer: 1000, display),
        window(11, SystemLabels.notificationCenterBundleIdentifier, layer: 23, display),
        window(12, "com.apple.dock", layer: 20, display)
    ]

    private func verdict(_ windows: [ScreenWindow], allowed: Set<Int32> = [samplePID]) -> OverlayVerdict {
        OverlayRule.verdict(point: Self.point, elementFrame: Self.button, windows: windows,
                            displays: [Self.display], allowedPIDs: allowed)
    }

    func testOverlayPassesTheFullDisplayWindowsOfTheFixedOwners() {
        XCTAssertEqual(verdict(Self.passiveFront + [Self.sampleWindow]), .clear)
    }

    func testOverlayStopsAtAFullDisplayWindowOfAnotherOwner() {
        // The same shape from an owner outside the fixed list, or with no bundle id, blocks.
        XCTAssertEqual(verdict([Self.window(20, "com.example.other", layer: 23, Self.display), Self.sampleWindow]), .blocked)
        XCTAssertEqual(verdict([Self.window(21, nil, layer: 23, Self.display), Self.sampleWindow]), .blocked)
    }

    func testOverlayStopsAtAFixedOwnerWindowSmallerThanTheDisplay() {
        // A banner of Notification Center over the point.
        let banner = Self.window(11, SystemLabels.notificationCenterBundleIdentifier, layer: 23,
                                 CGRect(x: 80, y: 280, width: 400, height: 90))
        XCTAssertEqual(verdict(Self.passiveFront + [banner, Self.sampleWindow]), .notificationCenter)
        // The Dock's own window in front of the point.
        let dock = Self.window(12, "com.apple.dock", layer: 20, CGRect(x: 0, y: 250, width: 1024, height: 120))
        XCTAssertEqual(verdict([dock, Self.sampleWindow]), .blocked)
    }

    func testOverlayStopsAtANotificationWindowOverlappingTheElementButNotThePoint() {
        let banner = Self.window(11, SystemLabels.notificationCenterBundleIdentifier, layer: 23,
                                 CGRect(x: 90, y: 290, width: 20, height: 20))
        XCTAssertFalse(banner.bounds.contains(Self.point))
        XCTAssertEqual(verdict([banner, Self.sampleWindow]), .notificationCenter)
        // Behind the sample's window it does not matter.
        XCTAssertEqual(verdict([Self.sampleWindow, banner]), .clear)
    }

    func testOverlayStopsAtAnotherAppsWindow() {
        let other = Self.window(30, "com.example.other", CGRect(x: 150, y: 310, width: 100, height: 100))
        XCTAssertEqual(verdict([other, Self.sampleWindow]), .blocked)
        // Not over the point and not Notification Center: the sample takes the click.
        let aside = Self.window(30, "com.example.other", CGRect(x: 600, y: 310, width: 100, height: 100))
        XCTAssertEqual(verdict([aside, Self.sampleWindow]), .clear)
    }

    func testOverlayPassesTransparentAndCursorWindows() {
        let transparent = Self.window(30, "com.example.other", alpha: 0, Self.button)
        let cursor = Self.window(31, nil, layer: OverlayRule.cursorLayer, Self.button)
        XCTAssertEqual(verdict([transparent, cursor, Self.sampleWindow]), .clear)
        let almostCursor = Self.window(31, nil, layer: OverlayRule.cursorLayer - 1, Self.button)
        XCTAssertEqual(verdict([almostCursor, Self.sampleWindow]), .blocked)
    }

    func testOverlayAllowsOnlyTheGivenOwners() {
        let panel = Self.window(40, SystemLabels.openAndSavePanelServiceBundleIdentifier, layer: 8, Self.button)
        XCTAssertEqual(verdict([panel, Self.sampleWindow]), .blocked)
        XCTAssertEqual(verdict([panel, Self.sampleWindow], allowed: [Self.samplePID, 40]), .clear)
        XCTAssertEqual(verdict(Self.passiveFront), .noWindow)
    }

    // MARK: - Result rule (U-3)

    func testResultLineParsesOnlyTheNumberedShape() {
        XCTAssertEqual(ResultLine.parse("#12 ✅ \nResult: x"), ShownResult(sequence: 12, text: "✅ \nResult: x"))
        XCTAssertEqual(ResultLine.parse("#0 Result will be displayed here"), ShownResult(sequence: 0, text: ResultLine.initial))
        XCTAssertNil(ResultLine.parse("12 x"))
        XCTAssertNil(ResultLine.parse("#x y"))
        XCTAssertNil(ResultLine.parse("#-1 y"))
        XCTAssertNil(ResultLine.parse("# y"))
        XCTAssertNil(ResultLine.parse("#3"))
    }

    func testResultRuleAcceptsOnlyTheNextResultOfTheOperation() {
        let marker = ShareButton.shareText.resultMarker
        let mine = ResultLine.expected(success: true, "[shareText] completed=false (cancelled)")
        XCTAssertEqual(ResultLine.judge(ShownResult(sequence: 7, text: mine), before: 7, marker: marker), .pending)
        XCTAssertEqual(ResultLine.judge(ShownResult(sequence: 8, text: mine), before: 7, marker: marker), .accepted)
        XCTAssertEqual(ResultLine.judge(ShownResult(sequence: 9, text: mine), before: 7, marker: marker), .overtaken)
        let failure = ResultLine.expected(success: false, "[shareText] errorCode=1, errorMessage=x")
        XCTAssertEqual(ResultLine.judge(ShownResult(sequence: 8, text: failure), before: 7, marker: marker), .accepted)
        // The marker only counts right after `Result: `, not as a word of the detail.
        let detail = ResultLine.expected(success: true, "[shareURL] note [shareText] x")
        XCTAssertEqual(ResultLine.judge(ShownResult(sequence: 8, text: detail), before: 7, marker: marker), .foreign)
    }

    /// The pairs come from the sample's own names: a longer name never stands in for a shorter one
    /// whose name it starts with (`shareText` / `shareTextAndURL`, `ShowFileDialog` / ...).
    func testResultRuleDoesNotLetALongerNameStandInForAShorterOne() {
        // (name, marker, a result of that name) for every button of the three screens.
        let shares = ShareButton.allCases.map { ($0.label, $0.resultMarker, "[\($0.label)] done") }
        let dialogs = DialogButton.allCases.map { ($0.rawValue, $0.resultMarker, "\($0.rawValue) - result: done") }
        let notifications = NotificationButton.allCases.map { button -> (String, String, String) in
            let name = String(button.resultMarker.dropFirst().dropLast(2))
            return (name, button.resultMarker, "[\(name)] done")
        }
        var pairs = 0
        for group in [shares, dialogs, notifications] {
            for (name, marker, _) in group {
                for (otherName, _, otherBody) in group where otherName != name && otherName.hasPrefix(name) {
                    pairs += 1
                    let shown = ShownResult(sequence: 1, text: ResultLine.expected(success: true, otherBody))
                    XCTAssertEqual(ResultLine.judge(shown, before: 0, marker: marker), .foreign,
                                   "\(otherName) stood in for \(name)")
                }
            }
        }
        XCTAssertGreaterThan(pairs, 0, "no name starts with another; the case is untested")
    }

    /// The new Clipboard tests' rule (CB1〜CB6): the next result only, the label anchored right after
    /// the mark. The pairs come from the 36 button names of the inventory.
    func testClipboardResultRuleAcceptsOnlyTheNextResultOfTheLabel() {
        let mine = ClipboardWaitRule.expected(success: true, label: "read", "items=1")
        XCTAssertEqual(ClipboardWaitRule.judge(ShownResult(sequence: 7, text: mine), before: 7, label: "read"), .pending)
        XCTAssertEqual(ClipboardWaitRule.judge(ShownResult(sequence: 8, text: mine), before: 7, label: "read"), .accepted)
        XCTAssertEqual(ClipboardWaitRule.judge(ShownResult(sequence: 9, text: mine), before: 7, label: "read"), .overtaken)
        let failure = ClipboardWaitRule.expected(success: false, label: "read", "errorCode=1514, errorMessage=x")
        XCTAssertEqual(ClipboardWaitRule.judge(ShownResult(sequence: 8, text: failure), before: 7, label: "read"), .accepted)
        // A label in the detail of another operation's result is not this operation's result.
        let detail = ClipboardWaitRule.expected(success: true, label: "snapshot", "note [read] x")
        XCTAssertEqual(ClipboardWaitRule.judge(ShownResult(sequence: 8, text: detail), before: 7, label: "read"), .foreign)
        // The other screens' shape (`Result: `) is not the Clipboard screen's.
        let other = ResultLine.expected(success: true, "[read] items=1")
        XCTAssertEqual(ClipboardWaitRule.judge(ShownResult(sequence: 8, text: other), before: 7, label: "read"), .foreign)

        let labels = SampleInventory.clipboardButtonNames.map(ClipboardWaitRule.label(forButtonNamed:))
        var pairs = 0
        for short in labels {
            for long in labels where long != short && long.hasPrefix(short) {
                pairs += 1
                let shown = ShownResult(sequence: 1, text: ClipboardWaitRule.expected(success: true, label: long, "done"))
                XCTAssertEqual(ClipboardWaitRule.judge(shown, before: 0, label: short), .foreign, "\(long) stood in for \(short)")
            }
        }
        XCTAssertGreaterThan(pairs, 0, "no label starts with another; the case is untested")
    }

    // MARK: - Gate (U-9)

    func testHostIsTheVMOnlyByFact() throws {
        XCTAssertEqual(try TestHost.resolve(environment: ["NTK_HOST": "vm"], hypervisorPresent: { 1 }), .vm)
        XCTAssertThrowsError(try TestHost.resolve(environment: ["NTK_HOST": "vm"], hypervisorPresent: { 0 }))
        XCTAssertThrowsError(try TestHost.resolve(environment: ["NTK_HOST": "vm"], hypervisorPresent: { nil }))
        XCTAssertEqual(try TestHost.resolve(environment: ["NTK_HOST": "VM"], hypervisorPresent: { 1 }), .mac)
        XCTAssertEqual(try TestHost.resolve(environment: [:], hypervisorPresent: { 1 }), .mac)
    }

    func testAllowanceRefusesUnknownAndVMOnlyCategoriesOnThisMac() throws {
        XCTAssertEqual(try SampleUITestCase.allowance(raw: "", host: .mac), [])
        XCTAssertEqual(try SampleUITestCase.allowance(raw: "panels, sharepicker", host: .mac), [.panels, .sharepicker])
        XCTAssertThrowsError(try SampleUITestCase.allowance(raw: "panel", host: .mac))
        for category in DeviceCategory.allCases where category.isVMOnly {
            XCTAssertThrowsError(try SampleUITestCase.allowance(raw: category.rawValue, host: .mac))
            XCTAssertEqual(try SampleUITestCase.allowance(raw: category.rawValue, host: .vm), [category])
        }
        XCTAssertEqual(Set(DeviceCategory.allCases.filter(\.isVMOnly)), [.ncsettings, .pasteprivacy, .realservice])
    }

    func testTestKeyIsReadFromTheTwoKnownShapesOnly() throws {
        XCTAssertEqual(try SampleUITestCase.normalizedTestKey(fromName: "-[MacLibraryExampleUITests.DialogUITests testD1_showDialogOK]"),
                       "DialogUITests/testD1_showDialogOK")
        XCTAssertEqual(try SampleUITestCase.normalizedTestKey(fromName: "-[DialogUITests testD1_showDialogOK]"),
                       "DialogUITests/testD1_showDialogOK")
        XCTAssertThrowsError(try SampleUITestCase.normalizedTestKey(fromName: "-[Other.DialogUITests testD1]"))
        XCTAssertThrowsError(try SampleUITestCase.normalizedTestKey(fromName: "DialogUITests/testD1"))
        XCTAssertThrowsError(try SampleUITestCase.normalizedTestKey(fromName: "-[DialogUITests helper]"))
    }

    func testDeclarationTableRejectsBrokenShapes() throws {
        func parse(_ text: String) throws -> [String: Set<DeviceCategory>] {
            try DeviceRequirements.parse(Data(text.utf8))
        }
        XCTAssertEqual(try parse(#"{"schema": 1, "tests": {"A/testB": ["panels"]}}"#), ["A/testB": [.panels]])
        XCTAssertThrowsError(try parse(#"{"schema": 1, "tests": {"A/testB": [], "A/testB": ["panels"]}}"#))
        XCTAssertThrowsError(try parse(#"{"schema": 1, "tests": {"A/testB": ["panel"]}}"#))
        XCTAssertThrowsError(try parse(#"{"schema": 1, "tests": {"A/testB": ["panels", "panels"]}}"#))
        XCTAssertThrowsError(try parse(#"{"schema": 2, "tests": {}}"#))
        XCTAssertThrowsError(try parse(#"{"schema": 1, "tests": {"A/B": []}}"#))
        // The bundled table parses and declares this test with no category.
        XCTAssertEqual(try DeviceRequirements.categories(for: "SupportRuleTests/testDeclarationTableRejectsBrokenShapes"), [])
    }

    // MARK: - Fixture (U-11)

    func testFixtureIsOnlyTheRunnersFolder() throws {
        let fixture = try PanelFixture.parse("/private/tmp/ntk-uitest-abc/")
        XCTAssertEqual(fixture.path, "/private/tmp/ntk-uitest-abc")
        XCTAssertEqual(fixture.name, "ntk-uitest-abc")
        XCTAssertEqual(fixture.normalized(#"["/private/tmp/ntk-uitest-abc/a.txt"], "/private/tmp/ntk-uitest-abc""#),
                       #"["<fixture>/a.txt"], "<fixture>""#)
        XCTAssertThrowsError(try PanelFixture.parse(""))
        XCTAssertThrowsError(try PanelFixture.parse("/private/tmp/ntk-uitest-"))
        XCTAssertThrowsError(try PanelFixture.parse("/tmp/ntk-uitest-abc"))
        XCTAssertThrowsError(try PanelFixture.parse("/private/tmp/ntk-uitest-abc/sub"))
        XCTAssertThrowsError(try PanelFixture.parse("/Users/someone"))
    }

    // MARK: - Overlay rule for Notification Center (5.0)

    private static let center = SystemLabels.notificationCenterBundleIdentifier
    private static let root = CGRect(x: 664, y: 103, width: 344, height: 73)
    private static var rootPoint: CGPoint { CGPoint(x: root.midX, y: root.midY) }
    /// Notification Center's full-display window: on 15.8.3 the banners are drawn in it.
    private static let centerFull = window(11, center, layer: 23, display)

    private func bannerVerdict(_ windows: [ScreenWindow], point: CGPoint = rootPoint) -> OverlayVerdict {
        NotificationOverlayRule.verdict(point: point, kind: .banner(rootFrame: Self.root), windows: windows,
                                        displays: [Self.display])
    }

    /// The design's self-test of "another window of the same owner" (7): (1) one window holds the root
    /// and is frontmost: press; (2) another window of the owner covers only the point; (3) two windows
    /// hold the root; (4) the owner or the window is missing: no press.
    func testNotificationOverlayPressesOnlyTheOneWindowThatHoldsTheRoot() {
        let automation = Self.window(10, "com.apple.dt.AutomationModeUI", layer: 1000, Self.display)
        let dock = Self.window(12, "com.apple.dock", layer: 20, Self.display)
        // (1)
        XCTAssertEqual(bannerVerdict([automation, Self.centerFull, dock, Self.sampleWindow]), .clear)
        // (2)
        let menu = Self.window(11, Self.center, layer: 101, CGRect(x: 820, y: 130, width: 80, height: 54))
        XCTAssertEqual(bannerVerdict([menu, Self.centerFull, Self.sampleWindow]), .blocked)
        // (3)
        let bannerWindow = Self.window(11, Self.center, layer: 23, CGRect(x: 650, y: 90, width: 370, height: 100))
        XCTAssertEqual(bannerVerdict([bannerWindow, Self.centerFull]), .blocked)
        XCTAssertEqual(bannerVerdict([bannerWindow]), .clear)
        // (4)
        XCTAssertEqual(bannerVerdict([Self.window(11, nil, layer: 23, Self.display)]), .blocked)
        XCTAssertEqual(bannerVerdict([automation, dock]), .noWindow)
        // Another app in front of the point, and a point outside the root.
        let other = Self.window(30, "com.example.other", CGRect(x: 700, y: 120, width: 200, height: 40))
        XCTAssertEqual(bannerVerdict([other, Self.centerFull]), .blocked)
        XCTAssertEqual(bannerVerdict([Self.centerFull], point: CGPoint(x: 500, y: 500)), .blocked)
    }

    func testNotificationOverlayPressesAMenuItemOnlyOnNotificationCenter() {
        let menu = Self.window(11, Self.center, layer: 101, CGRect(x: 918, y: 171, width: 80, height: 54))
        let item = CGPoint(x: 958, y: 187)
        func verdict(_ windows: [ScreenWindow]) -> OverlayVerdict {
            NotificationOverlayRule.verdict(point: item, kind: .menuItem, windows: windows, displays: [Self.display])
        }
        XCTAssertEqual(verdict([menu, Self.centerFull, Self.sampleWindow]), .clear)
        let other = Self.window(30, "com.example.other", CGRect(x: 900, y: 160, width: 100, height: 100))
        XCTAssertEqual(verdict([other, menu, Self.centerFull]), .blocked)
        XCTAssertEqual(verdict([Self.window(31, nil, layer: 101, CGRect(x: 918, y: 171, width: 80, height: 54))]), .blocked)
    }

    /// A banner is drawn inside Notification Center's full-display window on 15.8.3, so the window
    /// rule cannot see it over a sample button; the banner list's frame can.
    func testOverlayStopsAtABannerListOverThePoint() {
        let windows = Self.passiveFront + [Self.sampleWindow]
        let over = CGRect(x: 80, y: 280, width: 300, height: 100)
        XCTAssertEqual(OverlayRule.verdict(point: Self.point, elementFrame: Self.button, windows: windows,
                                           displays: [Self.display], allowedPIDs: [Self.samplePID],
                                           notificationAreas: [over]), .notificationCenter)
        let aside = CGRect(x: 664, y: 40, width: 344, height: 136)
        XCTAssertEqual(OverlayRule.verdict(point: Self.point, elementFrame: Self.button, windows: windows,
                                           displays: [Self.display], allowedPIDs: [Self.samplePID],
                                           notificationAreas: [aside]), .clear)
    }

    // MARK: - Notification rules

    func testBannerAnchorComparesTheWholeLabel() {
        let anchor = BannerAnchor.immediate
        XCTAssertTrue(anchor.matches("MacLibraryExample, Immediate Notification, MacLibraryExample, Displayed now"))
        XCTAssertFalse(anchor.matches("MacLibraryExample, Immediate Notification, MacLibraryExample, Displayed now, stacked"))
        XCTAssertFalse(anchor.matches("Other, Immediate Notification, MacLibraryExample, Displayed now"))
        XCTAssertFalse(BannerAnchor(title: "Immediate", body: "Displayed now")
            .matches("MacLibraryExample, Immediate Notification, MacLibraryExample, Displayed now"))
        XCTAssertTrue(anchor.label.hasPrefix(BannerAnchor.anyRootPrefix))
    }

    func testLastEventMatchesEveryField() {
        let value = "#1 kind=textInput notificationId=mac-sample-notification-1795377411 actionId=reply userText=hello reply userInfo=id:mac-sample-notification-1795377411,source:MacLibraryExample"
        guard let event = LastEvent.parse(value) else {
            return XCTFail("the sample's shape did not parse")
        }
        XCTAssertEqual(event.userText, "hello reply")
        let expected = ExpectedEvent(sequence: 1, kind: "textInput", notificationId: .immediate, actionId: "reply",
                                     userText: "hello reply")
        XCTAssertTrue(expected.matches(event))
        XCTAssertFalse(ExpectedEvent(sequence: 2, kind: "textInput", notificationId: .immediate, actionId: "reply",
                                     userText: "hello reply").matches(event))
        XCTAssertFalse(ExpectedEvent(sequence: 1, kind: "action", notificationId: .immediate, actionId: "reply",
                                     userText: "hello reply").matches(event))
        XCTAssertFalse(ExpectedEvent(sequence: 1, kind: "textInput", notificationId: .exact("mac-sample-notification"),
                                     actionId: "reply", userText: "hello reply").matches(event))
        // The user info must carry the same id.
        let other = LastEvent.parse(value.replacingOccurrences(of: "userInfo=id:mac-sample-notification-1795377411",
                                                               with: "userInfo=id:mac-sample-notification-1"))
        XCTAssertNotNil(other)
        XCTAssertFalse(expected.matches(other!))
        XCTAssertNil(LastEvent.parse("#1 kind=action notificationId=x"))
        XCTAssertEqual(LastEvent.parse("#0 " + LastEvent.initialText)?.kind, "none")
    }

    func testNotificationListParsesOnlyTheExactShape() {
        XCTAssertEqual(NotificationIDList.parse("[getScheduled] count=0, ids=[]", label: "getScheduled"),
                       NotificationIDList(count: 0, ids: []))
        let two = NotificationIDList.parse("[getDelivered] count=2, ids=[mac-sample-scheduled, mac-sample-notification-12]",
                                           label: "getDelivered")
        XCTAssertEqual(two?.ids, ["mac-sample-scheduled", "mac-sample-notification-12"])
        XCTAssertEqual(two?.hasExactly(["mac-sample-scheduled"], immediate: 1), true)
        XCTAssertEqual(two?.hasExactly(["mac-sample-scheduled"]), false)
        XCTAssertNil(NotificationIDList.parse("[getScheduled] count=2, ids=[a]", label: "getScheduled"))
        XCTAssertNil(NotificationIDList.parse("[getScheduled] count=2, ids=[a, a]", label: "getScheduled"))
        XCTAssertNil(NotificationIDList.parse("[getScheduled] count=1, ids=[a]", label: "getDelivered"))
        XCTAssertNil(NotificationIDList.parse("[getScheduled] count=1, ids=[a] ", label: "getScheduled"))
        XCTAssertNil(NotificationIDList.parse("[getScheduled] count=x, ids=[]", label: "getScheduled"))
    }

    func testSecondsWindowWaitsUntilFiveToThirty() {
        let cases: [(Double, Double)] = [(30.0, 35.5), (30.5, 35), (31, 34.5), (59, 6.5), (4.9, 0.6), (5, 0),
                                        (28.9, 0), (29.0, 36.5), (29.9, 35.6), (0, 5.5)]
        for (second, delay) in cases {
            XCTAssertEqual(SecondsWindow.delay(fromSecond: second), delay, accuracy: 0.0001, "second \(second)")
            XCTAssertLessThanOrEqual(SecondsWindow.delay(fromSecond: second), SecondsWindow.deadline)
            XCTAssertTrue(SecondsWindow.contains(second: (second + SecondsWindow.delay(fromSecond: second))
                .truncatingRemainder(dividingBy: 60)))
            // After a wait, a wall clock a few milliseconds behind the sleep still lands inside (stage 0d 17).
            XCTAssertTrue(delay == 0 || SecondsWindow.contains(second: (second + SecondsWindow.delay(fromSecond: second) - 0.01 + 60)
                .truncatingRemainder(dividingBy: 60)), "second \(second)")
        }
        XCTAssertFalse(SecondsWindow.contains(second: 30))
        XCTAssertFalse(SecondsWindow.contains(second: 4.99))
    }

    func testLaunchCopyIsTwelveHexDigits() {
        XCTAssertTrue(LaunchCopy.isWellFormed("copy=0123456789ab"))
        XCTAssertFalse(LaunchCopy.isWellFormed("copy=0123456789a"))
        XCTAssertFalse(LaunchCopy.isWellFormed("copy=0123456789abc"))
        XCTAssertFalse(LaunchCopy.isWellFormed("copy=0123456789AB"))
        XCTAssertFalse(LaunchCopy.isWellFormed(""))
    }

    // MARK: - Notification Center's groups around a press (runner review v7: Codex B-1; CenterLayoutRule review v1)

    private static let list = "AXNotificationListItems"

    private static func g(_ identifier: String, _ x: CGFloat, _ y: CGFloat, _ w: CGFloat = 360, _ h: CGFloat = 80,
                          in parent: String? = nil) -> CenterGroup {
        CenterGroup(identifier: identifier, frame: CGRect(x: x, y: y, width: w, height: h), parent: parent)
    }

    private func after(_ before: [CenterGroup], _ after: [CenterGroup], root: String = "R") -> CenterPressVerdict {
        CenterLayoutRule.afterClick(beforeClick: before, afterClick: after, pressedRoot: root)
    }

    func testCenterLayoutBeforeTheClickTakesOnlyTheSameGroups() {
        let a = Self.g("A", 600, 40), r = Self.g("R", 600, 130)
        let cases: [(String, [CenterGroup], CenterPressVerdict)] = [
            ("the same groups in another order", [r, a], .clear),
            ("a frame moved by half a point", [a, Self.g("R", 600, 130.5)], .changed),
            ("a group came", [a, r, Self.g("B", 600, 220)], .changed),
            ("a group went", [r], .changed),
            ("another identifier at the same frame", [Self.g("B", 600, 40), r], .changed),
            ("a group without an identifier came", [a, r, Self.g("", 600, 220)], .changed),
            ("the same identifier twice", [a, r, a], .changed),
            ("another parent", [a, Self.g("R", 600, 130, in: "A")], .changed)
        ]
        for (name, beforeClick, expected) in cases {
            XCTAssertEqual(CenterLayoutRule.beforeClick(atCheck: [a, r], beforeClick: beforeClick), expected, name)
        }
    }

    /// The reads of 15.8.3 in the VM (2026-11-28): the whole screen and a large group without identifiers, the list,
    /// and in it another notification (T) and the pressed root (R).
    private func checkWhatARightPressDoesOn15() {
        let screen = Self.g("", 0, 0, 1024, 768), big = Self.g("", 272, 0, 752, 691)
        let t = Self.g("T", 664, 40, 344, 57, in: Self.list), r = Self.g("R", 664, 103, 344, 73, in: Self.list)
        // N22 (body): the list grew by 6 points; nothing else changed.
        XCTAssertEqual(after([screen, big, Self.g(Self.list, 664, 40, 344, 136), t, r],
                             [screen, big, Self.g(Self.list, 658, 40, 350, 136), t, r]), .clear)
        // N23 (Open): the root and the list went; T, the last banner, took the list's frame.
        XCTAssertEqual(after([screen, big, Self.g(Self.list, 658, 40, 350, 136), t, r],
                             [screen, big, Self.g("T", 658, 40, 350, 136)]), .clear)
        // The body closed the root and nothing else moved.
        XCTAssertEqual(after([screen, big, Self.g(Self.list, 664, 40, 344, 136), t, r],
                             [screen, big, Self.g(Self.list, 664, 40, 344, 136), t]), .clear)
    }

    func testCenterLayoutAfterTheClickTellsWhatItCanAndRefusesTheRest() {
        let l = Self.g(Self.list, 600, 30, 360, 190)
        let a = Self.g("A", 600, 40, in: Self.list), r = Self.g("R", 600, 130, in: Self.list), u = Self.g("", 600, 220)
        let before = [l, a, r, u]
        // (what happened, the read after the click, the verdict).
        let cases: [(String, [CenterGroup], CenterPressVerdict)] = [
            ("nothing changed", before, .clear),
            ("the pressed root closed (body)", [l, a, u], .clear),
            ("the pressed root closed and a group without an identifier moved up", [l, a, Self.g("", 600, 130)], .cannotTell),
            ("a banner moved, same size", [l, Self.g("A", 600, 300, in: Self.list), r, u], .clear),
            ("the pressed root grew with a part of its own", [l, a, Self.g("R", 600, 130, 360, 200, in: Self.list),
                                                              Self.g("", 610, 200, 100, 30, in: "R"), u], .clear),
            ("a group without an identifier inside the root's frame but not below it",
             [l, a, Self.g("R", 600, 130, 360, 200, in: Self.list), Self.g("", 610, 200, 100, 30), u], .cannotTell),
            ("the pressed root grew with a new named part (counted)", [l, a, Self.g("R", 600, 130, 360, 200, in: Self.list),
                                                                    Self.g("R.part", 610, 150, 100, 30, in: "R"), u], .arrived),
            ("a named group came", before + [Self.g("B", 600, 310)], .arrived),
            ("the same identifier once more", before + [Self.g("A", 600, 310, in: Self.list)], .arrived),
            ("two groups merged into a new one", [Self.g("M", 600, 40, 360, 160), u], .arrived),
            ("a banner grew (one merged into it)", [l, Self.g("A", 600, 40, 360, 85, in: Self.list), r, u], .cannotTell),
            ("the list grew", [Self.g(Self.list, 594, 30, 372, 190), a, r, u], .clear),
            ("a group without an identifier came", before + [Self.g("", 600, 310)], .cannotTell),
            ("a group without an identifier moved", [l, a, r, Self.g("", 600, 400)], .cannotTell),
            ("a group without an identifier went", [l, a, r], .clear)
        ]
        for (name, afterClick, expected) in cases {
            XCTAssertEqual(after(before, afterClick), expected, name)
        }
        // No pressed root (an empty identifier) exempts nothing.
        XCTAssertEqual(after([u, a], [u, a, Self.g("", 610, 230, 10, 10, in: "")], root: ""), .cannotTell)
        XCTAssertEqual(after([u, Self.g("A", 600, 40, in: "")], [u, Self.g("A", 600, 40, 360, 120, in: "")], root: ""), .cannotTell)
        // Duplicates: counted, never matched one to one by guess.
        XCTAssertEqual(after([a, a, r], [a, Self.g("A", 600, 300, in: Self.list), r]), .clear)
        XCTAssertEqual(after([a, a, r], [a, a, a, r]), .arrived)
        checkWhatARightPressDoesOn15()
        checkWhatARightPressDoesOn26()
        checkNoExceptionFromFramesAlone()
    }

    /// CenterLayoutRule review v1: a group is not a container because its frame holds another (A-1), and a group
    /// that grew to a frame that went away is not a collapse unless the list, the root and the parents say so (A-2).
    private func checkNoExceptionFromFramesAlone() {
        // A-1: A grew over R; it holds R by frame, not by the snapshot.
        XCTAssertEqual(after([Self.g("A", 600, 40), Self.g("R", 600, 130)],
                             [Self.g("A", 600, 40, 360, 180), Self.g("R", 600, 130)]), .cannotTell)
        // A-1: the list's identifier on a group that held no banner before the click.
        XCTAssertEqual(after([Self.g(Self.list, 600, 30, 360, 190), Self.g("A", 600, 40), Self.g("R", 600, 130)],
                             [Self.g(Self.list, 594, 30, 372, 190), Self.g("A", 600, 40), Self.g("R", 600, 130)]), .cannotTell)
        // A-1: a group that held banners but is not a checked list.
        XCTAssertEqual(after([Self.g("X", 600, 30, 360, 190), Self.g("A", 600, 40, in: "X"), Self.g("R", 600, 130, in: "X")],
                             [Self.g("X", 594, 30, 372, 190), Self.g("A", 600, 40, in: "X"), Self.g("R", 600, 130, in: "X")]),
                       .cannotTell)
        // A-2 (the review's example): X went, A took X's frame, and the pressed root stays.
        XCTAssertEqual(after([Self.g("A", 600, 40), Self.g("R", 600, 250), Self.g("X", 600, 30, 360, 160)],
                             [Self.g("A", 600, 30, 360, 160), Self.g("R", 600, 250)]), .cannotTell)
        // A-2: each condition of the collapse missing in turn, from the N23 reads.
        let l = Self.g(Self.list, 658, 40, 350, 136), t = Self.g("T", 664, 40, 344, 57, in: Self.list)
        let r = Self.g("R", 664, 103, 344, 73, in: Self.list), s = Self.g("S", 664, 180, 344, 57, in: Self.list)
        let onto = Self.g("T", 658, 40, 350, 136)
        XCTAssertEqual(after([l, t, r], [onto, Self.g("R", 664, 103, 344, 73)]), .cannotTell)            // the root stays
        XCTAssertEqual(after([l, t, r], [l, Self.g("T", 658, 40, 350, 136, in: Self.list)]), .cannotTell) // the list stays
        XCTAssertEqual(after([l, t, r, s], [onto, Self.g("S", 664, 180, 344, 57)]), .cannotTell)       // two were left
        XCTAssertEqual(after([l, Self.g("T", 664, 40, 344, 57), r], [onto]), .cannotTell)                // T was not in the list
        XCTAssertEqual(after([l, t, Self.g("R", 664, 103, 344, 73)], [onto]), .cannotTell)               // R was not in the list
        XCTAssertEqual(after([l, t, r], [Self.g("T", 658, 40, 350, 137)]), .cannotTell)                  // not the list's frame
        XCTAssertEqual(after([l, t, r], [onto], root: "Q"), .cannotTell)                                 // another root pressed
        XCTAssertEqual(after([Self.g("X", 658, 40, 350, 136), Self.g("T", 664, 40, 344, 57, in: "X"),     // not a checked list
                              Self.g("R", 664, 103, 344, 73, in: "X")], [onto]), .cannotTell)
    }

    /// The reads of 26.6.2 in the VM (2026-11-28, NP2): no list, three widgets, and the prompt (the pressed root) that
    /// is read once more without its identifier while it closes.
    private func checkWhatARightPressDoesOn26() {
        let screen = Self.g("", 0, 0, 1024, 768), big = Self.g("", 272, 0, 752, 690)
        let widget = Self.g("", 8, 218, 360, 180), photos = Self.g("widget-local:photos", 16, 226, 344, 164)
        let others = [screen, big, widget, photos]
        let prompt = Self.g("P", 658, 42, 350, 77)
        XCTAssertEqual(after(others + [prompt], others + [Self.g("", 658, 42, 350, 77)], root: "P"), .clear)
        XCTAssertEqual(after(others + [prompt], others + [Self.g("", 658, 50, 350, 77)], root: "P"), .cannotTell)  // moved
        XCTAssertEqual(after(others + [prompt], others + [prompt, Self.g("", 658, 42, 350, 77)], root: "P"),
                       .cannotTell)                                                                            // root stays
        XCTAssertEqual(after(others + [prompt], others + [Self.g("", 658, 42, 350, 77), Self.g("", 658, 42, 350, 77)],
                             root: "P"), .cannotTell)                                                          // two
        XCTAssertEqual(after(others + [prompt], others + [Self.g("", 658, 42, 350, 77, in: "X")], root: "P"),
                       .cannotTell)                                                                            // another parent
        XCTAssertEqual(after(others + [prompt], others + [Self.g("", 658, 42, 350, 77)], root: "Q"), .cannotTell)  // not the root
        // NP1 (`Allow`): the highlight under the pointer moved from the prompt (6 by 4 points smaller) to the banner
        // below it (6 by 4 points larger); the list moved with them.
        let l = Self.g(Self.list, 658, 42, 350, 172), p = Self.g("P", 658, 42, 350, 77, in: Self.list)
        let b = Self.g("B", 664, 125, 344, 89, in: Self.list)
        let lAfter = Self.g(Self.list, 658, 46, 350, 168)
        XCTAssertEqual(after(others + [l, p, b], others + [lAfter, Self.g("P", 664, 46, 344, 73, in: Self.list),
                                                           Self.g("B", 658, 121, 350, 93, in: Self.list)], root: "P"), .clear)
        // ... and what it is not: a gain without a loss, a gain over the limit, a gain other than the loss, two gains
        // for one loss, banners outside a checked list.
        XCTAssertEqual(after(others + [l, p, b], others + [lAfter, p, Self.g("B", 658, 121, 350, 93, in: Self.list)],
                             root: "P"), .cannotTell)
        XCTAssertEqual(after(others + [l, p, b], others + [lAfter, Self.g("P", 664, 46, 344, 47, in: Self.list),
                                                           Self.g("B", 658, 95, 350, 119, in: Self.list)], root: "P"), .cannotTell)
        XCTAssertEqual(after(others + [l, p, b], others + [lAfter, Self.g("P", 664, 46, 344, 72, in: Self.list),
                                                           Self.g("B", 658, 121, 350, 93, in: Self.list)], root: "P"), .cannotTell)
        let c = Self.g("C", 664, 220, 344, 89, in: Self.list)
        XCTAssertEqual(after(others + [l, p, b, c], others + [lAfter, Self.g("P", 664, 46, 344, 73, in: Self.list),
                                                              Self.g("B", 658, 121, 350, 93, in: Self.list),
                                                              Self.g("C", 658, 216, 350, 93, in: Self.list)], root: "P"), .cannotTell)
        // N22 (body): the list went and the last banner took the list's frame, drawn 6 points wider by its highlight.
        let l22 = Self.g(Self.list, 664, 46, 344, 168), t22 = Self.g("T", 664, 46, 344, 89, in: Self.list)
        let r22 = Self.g("R", 664, 141, 344, 73, in: Self.list)
        XCTAssertEqual(after(others + [l22, t22, r22], others + [Self.g("T", 658, 46, 350, 168)]), .clear)
        XCTAssertEqual(after(others + [l22, t22, r22], others + [Self.g("T", 654, 46, 354, 168)]), .cannotTell)  // 10 wider
        XCTAssertEqual(after(others + [l22, t22, r22], others + [Self.g("T", 658, 46, 350, 169)]), .cannotTell)  // higher
        XCTAssertEqual(after(others + [l22, t22, r22], others + [Self.g("T", 664, 46, 350, 168)]), .cannotTell)  // to the right
        XCTAssertEqual(after(others + [Self.g("X", 658, 42, 350, 172), Self.g("P", 658, 42, 350, 77, in: "X"),
                                       Self.g("B", 664, 125, 344, 89, in: "X")],
                             others + [Self.g("X", 658, 46, 350, 168), Self.g("P", 664, 46, 344, 73, in: "X"),
                                       Self.g("B", 658, 121, 350, 93, in: "X")], root: "P"), .cannotTell)
    }

    func testCenterLayoutDoesNotSeeWhatItsReadsCannotShow() {
        // The limit, written down (design 9.1; presscenter review v1 A-1; CenterLayoutRule review v1 B-1): these pass
        // although a notification may have taken the click.
        let a = Self.g("A", 600, 40), r = Self.g("R", 600, 130)
        // A notification that took the click and went away before the read after it.
        XCTAssertEqual(after([a, r], [r]), .clear)
        // A new notification with the identifier, frame and size of one that went away.
        XCTAssertEqual(after([a, r], [a, r]), .clear)
        // A notification that merged into the last banner exactly as the list collapsed onto it: the same reads as
        // the collapse (N23), so it cannot be told from it.
        let l = Self.g(Self.list, 658, 40, 350, 136), t = Self.g("T", 664, 40, 344, 57, in: Self.list)
        XCTAssertEqual(after([l, t, Self.g("R", 664, 103, 344, 73, in: Self.list)], [Self.g("T", 658, 40, 350, 136)]), .clear)
    }
}
