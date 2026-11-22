//
//  SupportRuleTests.swift
//  MacLibraryExampleUITests
//
//  Checks the pure rules of the Support files without launching anything (`common.md`: a rule that
//  decides is cut out as a pure function and broken directly). The overlay rule (design 5.0), the
//  result rule (U-3), the gate's host and allowance (U-9), the test key, the declaration table and
//  the fixture path (U-11).
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
}
