//
//  Panels.swift
//  MacLibraryExampleUITests
//
//  Operations on the open and save panels that the sample presents (UI test design U-11, 6.1).
//  Every entry point needs a `PanelsToken`. Wherever a panel opens, it is moved to the runner's
//  fixture with Cmd+Shift+G, and an item is chosen only after the panel shows the fixture and the
//  item is in the fixture's own column. Nothing outside the fixture is touched.
//  Trusted Support file.
//

import XCTest
import Foundation

/// The fixture folder the runner made (`TEST_RUNNER_NTK_FIXTURE_DIR`, received as
/// `NTK_FIXTURE_DIR`): `/private/tmp/ntk-uitest-<run id>/` with `a.txt`, `b.txt`, `note.md`,
/// `pic.png`, `dirA/`, `dirB/` and `default.txt` (U-11).
struct PanelFixture {
    /// The path without a trailing slash, as the panels report it.
    let path: String

    static let items: Set<String> = ["a.txt", "b.txt", "note.md", "pic.png", "dirA", "dirB", "default.txt"]
    static let folders: Set<String> = ["dirA", "dirB"]
    private static let prefix = "/private/tmp/ntk-uitest-"

    static func fromEnvironment() throws -> PanelFixture {
        try parse(ProcessInfo.processInfo.environment["NTK_FIXTURE_DIR"] ?? "")
    }

    static func parse(_ raw: String) throws -> PanelFixture {
        let trimmed = raw.hasSuffix("/") ? String(raw.dropLast()) : raw
        let runID = trimmed.dropFirst(prefix.count)
        guard trimmed.hasPrefix(prefix), !runID.isEmpty, !runID.contains("/") else {
            throw SampleUITestError(.fixture, "NTK_FIXTURE_DIR is not /private/tmp/ntk-uitest-<id>")
        }
        return PanelFixture(path: trimmed)
    }

    /// The folder's name, which the panel's location pop-up shows.
    var name: String { (path as NSString).lastPathComponent }

    func child(_ item: String) -> String { "\(path)/\(item)" }

    /// `text` with the fixture's path replaced by `<fixture>` (U-1).
    func normalized(_ text: String) -> String {
        text.replacingOccurrences(of: path, with: "<fixture>")
    }
}

struct Panels {

    enum Kind {
        case open
        case save

        var identifier: String { self == .open ? SystemLabels.openPanel : SystemLabels.savePanel }
    }

    private let sample: SampleApp
    let fixture: PanelFixture

    init(_ sample: SampleApp, _ token: PanelsToken) throws {
        self.sample = sample
        fixture = try PanelFixture.fromEnvironment()
    }

    private var app: XCUIApplication { sample.supportRoot }

    private func query(_ kind: Kind) -> XCUIElementQuery {
        app.dialogs.matching(identifier: kind.identifier)
    }

    private func panel(_ kind: Kind) throws -> XCUIElement {
        try exactlyOne(query(kind), kind.identifier, step: .panel)
    }

    // MARK: Showing and closing

    @discardableResult
    func waitShown(_ kind: Kind) throws -> XCUIElement {
        try sample.waitForExactlyOne(query(kind), kind.identifier, timeout: SampleApp.systemUITimeout, step: .panel)
    }

    func waitGone(_ kind: Kind) throws {
        guard query(kind).firstMatch.waitForNonExistence(timeout: SampleApp.systemUITimeout) else {
            throw SampleUITestError(.panel, "\(kind.identifier) did not close")
        }
        try sample.session.checkInterruption()
    }

    // MARK: Location

    /// Moves the panel to the fixture with Cmd+Shift+G and confirms the panel shows it (U-11).
    func goToFixture(_ kind: Kind) throws {
        let panel = try panel(kind)
        try sample.guardedTypeKey("g", modifiers: [.command, .shift], to: panel, name: "\(kind.identifier) go to")
        let field = try sample.waitForExactlyOne(app.textFields.matching(identifier: SystemLabels.goToPathField),
                                                 SystemLabels.goToPathField, timeout: SampleApp.systemUITimeout,
                                                 step: .panel)
        try sample.waitUntil("the go-to field taking the focus", timeout: SampleApp.systemUITimeout, step: .keyFocus) {
            sample.hasKeyboardFocus(field) == true
        }
        // The field keeps the last path; replace it.
        try sample.guardedTypeKey("a", modifiers: .command, to: field, focused: field, name: SystemLabels.goToPathField)
        try sample.guardedTypeText(fixture.path + "/", into: field, name: SystemLabels.goToPathField)
        try sample.guardedTypeKey(XCUIKeyboardKey.return.rawValue, to: field, focused: field, name: SystemLabels.goToPathField)
        guard app.sheets.matching(identifier: SystemLabels.goToSheet).firstMatch.waitForNonExistence(timeout: SampleApp.systemUITimeout) else {
            throw SampleUITestError(.panel, "the go-to sheet did not close")
        }
        try sample.waitUntil("the panel showing the fixture", timeout: SampleApp.elementTimeout, step: .panelLocation) {
            try self.isAtFixture(kind)
        }
    }

    /// Whether the panel's location pop-up names the fixture folder (its name is unique per run).
    func isAtFixture(_ kind: Kind) throws -> Bool {
        try locationName(kind) == fixture.name
    }

    /// The folder name the location pop-up shows.
    private func locationName(_ kind: Kind) throws -> String? {
        let panel = try panel(kind)
        let popup = try exactlyOne(panel.popUpButtons.matching(identifier: SystemLabels.wherePopup),
                                   SystemLabels.wherePopup, step: .panelLocation)
        return popup.value as? String
    }

