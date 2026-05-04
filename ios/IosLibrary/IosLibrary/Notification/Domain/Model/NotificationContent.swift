//
//  NotificationContent.swift
//  IosLibrary
//

import Foundation

/// The content of a local notification.
public struct NotificationContent {
    /// A unique identifier for the notification request.
    public let id: String
    /// The notification title.
    public let title: String
    /// The notification subtitle.
    public let subtitle: String?
    /// The notification body text.
    public let body: String?
    /// The number to display as the app badge. Use 0 to clear the badge.
    public let badge: Int?
    /// The sound to play when the notification is delivered.
    public let sound: NotificationSound?
    /// The identifier of the category for actionable notifications.
    public let categoryIdentifier: String?
    /// The interruption level that indicates how the system should alert the user.
    public let interruptionLevel: NotificationInterruptionLevel?
    /// An identifier for grouping related notifications into a thread.
    public let threadIdentifier: String?
    /// The identifier of the notification's content to show when the system condenses the thread.
    public let targetContentIdentifier: String?
    /// A score (0.0–1.0) indicating how relevant the notification is to the user.
    public let relevanceScore: Double?
    /// A filter criteria string used to match notifications in the notification list.
    public let filterCriteria: String?
    /// Custom data to deliver with the notification.
    public let userInfo: [String: Any]
    /// Media attachments to include with the notification.
    public let attachments: [NotificationAttachment]

    /// Creates notification content.
    public init(
        id: String,
        title: String,
        subtitle: String? = nil,
        body: String? = nil,
        badge: Int? = nil,
        sound: NotificationSound? = .default,
        categoryIdentifier: String? = nil,
        interruptionLevel: NotificationInterruptionLevel? = nil,
        threadIdentifier: String? = nil,
        targetContentIdentifier: String? = nil,
        relevanceScore: Double? = nil,
        filterCriteria: String? = nil,
        userInfo: [String: Any] = [:],
        attachments: [NotificationAttachment] = []
    ) {
        self.id = id
        self.title = title
        self.subtitle = subtitle
        self.body = body
        self.badge = badge
        self.sound = sound
        self.categoryIdentifier = categoryIdentifier
        self.interruptionLevel = interruptionLevel
        self.threadIdentifier = threadIdentifier
        self.targetContentIdentifier = targetContentIdentifier
        self.relevanceScore = relevanceScore
        self.filterCriteria = filterCriteria
        self.userInfo = userInfo
        self.attachments = attachments
    }
}
