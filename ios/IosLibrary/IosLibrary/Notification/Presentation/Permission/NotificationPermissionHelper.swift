//
//  NotificationPermissionHelper.swift
//  IosLibrary
//

import Foundation
import UserNotifications

/// Helper for managing notification authorization.
public final class NotificationPermissionHelper {

    private let TAG = "NotificationPermissionHelper"

    /// Shared singleton instance.
    public static let shared = NotificationPermissionHelper()

    private let repository: NotificationRepository

    init(repository: NotificationRepository = NotificationRepositoryImpl()) {
        Log.d(TAG, "[init]")
        self.repository = repository
    }

    /// Requests authorization to display notifications.
    ///
    /// - Parameter options: The authorization options to request (default: alert, sound, badge, app notification settings).
    /// - Returns: `true` if the user granted permission.
    /// - Throws: `NotificationError.permissionDenied` if permission was denied,
    ///           or `NotificationError.unknown` for other failures.
    public func requestPermission(options: UNAuthorizationOptions = [.alert, .sound, .badge, .providesAppNotificationSettings]) async throws -> Bool {
        Log.d(TAG, "[requestPermission] options: \(options)")
        let granted = try await repository.requestPermission(options: options)
        if !granted {
            throw NotificationError.permissionDenied
        }
        return granted
    }

    /// Returns the current notification authorization status.
    public func authorizationStatus() async -> NotificationAuthorizationStatus {
        Log.d(TAG, "[authorizationStatus]")
        return await repository.authorizationStatus()
    }

    /// Opens the app's notification settings page in the Settings app.
    public func openNotificationSettings() {
        Log.d(TAG, "[openNotificationSettings]")
        repository.openNotificationSettings()
    }
}
