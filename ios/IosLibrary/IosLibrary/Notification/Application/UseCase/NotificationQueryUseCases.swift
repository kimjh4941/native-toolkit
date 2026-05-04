//
//  NotificationQueryUseCases.swift
//  IosLibrary
//

import Foundation

/// Returns all notifications currently visible in Notification Center.
public struct GetDeliveredNotificationsUseCase {
    private let repository: NotificationRepository

    public init(repository: NotificationRepository) {
        self.repository = repository
    }

    public func execute() async -> [ActiveNotification] {
        await repository.getDelivered()
    }
}

/// Returns whether the app currently has notification authorization.
public struct HasNotificationPermissionUseCase {
    private let repository: NotificationRepository

    public init(repository: NotificationRepository) {
        self.repository = repository
    }

    /// - Returns: `true` if the current authorization status is `.authorized` or `.provisional`.
    public func execute() async -> Bool {
        let status = await repository.authorizationStatus()
        return status == .authorized || status == .provisional
    }
}

/// Returns the current notification authorization status.
public struct GetAuthorizationStatusUseCase {
    private let repository: NotificationRepository

    public init(repository: NotificationRepository) {
        self.repository = repository
    }

    public func execute() async -> NotificationAuthorizationStatus {
        await repository.authorizationStatus()
    }
}
