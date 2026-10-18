//
//  ShareSheet.swift
//  IosLibraryExampleUITests
//
//  Operations on the share sheet that the sample presents (UI test design 3.4, 6.1, U-11, U-13).
//  Only Copy, Save to Files and closing are pressed; no other cell is touched. Every entry point
//  needs a `ShareSheetToken`; Copy also needs `ClipboardToken`, Save to Files `FilesToken`.
//  On the device no cell label is written. Trusted Support file.
//

import XCTest
import Foundation

struct ShareSheet {

    /// The sheet is shown in the sample's process.
    private let app = XCUIApplication(bundleIdentifier: SystemLabels.sampleBundleIdentifier)
    private let session: UITestSession

    static let sheetTimeout: TimeInterval = 10
    static let pickerTimeout: TimeInterval = 10

    init(_ token: ShareSheetToken) {
        session = token.session
    }

    /// The sheet's action cells (`Copy`, `Save to Files`). Only cells are matched: each cell also
    /// holds a title text with the same label (iOS 26.2, stage 0c).
    private func cells(_ labels: [String]) -> XCUIElementQuery {
        app.cells.matching(NSPredicate(format: "label IN %@", labels))
    }

    private func buttons(_ labels: [String]) -> XCUIElementQuery {
        app.buttons.matching(NSPredicate(format: "label IN %@", labels))
    }

    /// Elements that mark an open sheet: the navigation bar `UIActivityContentView` (iOS 18 and
    /// 26.2 without a preview title) or the activity list `ActivityListView` (26.2; with a preview
    /// title the navigation bar is named after the title).
    private var openMarkers: XCUIElementQuery {
        app.descendants(matching: .any).matching(NSPredicate(format: "identifier IN %@", SystemLabels.shareSheetMarkers))
    }

    /// Waits until the sheet is shown. Returns false otherwise.
    func waitOpen(timeout: TimeInterval = ShareSheet.sheetTimeout) throws -> Bool {
        let found = openMarkers.firstMatch.waitForExistence(timeout: timeout)
        try session.checkInterruption()
        return found
    }

    /// Waits until the sheet has gone.
    func waitClosed(timeout: TimeInterval = ShareSheet.sheetTimeout) throws -> Bool {
        let gone = openMarkers.firstMatch.waitForNonExistence(timeout: timeout)
        try session.checkInterruption()
        return gone
    }

    /// Whether the sheet is shown now (no wait).
    var isOpen: Bool { openMarkers.count > 0 }

    /// Number of Copy cells now (U-13: 2+ means do not press).
    var copyCount: Int { cells(SystemLabels.copy).count }

    /// Waits until the Copy cell is shown. Returns false otherwise.
    func waitForCopy(timeout: TimeInterval = ShareSheet.sheetTimeout) throws -> Bool {
        let found = cells(SystemLabels.copy).firstMatch.waitForExistence(timeout: timeout)
        try session.checkInterruption()
        return found
    }

    /// Labels of the header's title (`LP.CaptionBar.TopCaption`), read every 0.1 s for `duration`
    /// seconds from now. Consecutive equal readings are kept once; "" means no title element.
    func observeHeaderTitle(for duration: TimeInterval) -> [String] {
        let caption = app.descendants(matching: .any).matching(identifier: SystemLabels.shareHeaderTitle)
        var seen: [String] = []
        let deadline = Date().addingTimeInterval(duration)
        repeat {
            let label = caption.count == 1 ? caption.element.label : ""
            if seen.last != label { seen.append(label) }
            Thread.sleep(forTimeInterval: 0.1)
        } while Date() < deadline
        return seen
    }

    /// Closes the sheet: `Close` on iOS 18, `PopoverDismissRegion` on iOS 26 (U-16).
    func close() throws {
        if SampleUITestCase.osMajorVersion >= 26 {
            try exactlyOne(app.otherElements.matching(identifier: SystemLabels.popoverDismissRegion), SystemLabels.popoverDismissRegion).tap()
        } else {
            try exactlyOne(buttons(SystemLabels.close), "share sheet Close").tap()
        }
        try session.checkInterruption()
    }

