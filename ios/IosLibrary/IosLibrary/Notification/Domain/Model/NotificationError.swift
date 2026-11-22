//
//  NotificationError.swift
//  IosLibrary
//

import Foundation

/// Errors that can occur during notification operations.
///
/// Every case is stable: none carries an arbitrary system `Error`. A failed system API is
/// reported with the `NSError` domain and code of what the system reported (``FailureDetail``).
///
/// | Case | When |
/// |---|---|
/// | ``permissionDenied`` | The user denied the permission. Thrown by the deprecated `NotificationPermissionHelper`; the existing `requestPermission(options:completion:)` reports only its text, as the `errorMessage` with `false`; the other requests report a denial as `false` |
/// | ``attachmentLoadFailed(identifier:detail:)`` | An attachment of the content could not be created, or its file does not exist (or the process cannot see it). Only file URLs (`isFileURL`) are checked for the file; any other URL is left to the system as before |
/// | ``addRequestFailed(_:)`` | `show`, `update` or `schedule`: the system did not add the request |
/// | ``setBadgeCountFailed(_:)`` | The system did not set the badge count |
/// | ``authorizationFailed(_:)`` | The permission request itself failed |
/// | ``reservedUserInfoKey`` | `show`, `update` or `schedule`: the userInfo uses the library's reserved key |
/// | ``invalidUserInfo`` | `show`, `update` or `schedule`: the userInfo holds a value that is not a property-list value |
/// | ``invalidTrigger`` | `show`, `update` or `schedule`: the time interval of the trigger makes the system raise an exception (``NotificationTrigger/isValid``) |
/// | ``notForeground`` | A permission request (while the permission is not determined) or the settings page with `PresenterSelection.foreground` or `viewController(_:)`: the app is not in the foreground |
/// | ``openSettingsFailed`` | The system did not open the settings page |
/// | ``delegateNotInstalled`` | A listener or the launch response before ``IosNotificationManager/installDelegate()`` |
///
/// The texts of `errorDescription` are fixed English sentences without the values that were
/// passed in; the callback forms report them as their `errorMessage`.
public enum NotificationError: Error, Sendable, Equatable, LocalizedError {
    /// The user has denied notification permission.
    case permissionDenied
    /// An attachment could not be created from its file, or the file does not exist (or the
    /// process cannot see it). Only file URLs (`isFileURL`) are checked for the file; any other
    /// URL is left to the system as before (`update` may then have removed the pending request
    /// when `add` fails).
    /// - Parameters:
    ///   - identifier: The attachment's identifier (``NotificationAttachment/identifier``).
    ///   - detail: The `NSError` domain and code of the system error. A missing file is
    ///     `NSCocoaErrorDomain` and `NSFileReadNoSuchFileError`.
    case attachmentLoadFailed(identifier: String, detail: FailureDetail)
    /// Adding the notification request to the system failed.
    /// - Parameter detail: The `NSError` domain and code of the system error.
    case addRequestFailed(FailureDetail)
    /// Setting the app badge count failed.
    /// - Parameter detail: The `NSError` domain and code of the system error.
    case setBadgeCountFailed(FailureDetail)
    /// Requesting the notification permission failed (not a denial: the request itself failed).
    /// - Parameter detail: The `NSError` domain and code of the system error.
    case authorizationFailed(FailureDetail)
    /// The userInfo of `show`, `schedule` or `update` uses the key the library reserves for its
    /// own marker (`com.jonghyunkim.nativetoolkit`). Nothing was added, removed or replaced.
    case reservedUserInfoKey
    /// The userInfo of `show`, `schedule` or `update` holds a value that is not a property-list
    /// value (string, number, Boolean, date, data, array or dictionary with string keys).
    /// Nothing was added, removed or replaced.
    case invalidUserInfo
    /// The trigger of `show`, `schedule` or `update` is not valid (``NotificationTrigger/isValid``):
    /// the system would raise an exception, which ends the process. Nothing was added, removed or
    /// replaced.
    case invalidTrigger
    /// A permission request (while the permission is not determined yet) or the settings page
    /// was asked for with `PresenterSelection.foreground` or `viewController(_:)` while the app
    /// has no view controller in the foreground. No system prompt was shown.
    case notForeground
    /// The system did not open the app's notification settings page.
    case openSettingsFailed
    /// A listener was added to ``IosNotificationManager/responses`` or
    /// ``IosNotificationManager/settingsRequests``, or ``IosNotificationManager/launchResponse()``
    /// was called, before ``IosNotificationManager/installDelegate()`` installed the library's
    /// delegate in this process.
    case delegateNotInstalled

    /// A fixed English description of the case, without the values that were passed in.
    public var errorDescription: String? {
        switch self {
        case .permissionDenied:
            return "Notification permission was denied."
        case .attachmentLoadFailed:
            return "Failed to create a notification attachment."
        case .addRequestFailed:
            return "Failed to add the notification request."
        case .setBadgeCountFailed:
            return "Failed to set the badge count."
        case .authorizationFailed:
            return "Failed to request notification permission."
        case .reservedUserInfoKey:
            return "The userInfo uses the key the library reserves."
        case .invalidUserInfo:
            return "The userInfo holds a value that is not a property-list value."
        case .invalidTrigger:
            return "The time interval of the trigger is not valid."
        case .notForeground:
            return "The app is not in the foreground."
        case .openSettingsFailed:
            return "Failed to open the notification settings."
        case .delegateNotInstalled:
            return "The library's notification delegate is not installed. Call IosNotificationManager.installDelegate() first."
        }
    }
}
