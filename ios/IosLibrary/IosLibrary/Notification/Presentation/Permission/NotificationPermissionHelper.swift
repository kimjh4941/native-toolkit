//
//  NotificationPermissionHelper.swift
//  IosLibrary
//

import Foundation
import os
import UserNotifications

private let logger = Logger(subsystem: "com.jonghyunkim.nativetoolkit.IosLibrary", category: "NotificationPermissionHelper")

/// Helper for managing notification authorization.
///
/// The helper is `Sendable` (it holds only an immutable `Sendable` repository) and may be called
/// from any thread.
public final class NotificationPermissionHelper: Sendable {

    /// Shared singleton instance.
    public static let shared = NotificationPermissionHelper()

    private let repository: NotificationRepository

    init(repository: NotificationRepository = NotificationRepositoryImpl()) {
        logger.log(level: .libraryDebug, "[init]")
        self.repository = repository
    }

    /// Requests authorization to display notifications.
    ///
    /// - Parameter options: The authorization options to request (default: alert, sound, badge, app notification settings).
    /// - Returns: `true` if the user granted permission.
    /// - Throws: `NotificationError.permissionDenied` if permission was denied,
    ///           or `NotificationError.unknown` for other failures.
    public func requestPermission(options: UNAuthorizationOptions = [.alert, .sound, .badge, .providesAppNotificationSettings]) async throws -> Bool {
        logger.log(level: .libraryDebug, "[requestPermission] options: \(options.rawValue, privacy: .public)")
        let granted = try await repository.requestPermission(options: options)
        if !granted {
            throw NotificationError.permissionDenied
        }
        return granted
    }

    /// Returns the current notification authorization status.
    public func authorizationStatus() async -> NotificationAuthorizationStatus {
        logger.log(level: .libraryDebug, "[authorizationStatus]")
        return await repository.authorizationStatus()
    }

    /// Opens the app's notification settings page in the Settings app.
    public func openNotificationSettings() {
        logger.log(level: .libraryDebug, "[openNotificationSettings]")
        repository.openNotificationSettings()
    }
}