    /// Drags the sheet's header (the `UIActivityContentView` navigation bar) down (works on both
    /// versions. Stage 0a 3.6).
    func dragHeaderDown() throws {
        let header = try exactlyOne(app.navigationBars.matching(identifier: SystemLabels.activityContentView), SystemLabels.activityContentView)
        let top = header.coordinate(withNormalizedOffset: CGVector(dx: 0.3, dy: 0.3))
        let bottom = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.99))
        top.press(forDuration: 0.1, thenDragTo: bottom)
        try session.checkInterruption()
    }

    /// Waits for the Copy cell and taps it (exactly one match. U-13).
    func copy(_ token: ClipboardToken) throws {
        guard try waitForCopy() else {
            throw SampleUITestError("Copy did not appear")
        }
        try exactlyOne(cells(SystemLabels.copy), "Copy").tap()
        try session.checkInterruption()
    }

    /// Save to Files into On My iPhone; Keep Both when asked to replace (U-11). When On My iPhone
    /// cannot be chosen, cancels without saving and throws. `isFinished` tells that the sample has
    /// reported the result; the replace prompt is polled for until then (no fixed wait. U-14).
    func saveToFiles(_ token: FilesToken, isFinished: () throws -> Bool) throws {
        let saveToFiles = cells(SystemLabels.saveToFiles)
        guard saveToFiles.firstMatch.waitForExistence(timeout: Self.sheetTimeout) else {
            throw SampleUITestError("Save to Files did not appear")
        }
        try exactlyOne(saveToFiles, "Save to Files").tap()
        try session.checkInterruption()
        let save = buttons(SystemLabels.save)
        guard save.firstMatch.waitForExistence(timeout: Self.pickerTimeout) else {
            throw SampleUITestError("the Files picker did not appear")
        }
        try chooseOnMyIPhone()
        // A tap while the picker was still animating closed it without saving or a completion
        // (stage 0c, iOS 26.2, 1 of 4 runs), so Save is tapped once it has settled.
        try tapWhenSettled(try exactlyOne(save, "Save"), "Save")
        let keepBoth = buttons(SystemLabels.keepBoth)
        let deadline = Date().addingTimeInterval(Self.pickerTimeout)
        while try !isFinished() {
            if keepBoth.count > 0 {
                try tapKeepBoth(keepBoth)
                return
            }
            guard Date() < deadline else {
                throw SampleUITestError("Save to Files did not finish")
            }
            Thread.sleep(forTimeInterval: 0.25)
        }
    }

    /// Taps Keep Both on the replace prompt once it has settled (a tap during the alert's
    /// appearance animation was swallowed on iOS 26.2), and waits until the prompt has gone. When it
    /// is still shown, taps once more (the same button).
    private func tapKeepBoth(_ keepBoth: XCUIElementQuery) throws {
        for _ in 0..<2 {
            try tapWhenSettled(try exactlyOne(keepBoth, "Keep Both"), "Keep Both")
            if keepBoth.firstMatch.waitForNonExistence(timeout: 5) {
                return
            }
        }
        throw SampleUITestError("the replace prompt did not close after Keep Both")
    }

    /// Taps `element` once it is enabled, hittable and its frame reads the same twice in a row
    /// (0.25 s apart).
    private func tapWhenSettled(_ element: XCUIElement, _ name: String) throws {
        let deadline = Date().addingTimeInterval(Self.pickerTimeout)
        var previous = CGRect.null
        while !(element.isEnabled && element.isHittable && element.frame == previous) {
            guard Date() < deadline else {
                throw SampleUITestError("\(name) did not settle")
            }
            previous = element.frame
            Thread.sleep(forTimeInterval: 0.25)
        }
        element.tap()
        try session.checkInterruption()
    }

    /// Whether the Files picker shows On My iPhone: its browsing root is the local storage provider
    /// (iOS 26.2: `DOC.browsingRoot Source: com.apple.FileProvider.LocalStorage, Title: …`), or the
    /// picker's navigation bar title is On My iPhone.
    private var isAtOnMyIPhone: Bool {
        let root = app.descendants(matching: .any).matching(NSPredicate(format: "identifier BEGINSWITH %@", SystemLabels.localStorageBrowsingRoot))
        if root.count == 1 { return true }
        let title = app.navigationBars.matching(identifier: SystemLabels.filesPickerNavigationBar)
            .staticTexts.matching(NSPredicate(format: "label IN %@", SystemLabels.onMyIPhone))
        return title.count == 1
    }

    private func chooseOnMyIPhone() throws {
        if isAtOnMyIPhone { return }
        let browse = buttons(SystemLabels.browse)
        if browse.count == 1 {
            browse.element.tap()
            try session.checkInterruption()
        }
        let location = app.descendants(matching: .any).matching(NSPredicate(
            format: "label IN %@ AND (elementType == %lu OR elementType == %lu)",
            SystemLabels.onMyIPhone, XCUIElement.ElementType.cell.rawValue, XCUIElement.ElementType.button.rawValue
        ))
        guard location.firstMatch.waitForExistence(timeout: Self.pickerTimeout), location.count == 1 else {
            try cancelPicker()
            throw SampleUITestError("On My iPhone could not be chosen; cancelled without saving")
        }
        location.element.tap()
        try session.checkInterruption()
        let deadline = Date().addingTimeInterval(Self.pickerTimeout)
        while !isAtOnMyIPhone {
            guard Date() < deadline else {
                try cancelPicker()
                throw SampleUITestError("the Files picker did not move to On My iPhone; cancelled without saving")
            }
            Thread.sleep(forTimeInterval: 0.25)
        }
    }

    private func cancelPicker() throws {
        let cancel = buttons(SystemLabels.cancel)
        if cancel.count == 1 {
            cancel.element.tap()
        }
        try session.checkInterruption()
    }
}
