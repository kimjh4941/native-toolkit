//
//  ScheduledNotification.swift
//  MacLibrary
//
//  Created by Kim Jong Hyun on 2026/05/09.
//

/// Represents a pending (not yet delivered) scheduled notification.
public struct ScheduledNotification {
    /// The unique identifier of the notification request.
    public let identifier: String
    /// The title of the notification.
    public let title: String
    /// The body text, if any.
    public let body: String?
    /// The domain trigger, if any. `nil` for immediate notifications.
    public let trigger: NotificationTrigger?

    public init(identifier: String, title: String, body: String?, trigger: NotificationTrigger?) {
        self.identifier = identifier
        self.title = title
        self.body = body
        self.trigger = trigger
    }
}
