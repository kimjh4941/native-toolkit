//
//  NotificationDelegateInstallResult.swift
//  IosLibrary
//

import Foundation

/// The result of ``IosNotificationManager/installDelegate()``.
public enum NotificationDelegateInstallResult: Sendable {
    /// The library's delegate is `UNUserNotificationCenter.current().delegate` when the call
    /// returns (also when it already was).
    case installed
    /// The call was not on the main thread. Nothing was changed.
    case notMainThread
}
