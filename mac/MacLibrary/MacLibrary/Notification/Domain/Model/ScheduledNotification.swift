//
//  ScheduledNotification.swift
//  MacLibrary
//
//  Created by Kim Jong Hyun on 2026/05/09.
//
import UserNotifications

/// Represents a pending (not yet delivered) scheduled notification.
public struct ScheduledNotification {
    /// The unique identifier of the notification request.
    public let identifier: String
    /// The title of the notification.
    public let title: String
    /// The body text, if any.
    public let body: String?
    /// The trigger that determines when the notification fires, if any.
    public let trigger: UNNotificationTrigger?

    public init(identifier: String, title: String, body: String?, trigger: UNNotificationTrigger?) {
        self.identifier = identifier
        self.title = title
        self.body = body
        self.trigger = trigger
    }
}
