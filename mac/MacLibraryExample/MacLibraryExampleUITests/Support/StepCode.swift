//
//  StepCode.swift
//  MacLibraryExampleUITests
//
//  The vocabulary of `NTK-STEP:<step>` (UI test design 3.4). A failure thrown by the Support files
//  carries one of these codes, so that the runner can tell which step failed on this Mac without
//  showing the failure text. Only values of this enum may follow `NTK-STEP:`.
//  Trusted Support file.
//

import Foundation

enum StepCode: String, CaseIterable {
    /// The gate of the base class (declaration table, host, allowance, tokens).
    case gate
    /// The sample did not start, or its window is not on a display.
    case launch
    /// A menu card or a screen did not open.
    case openScreen
    /// The back button did not return to the menu.
    case goBack
    /// An element was not found exactly once (U-2).
    case elementNotUnique
    /// An element could not be scrolled inside its scroll view.
    case scroll
    /// The sample was not in the state the step needs (foreground).
    case notForeground
    /// The check before a press found another window over the point, or could not read the windows.
    case overlay
    /// A Notification Center window stayed over the element.
    case notificationOverlay
    /// The check before a key press found the wrong app in front or the wrong element focused.
    case keyFocus
    /// The result line did not show the expected next result.
    case resultTimeout
    /// The result line moved past the expected number (an extra completion).
    case extraResult
    /// The result line did not have the shape `#<n> <text>` or the marker of the operation.
    case resultShape
    /// An alert of the sample did not appear or close.
    case alert
    /// A panel did not appear, close, or move to the fixture.
    case panel
    /// The panel was not at the fixture when an item was to be chosen.
    case panelLocation
    /// The fixture folder given by the runner is missing or not of the expected shape.
    case fixture
    /// The share picker did not appear or close, or appeared when it should not.
    case picker
    /// The picker had no Copy (macOS 15 has none).
    case copyMissing
    /// The general pasteboard changed between the runner's write and the sample's read.
    case pasteboard
    /// Another app could not be stopped or read.
    case otherApp
    /// The interruption monitor stopped the test (U-8).
    case interrupted
    /// The identifier inventory did not match (I1).
    case inventory
}
