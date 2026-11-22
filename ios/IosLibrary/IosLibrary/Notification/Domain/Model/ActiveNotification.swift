//
//  ActiveNotification.swift
//  IosLibrary
//

import Foundation
import os

private let logger = Logger(subsystem: "com.jonghyunkim.nativetoolkit.IosLibrary", category: "ActiveNotification")

/// A notification that has already been delivered to the device.
///
/// `Sendable` for the same reason as ``ScheduledNotification``: the userInfo is kept as a value
/// tree (``userInfoValues``), and ``userInfo`` builds the dictionary from it with Foundation
/// types, so it reads as before.
public struct ActiveNotification: Sendable {
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
    /// Custom data delivered with the notification, as a value tree, without the library's own
    /// key.
    public let userInfoValues: [String: NotificationUserInfoValue]

    /// Custom data delivered with the notification, without the library's own key.
    ///
    /// Built from ``userInfoValues`` on every read, with Foundation types (see
    /// ``ScheduledNotification/userInfo``).
    public var userInfo: [AnyHashable: Any] {
        NotificationUserInfoValue.foundationDictionary(userInfoValues)
    }

    /// Creates an active (delivered) notification.
    ///
    /// `userInfo` is converted into ``userInfoValues`` as in
    /// ``ScheduledNotification/init(identifier:title:subtitle:body:categoryIdentifier:userInfo:)``.
    public init(
        identifier: String,
        title: String,
        subtitle: String?,
        body: String?,
        categoryIdentifier: String,
        date: Date,
        userInfo: [AnyHashable: Any]
    ) {
        logger.log(level: .libraryDebug, "[init] identifier: \(identifier, privacy: .public), title: \(LogRedaction.length(title), privacy: .public), subtitle: \(LogRedaction.length(subtitle), privacy: .public), body: \(LogRedaction.length(body), privacy: .public), categoryIdentifier: \(categoryIdentifier, privacy: .public), date: \(date.timeIntervalSince1970, privacy: .public), userInfoKeys: \(userInfo.count, privacy: .public)")
        self.identifier = identifier
        self.title = title
        self.subtitle = subtitle
        self.body = body
        self.categoryIdentifier = categoryIdentifier
        self.date = date
        self.userInfoValues = NotificationUserInfoValue.tree(of: userInfo).values
    }
}
