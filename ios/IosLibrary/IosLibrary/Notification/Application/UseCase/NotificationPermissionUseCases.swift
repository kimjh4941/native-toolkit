//
//  NotificationPermissionUseCases.swift
//  IosLibrary
//

import Foundation
import os
// `UNAuthorizationOptions` only: the port's one platform type, passed through as it is (see the
// note on `NotificationRepository`).
import UserNotifications

private let requestLogger = Logger(subsystem: "com.jonghyunkim.nativetoolkit.IosLibrary", category: "RequestNotificationPermissionUseCase")
private let openSettingsLogger = Logger(subsystem: "com.jonghyunkim.nativetoolkit.IosLibrary", category: "OpenNotificationSettingsUseCase")

/// Requests authorization to display notifications and tells whether it was granted.
///
/// A denial is `false`, not an error. Whether the app must be in the foreground first is not
/// decided here (design 8.5.4, SR-17): the presentation gate of `IosNotificationManager`
/// (`NotificationPresentationGate`) decides it before calling this.
public struct RequestNotificationPermissionUseCase: Sendable {
    private let repository: NotificationRepository

    public init(repository: NotificationRepository) {
        requestLogger.log(level: .libraryDebug, "[init] repository: \(String(describing: type(of: repository)), privacy: .public)")
        self.repository = repository
    }

    /// - Parameter options: The authorization options to request.
    /// - Returns: `true` if the user granted permission, `false` if the user denied it.
    /// - Throws: ``NotificationError``: what the repository threw when it is one, otherwise
    ///   ``NotificationError/authorizationFailed(_:)`` with the error's domain and code.
    public func execute(options: UNAuthorizationOptions) async throws(NotificationError) -> Bool {
        requestLogger.log(level: .libraryDebug, "[execute] options: \(options.rawValue, privacy: .public)")
        do {
            return try await repository.requestPermission(options: options)
        } catch let error as NotificationError {
            throw error
        } catch {
            requestLogger.error("[execute] the repository threw an error that is not a NotificationError: \(LogRedaction.describe(error), privacy: .public)")
            throw .authorizationFailed(FailureDetail(systemError: error))
        }
    }
}

/// Opens the app's notification settings page in the Settings app and tells whether it opened.
///
/// Whether the app must be in the foreground first is not decided here (design 8.5.5, SR-17).
public struct OpenNotificationSettingsUseCase: Sendable {
    private let repository: NotificationRepository

    public init(repository: NotificationRepository) {
        openSettingsLogger.log(level: .libraryDebug, "[init] repository: \(String(describing: type(of: repository)), privacy: .public)")
        self.repository = repository
    }

    /// - Returns: Whether the system opened the page.
    public func execute() async -> Bool {
        openSettingsLogger.log(level: .libraryDebug, "[execute]")
        return await repository.openNotificationSettings()
    }
}
