//
//  NotificationError.swift
//  IosLibrary
//

import Foundation

/// Errors that can occur during notification operations.
public enum NotificationError: Error {
    /// The user has denied notification permission.
    case permissionDenied
    /// Notification permission has not been requested yet.
    case permissionNotDetermined
    /// The attachment URL is invalid or inaccessible.
    case attachmentInvalidURL
    /// The attachment could not be loaded.
    /// - Parameter error: The underlying system error.
    case attachmentLoadFailed(Error)
    /// Adding the notification request to the system failed.
    /// - Parameter error: The underlying system error.
    case addRequestFailed(Error)
    /// Setting the app badge count failed.
    /// - Parameter error: The underlying system error.
    case setBadgeCountFailed(Error)
    /// An unknown error occurred.
    /// - Parameter error: The underlying system error.
    case unknown(Error)
    /// The userInfo of `show`, `schedule` or `update` uses the key the library reserves for its
    /// own marker (`com.jonghyunkim.nativetoolkit`). Nothing was added, removed or replaced.
    case reservedUserInfoKey
    /// A listener was added to ``IosNotificationManager/responses`` or
    /// ``IosNotificationManager/settingsRequests``, or ``IosNotificationManager/launchResponse()``
    /// was called, before ``IosNotificationManager/installDelegate()`` installed the library's
    /// delegate in this process.
    case delegateNotInstalled
}
