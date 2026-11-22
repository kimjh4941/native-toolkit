//
//  NavigationUITests.swift
//  MacLibraryExampleUITests
//
//  M1a, M1b and M2 of the UI test design (5.1). On macOS 15.8.3 the toolbar's back button does not
//  return to the menu when XCUITest presses it (9.0 2), so M1b and M2, which go back, run on macOS
//  26 only (`OS_ONLY_TESTS`, U-33); M1a opens each screen from a fresh launch.
//

import XCTest
import Foundation

final class NavigationUITests: SampleUITestCase {

    // MARK: - M1a

    /// Each screen opens from its menu card after a fresh launch. Opening the Clipboard screen only
    /// registers the paste button's receiver (5.1).
    @MainActor
    func testM1a_menuOpensEachScreen() throws {
        for screen in SampleScreen.allCases {
            let sample = try launchSample()
            XCTAssertTrue(sample.menuCardsShown, "the menu does not show the four cards")
            try sample.open(screen)
            XCTAssertTrue(sample.isShowing(screen), "the result line of \(screen) is not shown")
            if screen != .clipboard {
                XCTAssertEqual(try sample.result(screen), ShownResult(sequence: 0, text: ResultLine.initial))
            }
        }
    }

    // MARK: - M1b (macOS 26 only)

    @MainActor
    func testM1b_backReturnsToTheMenu() throws {
        let sample = try launchSample()
        for screen in SampleScreen.allCases {
            try sample.open(screen)
            try sample.goBack(from: screen)
            XCTAssertTrue(sample.menuCardsShown, "the menu does not show the four cards after leaving \(screen)")
        }
    }

    // MARK: - M2 (macOS 26 only)

    /// A screen opened again starts from its initial state (its state is `@State`). Share has no
    /// button that does nothing outside, so it is left out (5.1).
    @MainActor
    func testM2_reopenedScreensStartFromTheirInitialState() throws {
        let sample = try launchSample()
        let initial = ShownResult(sequence: 0, text: ResultLine.initial)

        try sample.open(.dialog)
        XCTAssertEqual(try sample.result(.dialog), initial)
        try sample.tap(.showDialog)
        let alert = sample.alert()
        try alert.waitShown()
        try alert.press(1)
        try sample.waitForNextResult(.dialog, after: 0, marker: DialogButton.showDialog.resultMarker)
        try sample.expectNoFurtherResult(.dialog, sequence: 1)
        try alert.waitGone()
        try sample.goBack(from: .dialog)
        try sample.open(.dialog)
        XCTAssertEqual(try sample.result(.dialog), initial)
        try sample.goBack(from: .dialog)

        // HasPermission only reads the state, so either answer is a change of the result line.
        try sample.open(.notification)
        XCTAssertEqual(try sample.result(.notification), initial)
        try sample.tap(.hasPermission)
        try sample.waitForNextResult(.notification, after: 0, marker: NotificationButton.hasPermission.resultMarker)
        try sample.expectNoFurtherResult(.notification, sequence: 1)
        try sample.goBack(from: .notification)
        try sample.open(.notification)
        XCTAssertEqual(try sample.result(.notification), initial)
    }
}
