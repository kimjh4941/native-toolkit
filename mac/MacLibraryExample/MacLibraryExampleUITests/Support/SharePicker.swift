//
//  SharePicker.swift
//  MacLibraryExampleUITests
//
//  Operations on the sharing service picker that the sample presents (UI test design U-13, 6.1).
//  The picker is the one `Popover` of the sample's tree (stage 0a 4.3). Only Escape and, on macOS
//  26, Copy are pressed; no service is opened. Service names are not read: the picker's buttons
//  are only counted, and S10 counts the buttons of one named service. Every entry point needs a
//  `SharePickerToken`; Copy also needs `ClipboardToken`.
//  Trusted Support file.
//

import XCTest
import Foundation

struct SharePicker {

    private let sample: SampleApp

    init(_ sample: SampleApp, _ token: SharePickerToken) {
        self.sample = sample
    }

    private var popovers: XCUIElementQuery { sample.supportRoot.popovers }

    /// Waits until exactly one picker is shown.
    @discardableResult
    func waitShown() throws -> XCUIElement {
        try sample.waitForExactlyOne(popovers, "share picker", timeout: SampleApp.systemUITimeout, step: .picker)
    }

    func waitGone() throws {
        guard popovers.firstMatch.waitForNonExistence(timeout: SampleApp.systemUITimeout) else {
            throw SampleUITestError(.picker, "the share picker did not close")
        }
        try sample.session.checkInterruption()
    }

    /// Number of pickers now (no wait).
    var count: Int { popovers.count }

    /// Number of service buttons in the picker (names are not read).
    func serviceCount() throws -> Int {
        try exactlyOne(popovers, "share picker", step: .picker).buttons.count
    }

    /// Number of the picker's buttons named one of `labels` (S10: the excluded service).
    func serviceCount(named labels: [String]) throws -> Int {
        try exactlyOne(popovers, "share picker", step: .picker)
            .buttons.matching(NSPredicate(format: "label IN %@", labels)).count
    }

    /// Closes the picker with Escape: only when exactly one picker is open and no menu is open
    /// (design 5.0, keys), with the sample in front.
    func escape() throws {
        let picker = try exactlyOne(popovers, "share picker", step: .picker)
        guard try openMenuCount() == 0 else {
            throw SampleUITestError(.keyFocus, "a menu is open over the share picker")
        }
        try sample.guardedTypeKey(XCUIKeyboardKey.escape.rawValue, to: picker, name: "share picker Escape")
    }

    /// Presses Copy (macOS 26 only. U-13). Fails without pressing when the picker has none.
    func copy(_ token: ClipboardToken) throws {
        let picker = try exactlyOne(popovers, "share picker", step: .picker)
        let query = picker.buttons.matching(NSPredicate(format: "label IN %@", SystemLabels.copy))
        guard query.count > 0 else {
            throw SampleUITestError(.copyMissing, "the share picker has no Copy")
        }
        let copy = try exactlyOne(query, "Copy", step: .copyMissing)
        try sample.guardedClick(copy, .sampleWindow, name: "Copy")
    }

    /// Watches for `seconds` that no picker appears (U-14 (a): 2 seconds).
    func expectNotShown(for seconds: TimeInterval) throws {
        let deadline = Date().addingTimeInterval(seconds)
        repeat {
            guard popovers.count == 0 else {
                throw SampleUITestError(.picker, "a share picker appeared")
            }
            Thread.sleep(forTimeInterval: 0.1)
        } while Date() < deadline
        try sample.session.checkInterruption()
    }

    /// Menus of the sample that are open: menus outside the menu bar with a visible frame.
    private func openMenuCount() throws -> Int {
        let root = try sample.supportRoot.snapshot()
        var open = 0
        func visit(_ node: XCUIElementSnapshot, inMenuBar: Bool) {
            let menuBar = inMenuBar || node.elementType == .menuBar
            if node.elementType == .menu && !menuBar && node.frame.width > 0 && node.frame.height > 0 {
                open += 1
            }
            for child in node.children {
                visit(child, inMenuBar: menuBar)
            }
        }
        visit(root, inMenuBar: false)
        return open
    }
}
