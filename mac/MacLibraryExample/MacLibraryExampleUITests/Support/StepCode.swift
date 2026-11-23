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
    /// The Clipboard screen's `PasteButton` was not found exactly once.
    case pasteButton
    /// The paste confirmation did not appear, did not close, was not found exactly once, or
    /// appeared when it should not.
    case pasteConfirmation
    /// Another app could not be stopped or read.
    case otherApp
    /// The interruption monitor stopped the test (U-8).
    case interrupted
    /// The identifier inventory did not match (I1).
    case inventory
    /// A precondition of the test does not hold (the text also carries `NTK-PRECONDITION:<name>`).
    case precondition
    /// The sample's banner root was not found exactly once, was replaced, or appeared when it
    /// should not (U-2, U-5).
    case notificationRoot
    /// The root's `Options`, the menu it opened or an item of that menu was not found exactly once.
    case notificationAction
    /// The reply field in the root was not found exactly once or had no keyboard focus.
    case notificationReply
    /// The sample was not in the state the scenario needs before a press in Notification Center.
    case notificationState
    /// The permission prompt did not appear, appeared when it should not, or its menu was not found.
    case permissionPrompt
    /// The list of `GetScheduled` / `GetDelivered` had another shape or did not reach the expected ids.
    case notificationList
    /// The clock did not reach the window of seconds before the deadline (U-14 (c)).
    case secondsWindow
    /// System Settings did not come to the front or did not stop.
    case settings
    /// A step of the cold start failed (stop, wake, timing).
    case coldStart
    /// `notification.lastEvent` had another shape or value.
    case lastEvent
    /// `notification.launchCopy` had another shape or value, or the runner gave no expected copy.
    case launchCopy
    /// Finder did not come to the front.
    case finder
}