    // MARK: Choosing items (open panels)

    /// Clicks `item` of the fixture. With `adding`, Cmd is held to add it to the selection.
    func choose(_ item: String, in kind: Kind = .open, adding: Bool = false) throws {
        guard PanelFixture.items.contains(item) else {
            throw SampleUITestError(.fixture, "\(item) is not an item of the fixture")
        }
        // Choosing a folder in a folder panel moves the location into it (stage 0c, VM), so a folder
        // added to the selection is chosen while the location names a folder of the fixture. Either
        // way the item is taken only from the one column that lists exactly the fixture.
        let location = try locationName(kind)
        guard location == fixture.name || (adding && PanelFixture.folders.contains(location ?? "")) else {
            throw SampleUITestError(.panelLocation, "the panel is not at the fixture before choosing \(item)")
        }
        // 26: the fixture's column may lie outside what the panel shows; it is scrolled in and taken again.
        try sample.scrollPanelColumnIntoView(try fixtureItem(item, in: kind), panel: try panel(kind),
                                             name: "fixture item \(item)")
        let element = try fixtureItem(item, in: kind)
        try sample.guardedClick(element, .panel, name: "fixture item \(item)", modifiers: adding ? .command : [])
    }

    /// The text field of `item` in the column view, found only in the one column whose items are
    /// exactly the fixture's, so nothing of another folder can be chosen.
    private func fixtureItem(_ item: String, in kind: Kind) throws -> XCUIElement {
        let panel = try panel(kind)
        let browser = try exactlyOne(panel.browsers.matching(identifier: SystemLabels.columnView),
                                     SystemLabels.columnView, step: .panel)
        let snapshot = try browser.snapshot()
        var fixtureColumns: [CGRect] = []

        func names(in node: XCUIElementSnapshot) -> [String] {
            var found: [String] = []
            if node.elementType == .textField, let value = node.value as? String { found.append(value) }
            for child in node.children { found += names(in: child) }
            return found
        }
        func visit(_ node: XCUIElementSnapshot) {
            if node.elementType == .scrollView {
                let inner = node.children.filter { $0.elementType != .scrollView }
                let listed = inner.flatMap(names(in:))
                if node.children.allSatisfy({ $0.elementType != .scrollView }),
                   Set(listed) == PanelFixture.items, listed.count == PanelFixture.items.count {
                    fixtureColumns.append(node.frame)
                }
            }
            for child in node.children { visit(child) }
        }
        visit(snapshot)
        guard fixtureColumns.count == 1, let column = fixtureColumns.first else {
            throw SampleUITestError(.panelLocation, "expected exactly one column listing the fixture, found \(fixtureColumns.count)")
        }
        let candidates = browser.textFields.matching(NSPredicate(format: "value == %@", item)).allElementsBoundByIndex
            .filter { column.contains(CGPoint(x: $0.frame.midX, y: $0.frame.midY)) }
        guard candidates.count == 1, let element = candidates.first else {
            throw SampleUITestError(.elementNotUnique, "expected exactly one \(item) in the fixture's column, found \(candidates.count)")
        }
        return element
    }

    // MARK: Save panel

    /// Replaces the save panel's name (the extension is added by the panel).
    func setSaveName(_ name: String) throws {
        let panel = try panel(.save)
        let field = try exactlyOne(panel.textFields.matching(identifier: SystemLabels.saveNameField),
                                   SystemLabels.saveNameField, step: .panel)
        try sample.waitUntil("the name field taking the focus", timeout: SampleApp.systemUITimeout, step: .keyFocus) {
            sample.hasKeyboardFocus(field) == true
        }
        try sample.guardedTypeKey("a", modifiers: .command, to: field, focused: field, name: SystemLabels.saveNameField)
        try sample.guardedTypeText(name, into: field, name: SystemLabels.saveNameField)
    }

    /// The replace confirmation of the save panel (`Replace`), counted without waiting.
    var replaceButtonCount: Int {
        app.buttons.matching(NSPredicate(format: "label IN %@ OR title IN %@", SystemLabels.replace, SystemLabels.replace)).count
    }

    /// Waits for the replace confirmation and presses `Replace` (exactly one).
    func confirmReplace() throws {
        let query = app.buttons.matching(NSPredicate(format: "label IN %@ OR title IN %@", SystemLabels.replace, SystemLabels.replace))
        let replace = try sample.waitForExactlyOne(query, "Replace", timeout: SampleApp.systemUITimeout, step: .panel)
        try sample.guardedClick(replace, .panel, name: "Replace")
    }

    // MARK: Buttons

    /// The panel's default button (`OKButton`: Open, Choose or Save).
    func confirm(_ kind: Kind) throws {
        let ok = try exactlyOne(try panel(kind).buttons.matching(identifier: SystemLabels.okButton),
                                SystemLabels.okButton, step: .panel)
        try sample.waitUntil("\(SystemLabels.okButton) being enabled", timeout: SampleApp.systemUITimeout, step: .panel) {
            ok.isEnabled
        }
        try sample.guardedClick(ok, .panel, name: SystemLabels.okButton)
    }

    func cancel(_ kind: Kind) throws {
        let cancel = try exactlyOne(try panel(kind).buttons.matching(identifier: SystemLabels.cancelButton),
                                    SystemLabels.cancelButton, step: .panel)
        try sample.guardedClick(cancel, .panel, name: SystemLabels.cancelButton)
    }
}
