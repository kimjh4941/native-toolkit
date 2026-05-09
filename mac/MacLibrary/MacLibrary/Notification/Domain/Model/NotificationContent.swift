//
//  NotificationContent.swift
//  MacLibrary
//
//  Created by Kim Jong Hyun on 2026/05/09.
//

/// The content payload for a local notification.
///
/// - Important: `id` must be 1–128 characters using only alphanumerics, `-`, or `_`.
///   `title` must be 1–128 characters. `body` is optional and must not exceed 1024 characters.
public struct NotificationContent {
    /// Unique identifier for the notification (1–128 chars, `[A-Za-z0-9\-_]`).
    public let id: String
    /// Short headline shown in the notification banner (1–128 chars).
    public let title: String
    /// Optional descriptive body text (0–1024 chars).
    public let body: String?
    /// Optional subtitle displayed below the title.
    public let subtitle: String?
    /// Optional data string passed through to action handlers.
    public let userInfo: [String: String]?
    /// Optional badge count override. `nil` means no change.
    public let badge: Int?

    public init(
        id: String,
        title: String,
        body: String? = nil,
        subtitle: String? = nil,
        userInfo: [String: String]? = nil,
        badge: Int? = nil
    ) {
        self.id = id
        self.title = title
        self.body = body
        self.subtitle = subtitle
        self.userInfo = userInfo
        self.badge = badge
    }
}
