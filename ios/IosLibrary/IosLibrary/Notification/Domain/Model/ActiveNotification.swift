//
//  ActiveNotification.swift
//  IosLibrary
//

import Foundation

/// A notification that has already been delivered to the device.
public struct ActiveNotification {
    /// The unique identifier of the notification request.
    public let identifier: String
    /// The notification title.
    public let title: String
    /// The notification subtitle.
    public let subtitle: String?
    /// The notification body text.
    public let body: String?
    /// The category identifier associated with the notification.
    public let categoryIdentifier: String
    /// The date and time when the notification was delivered.
    public let date: Date
    /// Custom data delivered with the notification.
    public let userInfo: [AnyHashable: Any]

    /// Creates an active (delivered) notification.
    public init(
        identifier: String,
        title: String,
        subtitle: String?,
        body: String?,
        categoryIdentifier: String,
        date: Date,
        userInfo: [AnyHashable: Any]
    ) {
        self.identifier = identifier
        self.title = title
        self.subtitle = subtitle
        self.body = body
        self.categoryIdentifier = categoryIdentifier
        self.date = date
        self.userInfo = userInfo
    }
}
