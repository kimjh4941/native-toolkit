//
//  NotificationCategoryOptions.swift
//  IosLibrary
//

import Foundation

/// Options that determine the behavior of notifications in a category.
/// Domain-layer type; maps to UNNotificationCategoryOptions in the Data layer.
public struct NotificationCategoryOptions: OptionSet {
    public let rawValue: UInt

    public init(rawValue: UInt) {
        self.rawValue = rawValue
    }

    /// Sends a dismiss action when the user explicitly dismisses the notification.
    public static let customDismissAction = NotificationCategoryOptions(rawValue: 1 << 0)
    /// The category can be displayed in CarPlay.
    public static let allowInCarPlay = NotificationCategoryOptions(rawValue: 1 << 1)
    /// Shows the notification title even when previews are hidden by the user.
    public static let hiddenPreviewsShowTitle = NotificationCategoryOptions(rawValue: 1 << 2)
    /// Allows Siri to announce the notification over AirPods.
    public static let allowAnnouncement = NotificationCategoryOptions(rawValue: 1 << 3)
}
