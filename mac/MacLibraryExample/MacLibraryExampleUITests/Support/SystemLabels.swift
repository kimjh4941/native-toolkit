//
//  SystemLabels.swift
//  MacLibraryExampleUITests
//
//  The one table of system UI identifiers and labels (UI test design U-2). System UI is found by
//  its identifier when it has one; otherwise by the labels below, in en (macOS 15.8.3 VM, stage
//  0c) and ja (not measured yet: U-30 takes them on the VM). `’` is U+2019.
//  Trusted Support file.
//

import Foundation

enum SystemLabels {

    // MARK: Processes

    /// Bundle identifier of the sample app.
    static let sampleBundleIdentifier = "com.jonghyunkim.mac.nativetoolkit.example"
    static let notificationCenterBundleIdentifier = "com.apple.notificationcenterui"
    /// The view service that may own a sandboxed app's open and save panels (design 5.0). On the
    /// macOS 15.8.3 VM the panels' windows belonged to the sample itself (stage 0c).
    static let openAndSavePanelServiceBundleIdentifier = "com.apple.appkit.xpc.openAndSavePanelService"
    static let mailBundleIdentifier = "com.apple.mail"
    static let finderBundleIdentifier = "com.apple.finder"
    static let systemSettingsBundleIdentifier = "com.apple.systempreferences"

    /// Owners of the full-display windows that sit in front of every app and take no click (macOS
    /// 15.8.3 VM, stage 0c: the automation mode overlay at layer 1000, Notification Center at 23,
    /// the Dock at 20, each exactly as large as the display). Only a window of these owners whose
    /// bounds equal a whole display is passed over by the overlay check (`OverlayRule`).
    static let passiveFullDisplayOwners: Set<String> = [
        "com.apple.dt.AutomationModeUI",
        notificationCenterBundleIdentifier,
        "com.apple.dock"
    ]

    // MARK: Sample window

    /// The toolbar's back button of the sample's `NavigationStack` (label `Back`).
    static let backButtonIdentifier = "chevron.backward"
    /// The window buttons (close, minimize, full screen) carry identifiers with this prefix.
    static let windowButtonPrefix = "_XCUI:"

    // MARK: Alert (`NSAlert`)

    /// `action-button-<n>` is the n-th button added to the alert (1-based), whatever its place on
    /// screen (macOS 15.8.3: OK is 1, Cancel 2, Delete 3; Delete is shown second).
    static func alertButtonIdentifier(_ number: Int) -> String { "action-button-\(number)" }
    /// The suppression checkbox (Apple's spelling).
    static let alertSuppressionCheckbox = "supression-checkbox"
    /// The alert's help button has no stable identifier (`_NS:<n>`), so it is found by its label.
    static let help = ["Help", "ヘルプ"]

    // MARK: Open and save panels

    static let openPanel = "open-panel"
    static let savePanel = "save-panel"
    static let okButton = "OKButton"
    static let cancelButton = "CancelButton"
    /// The sheet Cmd+Shift+G opens, and its path field.
    static let goToSheet = "GoToWindow"
    static let goToPathField = "PathTextField"
    /// The panel's location pop-up; its value is the name of the folder shown now.
    static let wherePopup = "where popup"
    static let saveNameField = "saveAsNameTextField"
    static let columnView = "ColumnView"
    /// The replace confirmation of the save panel.
    static let replace = ["Replace", "置き換える"]

    // MARK: Share picker

    /// Copy of the share picker (macOS 26 only; 15.8.3 has none. M-3).
    static let copy = ["Copy", "コピー"]
    /// The service the sample excludes in ShareExcludingServices (S10).
    static let addToReadingList = ["Add to Reading List", "リーディングリストに追加"]
    /// The service name the sample's result line shows after ShareViaMail (S11).
    static let mailServiceName = ["Mail", "メール"]

    // MARK: Notification Center (macOS 15.8.3 VM, stage 0c 2.3)

    /// Separator of the parts of a banner's label (`<app>, <title>, <subtitle>, <body>`). ja: not
    /// measured (U-30).
    static let notificationLabelSeparator = ", "
    /// The container of the banners in Notification Center's tree (identifier, no label).
    static let notificationListIdentifier = "AXNotificationListItems"
    /// The menu button a root shows on hover; it carries the text as its title (the label is empty).
    static let notificationOptions = ["Options", "オプション"]
    /// The start of the permission prompt's label (`“<app>” Notifications, Notifications may include
    /// alerts, sounds, and icon badges.`. Stage 0a 4.3). en only: the ja form is taken in U-30.
    static func permissionPromptPrefixes(appName: String) -> [String] {
        ["\u{201C}\(appName)\u{201D} Notifications"]
    }
    /// The items of the permission prompt's menu. `’` is U+2019.
    static let permissionAllow = ["Allow", "許可"]
    static let permissionDontAllow = ["Don\u{2019}t Allow", "許可しない"]

    // MARK: Clipboard screen

    /// The system `PasteButton` of the Clipboard screen: no identifier reaches the tree (its
    /// `NSViewRepresentable` container `clipboard.pasteButton` does not appear on 15.8.3. Stage 0b).
    static let paste = ["Paste", "ペースト"]
}
