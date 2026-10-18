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

    private func labeled(_ labels: [String]) -> XCUIElementQuery {
        app.descendants(matching: .any).matching(NSPredicate(format: "label IN %@", labels))
    }

    private var contentView: XCUIElementQuery {
        app.descendants(matching: .any).matching(identifier: SystemLabels.activityContentView)
    }

    /// Waits until the sheet is shown (its activity content view). Returns false otherwise.
    func waitOpen(timeout: TimeInterval = ShareSheet.sheetTimeout) throws -> Bool {
        let found = contentView.firstMatch.waitForExistence(timeout: timeout)
        try session.checkInterruption()
        return found
    }

    /// Whether the sheet is shown now (no wait).
    var isOpen: Bool { contentView.count > 0 }

    /// Number of Copy elements (U-13: 2+ means do not press).
    var copyCount: Int { labeled(SystemLabels.copy).count }

    /// Closes the sheet: `Close` on iOS 18, `PopoverDismissRegion` on iOS 26 (U-16).
    func close() throws {
        let closeButtons = app.buttons.matching(NSPredicate(format: "label IN %@", SystemLabels.close))
        if SampleUITestCase.osMajorVersion >= 26 {
            try exactlyOne(app.otherElements.matching(identifier: SystemLabels.popoverDismissRegion), SystemLabels.popoverDismissRegion).tap()
        } else {
            try exactlyOne(closeButtons, "share sheet Close").tap()
        }
        try session.checkInterruption()
    }

    /// Drags the sheet's header down (works on both versions. Stage 0a 3.6).
    func dragHeaderDown() throws {
        let view = try exactlyOne(contentView, SystemLabels.activityContentView)
        let top = view.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.02))
        let bottom = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.98))
        top.press(forDuration: 0.1, thenDragTo: bottom)
        try session.checkInterruption()
    }

    func copy(_ token: ClipboardToken) throws {
        try exactlyOne(labeled(SystemLabels.copy), "Copy").tap()
        try session.checkInterruption()
    }

    /// Save to Files into On My iPhone; Keep Both when asked to replace (U-11). When On My iPhone
    /// cannot be chosen, cancels without saving and throws.
    func saveToFiles(_ token: FilesToken) throws {
        try exactlyOne(labeled(SystemLabels.saveToFiles), "Save to Files").tap()
        try session.checkInterruption()
        let save = app.buttons.matching(NSPredicate(format: "label IN %@", SystemLabels.save))
        guard save.firstMatch.waitForExistence(timeout: Self.pickerTimeout) else {
            throw SampleUITestError("the Files picker did not appear")
        }
        try chooseOnMyIPhone()
        try exactlyOne(save, "Save").tap()
        try session.checkInterruption()
        let keepBoth = app.buttons.matching(NSPredicate(format: "label IN %@", SystemLabels.keepBoth))
        if keepBoth.firstMatch.waitForExistence(timeout: 3) {
            try exactlyOne(keepBoth, "Keep Both").tap()
            try session.checkInterruption()
        }
    }

    private func chooseOnMyIPhone() throws {
        let onMyIPhone = labeled(SystemLabels.onMyIPhone)
        if onMyIPhone.count == 1, onMyIPhone.element.isSelected {
            return
        }
        let browse = app.buttons.matching(NSPredicate(format: "label IN %@", SystemLabels.browse))
        if browse.count == 1 {
            browse.element.tap()
            try session.checkInterruption()
        }
        let location = app.descendants(matching: .any).matching(NSPredicate(format: "label IN %@", SystemLabels.onMyIPhone))
        guard location.firstMatch.waitForExistence(timeout: Self.pickerTimeout), location.count == 1 else {
            try cancelPicker()
            throw SampleUITestError("On My iPhone could not be chosen; cancelled without saving")
        }
        location.element.tap()
        try session.checkInterruption()
    }

    private func cancelPicker() throws {
        let cancel = app.buttons.matching(NSPredicate(format: "label IN %@", SystemLabels.cancel))
        if cancel.count == 1 {
            cancel.element.tap()
        }
        try session.checkInterruption()
    }
}
