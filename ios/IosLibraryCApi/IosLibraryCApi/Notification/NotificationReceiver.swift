//
//  NotificationReceiver.swift
//  IosLibraryCApi
//

import IosLibrary

/// What the functions of Notification.h do: the checks, the types, and the call to the library's public API.
enum NotificationReceiver {
    /// The main-thread check is `installDelegate()`'s own: it goes by the thread and never waits (part 1, 1.4).
    static func install() -> ntk_notification_error {
        CApiLog.notification.debug("[install]")
        VersionCheck.run()
        return error(for: IosNotificationManager.installDelegate())
    }

    static func error(for result: NotificationDelegateInstallResult) -> ntk_notification_error {
        CApiLog.notification.debug("[error] result: \(String(describing: result), privacy: .public)")
        switch result {
        case .installed:
            return ntk_notification_error(NTK_NOTIFICATION_ERROR_NONE)
        case .notMainThread:
            CApiLog.notification.error("[install] WRONG_THREAD: not on the main thread")
            return ntk_notification_error(NTK_NOTIFICATION_ERROR_WRONG_THREAD)
        @unknown default:
            CApiLog.notification.error("[install] UNKNOWN: \(String(describing: result), privacy: .public)")
            return ntk_notification_error(NTK_NOTIFICATION_ERROR_UNKNOWN)
        }
    }
}
