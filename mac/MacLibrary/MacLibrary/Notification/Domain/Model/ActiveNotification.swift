//
//  ActiveNotification.swift
//  MacLibrary
//
//  Created by Kim Jong Hyun on 2026/05/09.
//
import Foundation

/// Represents a delivered (already shown) notification.
public struct ActiveNotification {
    /// The unique identifier of the notification.
    public let identifier: String
    /// The title that was displayed.
    public let title: String
    /// The body text that was displayed, if any.
    public let body: String?
    /// The date the notification was delivered.
    public let date: Date

    public init(identifier: String, title: String, body: String?, date: Date) {
        self.identifier = identifier
        self.title = title
        self.body = body
        self.date = date
    }
}
