//
//  ScheduledNotification.swift
//  IosLibrary
//

import Foundation
import os

private let logger = Logger(subsystem: "com.jonghyunkim.nativetoolkit.IosLibrary", category: "ScheduledNotification")

/// A notification request that is pending delivery.
///
/// `Sendable`: the userInfo is kept as a value tree (``userInfoValues``), so a list can be
/// returned from the `async` forms and handed between threads. ``userInfo`` builds the
/// dictionary from that tree with Foundation types, so it reads as before (`as? Int`,
/// `as? Double`, `as? Bool`, `as? String`, `as? Date`, `as? Data`, `as? [Any]`,
/// `as? [String: Any]`).
public struct ScheduledNotification: Sendable {
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
    /// Custom data that will be delivered with the notification, as a value tree, without the
    /// library's own key.
    public let userInfoValues: [String: NotificationUserInfoValue]

    /// Custom data that will be delivered with the notification, without the library's own key.
    ///
    /// Built from ``userInfoValues`` on every read, with Foundation types (`NSString`,
    /// `NSNumber`, `NSDate`, `NSData`, `NSArray`, `NSDictionary`; a Boolean is a `CFBoolean`).
    public var userInfo: [AnyHashable: Any] {
        NotificationUserInfoValue.foundationDictionary(userInfoValues)
    }

    /// Creates a scheduled notification model.
    ///
    /// `userInfo` is converted into ``userInfoValues``. A key that is not a `String` and a value
    /// that is not a property-list value (the system never stores one) are left out; the number
    /// left out is logged, never the keys or the values.
    public init(
        identifier: String,
        title: String,
        subtitle: String?,
        body: String?,
        categoryIdentifier: String,
        userInfo: [AnyHashable: Any]
    ) {
        logger.log(level: .libraryDebug, "[init] identifier: \(identifier, privacy: .public), title: \(LogRedaction.length(title), privacy: .public), subtitle: \(LogRedaction.length(subtitle), privacy: .public), body: \(LogRedaction.length(body), privacy: .public), categoryIdentifier: \(categoryIdentifier, privacy: .public), userInfoKeys: \(userInfo.count, privacy: .public)")
        self.identifier = identifier
        self.title = title
        self.subtitle = subtitle
        self.body = body
        self.categoryIdentifier = categoryIdentifier
        self.userInfoValues = NotificationUserInfoValue.tree(of: userInfo).values
    }
}
