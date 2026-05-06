//
//  ScheduledNotification.swift
//  IosLibrary
//

import Foundation

/// A notification request that is pending delivery.
public struct ScheduledNotification {
    /// The unique identifier of the scheduled request.
    public let identifier: String
    /// The notification title.
    public let title: String
    /// The notification subtitle.
    public let subtitle: String?
    /// The notification body text.
    public let body: String?
    /// The category identifier associated with the request.
    public let categoryIdentifier: String
    /// Custom data that will be delivered with the notification.
    public let userInfo: [AnyHashable: Any]

    /// Creates a scheduled notification model.
    public init(
        identifier: String,
        title: String,
        subtitle: String?,
        body: String?,
        categoryIdentifier: String,
        userInfo: [AnyHashable: Any]
    ) {
        self.identifier = identifier
        self.title = title
        self.subtitle = subtitle
        self.body = body
        self.categoryIdentifier = categoryIdentifier
        self.userInfo = userInfo
    }
}
