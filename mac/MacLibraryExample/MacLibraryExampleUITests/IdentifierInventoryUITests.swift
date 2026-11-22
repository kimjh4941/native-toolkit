//
//  IdentifierInventoryUITests.swift
//  MacLibraryExampleUITests
//
//  I1a〜I1d of the UI test design (5.1): every button of a screen carries an identifier of the
//  screen, and the identifiers equal the inventory of design 4.1 (set, count, no duplicates). One
//  side is collected from the running UI in one snapshot; the other is the copy of the sample's
//  enums in `SampleInventory`. The window buttons, the toolbar's back button, the scroll bars' page
//  areas and the Clipboard screen's `PasteButton` are excluded by name and counted.
//

import XCTest
import Foundation

final class IdentifierInventoryUITests: SampleUITestCase {

    private var sample: SampleApp!

    override func setUpAfterGate() throws {
        sample = try launchSample()
    }

    override func tearDownAfterGate() throws {
        sample = nil
    }

    @MainActor
    func testI1a_dialogIdentifiers() throws {
        try sample.open(.dialog)
        try assertInventory(.dialog)
    }

    @MainActor
    func testI1b_notificationIdentifiers() throws {
        try sample.open(.notification)
        try assertInventory(.notification)
    }

    @MainActor
    func testI1c_shareIdentifiers() throws {
        try sample.open(.share)
        try assertInventory(.share)
    }

    @MainActor
    func testI1d_clipboardIdentifiers() throws {
        try sample.open(.clipboard)
        try assertInventory(.clipboard)
    }

    // MARK: - Helpers

    @MainActor
    private func assertInventory(_ screen: SampleScreen) throws {
        let snapshot = try sample.inventorySnapshot(screen)

        // The excluded kinds, each with the count the window has.
        XCTAssertEqual(snapshot.windowButtons, 3, "window buttons (close, minimize, full screen)")
        XCTAssertEqual(snapshot.backButtons, 1, "the toolbar's back button")
        XCTAssertEqual(snapshot.pasteButtons, screen == .clipboard ? 1 : 0, "the Clipboard screen's PasteButton")

        // (1) Every remaining button has an identifier of this screen's buttons.
        let foreign = snapshot.buttons.filter { !$0.hasPrefix(screen.buttonPrefix) }
        XCTAssertEqual(foreign, [], "buttons without a \(screen.buttonPrefix) identifier (\"\" = no identifier)")

        // (2) The identifiers equal the inventory: same count, no duplicates, same set.
        let collected = snapshot.buttons
        let expected = SampleInventory.expectedButtons(screen)
        XCTAssertEqual(Set(expected).count, expected.count, "the inventory itself has duplicates")
        XCTAssertEqual(collected.count, expected.count, "number of buttons")
        XCTAssertEqual(Set(collected).count, collected.count, "duplicated identifiers: \(duplicates(collected))")
        XCTAssertEqual(Set(collected).subtracting(expected).sorted(), [], "identifiers not in the inventory")
        XCTAssertEqual(Set(expected).subtracting(collected).sorted(), [], "inventory identifiers not on the screen")

        // (3) The non-button identifiers of the screen are each present exactly once.
        let nonButtons = snapshot.identifiedNonButtons
        let expectedNonButtons = SampleInventory.expectedNonButtons(screen)
        XCTAssertEqual(nonButtons.count, expectedNonButtons.count, "number of non-button identifiers: \(nonButtons.sorted())")
        XCTAssertEqual(Set(nonButtons).count, nonButtons.count, "duplicated non-button identifiers: \(duplicates(nonButtons))")
        XCTAssertEqual(Set(nonButtons), Set(expectedNonButtons), "non-button identifiers")
    }

    private func duplicates(_ values: [String]) -> [String] {
        Dictionary(grouping: values, by: { $0 }).filter { $0.value.count > 1 }.keys.sorted()
    }
}
