//
//  SystemLabels.swift
//  IosLibraryExampleUITests
//
//  The one table of system UI labels (UI test design U-2). System UI without an identifier is
//  found by these labels in both en (iOS 26.2 simulator) and ja (the device). `’` is U+2019.
//  Trusted Support file.
//

import Foundation

enum SystemLabels {

    /// Display name of the sample.
    static let sampleDisplayName = "IosLibraryExample"

    /// The display name as system alerts quote it. A system alert may be answered by the
    /// interruption monitor only when its label contains this (U-8 (a)). Anchored by the quotes
    /// because the test runner's name `IosLibraryExampleUITests-Runner` contains the bare name
    /// (en, iOS 26.2 simulator: `“IosLibraryExample” Would Like to Send You Notifications`,
    /// `“IosLibraryExample” would like to paste from “IosLibraryExampleUITests-Runner”`).
    static let quotedSampleDisplayName = "“IosLibraryExample”"

    static let springboardBundleIdentifier = "com.apple.springboard"

    /// Bundle identifier of the sample app.
    static let sampleBundleIdentifier = "com.jonghyunkim.ios.nativetoolkit.example"

    // Permission and paste alerts
    static let allow = ["Allow", "許可"]
    static let dontAllow = ["Don’t Allow", "許可しない"]
    static let allowPaste = ["Allow Paste", "ペーストを許可"]
    static let dontAllowPaste = ["Don’t Allow Paste", "ペーストを許可しない"]
    static let notNow = ["Not Now", "今はしない"]
    static let cancel = ["Cancel", "キャンセル"]

    // Share sheet and Files
    static let copy = ["Copy", "コピー"]
    static let saveToFiles = ["Save to Files", "“ファイル”に保存", "\"ファイル\"に保存"]
    static let save = ["Save", "保存"]
    static let close = ["Close", "閉じる"]
    static let keepBoth = ["Keep Both", "両方とも残す"]
    static let onMyIPhone = ["On My iPhone", "このiPhone内"]
    static let browse = ["Browse", "ブラウズ"]

    // Identifiers of system UI (no label needed)
    static let notificationShortLook = "NotificationShortLookView"
    static let popoverDismissRegion = "PopoverDismissRegion"
    static let activityContentView = "UIActivityContentView"
    /// Elements that mark an open share sheet (see `ShareSheet.waitOpen`).
    static let shareSheetMarkers = [activityContentView, "ActivityListView"]
    /// The Files picker (Save to Files): its navigation bar and the browsing root of On My iPhone
    /// (iOS 26.2).
    static let filesPickerNavigationBar = "FullDocumentManagerViewControllerNavigationBar"
    static let localStorageBrowsingRoot = "DOC.browsingRoot Source: com.apple.FileProvider.LocalStorage"
    /// The share sheet header's title (`LPLinkView` caption, iOS 26.2).
    static let shareHeaderTitle = "LP.CaptionBar.TopCaption"
    /// The expanded (long-pressed) notification and its content button (iOS 26.2, stage 0c).
    static let notificationExpandedView = "notification-expanded-view"
    static let expandedContent = "ShortLook.Platter.Content.Seamless"

    /// Negative buttons the monitor may press on an alert of the sample when the test declares
    /// `systemui` (U-8 (a)).
    static var systemNegativeButtons: [String] { dontAllow + notNow + cancel }

    /// Negative buttons the monitor may press on an alert of the sample when the test declares
    /// `clipboard` (the paste alert).
    static var pasteNegativeButtons: [String] { dontAllowPaste }
}
