//
//  IdentifierInventoryUITests.swift
//  IosLibraryExampleUITests
//
//  I1a〜I1d of the UI test design (3.1): every button of a screen carries an identifier of the
//  screen, and the identifiers match the inventory of design 5.1 exactly (set, count, no
//  duplicates). One side is collected from the running UI; the other is the inventory.
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
        try sample.openClipboard(try clipboardToken())
        try assertInventory(.clipboard)
    }

    // MARK: - Helpers

    @MainActor
    private func assertInventory(_ screen: SampleScreen) throws {
        let snapshot = try sample.inventorySnapshot(screen)

        // The navigation bar holds exactly one button, the back button, excluded explicitly. iOS 26
        // gives it the identifier `BackButton`; iOS 18 gives it none, so there it is known by its
        // label, the menu's title (the sample's own text, the same in every language).
        let bar = snapshot.navigationBarButtons
        XCTAssertEqual(bar.count, 1, "navigation bar buttons: \(bar.map(\.identifier))")
        XCTAssertEqual(bar.filter(isBackButton).count, 1,
                       "the navigation bar button is not the back button: \(bar.map(\.identifier)) (\"\" = no identifier)")

        // (1) Every remaining button has an identifier of this screen's buttons.
        let foreign = snapshot.buttons.filter { !$0.identifier.hasPrefix(screen.buttonPrefix) }
        XCTAssertEqual(foreign.map(\.identifier), [], "buttons without a \(screen.buttonPrefix) identifier (\"\" = no identifier)")

        // (2) The identifiers equal the inventory: same count, no duplicates, same set.
        let collected = snapshot.buttons.map(\.identifier)
        let expected = SampleInventory.expectedButtons(screen)
        XCTAssertEqual(Set(expected).count, expected.count, "the inventory itself has duplicates")
        XCTAssertEqual(collected.count, expected.count, "number of buttons")
        XCTAssertEqual(Set(collected).count, collected.count, "duplicated identifiers: \(duplicates(collected))")
        XCTAssertEqual(Set(collected).subtracting(expected).sorted(), [], "identifiers not in the inventory")
        XCTAssertEqual(Set(expected).subtracting(collected).sorted(), [], "inventory identifiers not on the screen")

        // (3) The non-button identifiers of the screen are each present exactly once.
        let nonButtons = snapshot.identifiedNonButtons.map(\.identifier)
        let expectedNonButtons = SampleInventory.expectedNonButtons(screen)
        XCTAssertEqual(nonButtons.count, expectedNonButtons.count, "number of non-button identifiers")
        XCTAssertEqual(Set(nonButtons).count, nonButtons.count, "duplicated non-button identifiers: \(duplicates(nonButtons))")
        XCTAssertEqual(Set(nonButtons), Set(expectedNonButtons), "non-button identifiers")
    }

    /// The back button: the identifier `BackButton` (iOS 26), or no identifier and the menu's title
    /// as its label (iOS 18).
    private func isBackButton(_ button: NavigationBarButton) -> Bool {
        button.identifier == "BackButton" || (button.identifier.isEmpty && button.label == "Main Menu")
    }

    private func duplicates(_ values: [String]) -> [String] {
        Dictionary(grouping: values, by: { $0 }).filter { $0.value.count > 1 }.keys.sorted()
    }
}
