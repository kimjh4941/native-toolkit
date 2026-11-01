//
//  NotificationQueryUseCases.swift
//  IosLibrary
//

import Foundation
import os

private let deliveredLogger = Logger(subsystem: "com.jonghyunkim.nativetoolkit.IosLibrary", category: "GetDeliveredNotificationsUseCase")
private let hasPermissionLogger = Logger(subsystem: "com.jonghyunkim.nativetoolkit.IosLibrary", category: "HasNotificationPermissionUseCase")
private let statusLogger = Logger(subsystem: "com.jonghyunkim.nativetoolkit.IosLibrary", category: "GetAuthorizationStatusUseCase")

/// Returns all notifications currently visible in Notification Center.
public struct GetDeliveredNotificationsUseCase: Sendable {
    private let repository: NotificationRepository

    public init(repository: NotificationRepository) {
        deliveredLogger.log(level: .libraryDebug, "[init] repository: \(String(describing: type(of: repository)), privacy: .public)")
        self.repository = repository
    }

    public func execute() async -> [ActiveNotification] {
        deliveredLogger.log(level: .libraryDebug, "[execute]")
        return await repository.getDelivered()
    }
}

/// Returns whether the app currently has notification authorization.
public struct HasNotificationPermissionUseCase: Sendable {
    private let repository: NotificationRepository

    public init(repository: NotificationRepository) {
        hasPermissionLogger.log(level: .libraryDebug, "[init] repository: \(String(describing: type(of: repository)), privacy: .public)")
        self.repository = repository
    }

    /// - Returns: `true` if the current authorization status is `.authorized` or `.provisional`.
    public func execute() async -> Bool {
        hasPermissionLogger.log(level: .libraryDebug, "[execute]")
        let status = await repository.authorizationStatus()
        return status == .authorized || status == .provisional
    }
}

/// Returns the current notification authorization status.
public struct GetAuthorizationStatusUseCase: Sendable {
    private let repository: NotificationRepository

    public init(repository: NotificationRepository) {
        statusLogger.log(level: .libraryDebug, "[init] repository: \(String(describing: type(of: repository)), privacy: .public)")
        self.repository = repository
    }

    public func execute() async -> NotificationAuthorizationStatus {
        statusLogger.log(level: .libraryDebug, "[execute]")
        return await repository.authorizationStatus()
    }
}
