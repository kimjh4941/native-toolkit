//
//  NotificationDispatchUseCases.swift
//  IosLibrary
//

import Foundation
import UserNotifications

/// Shows an immediate or triggered notification.
public struct ShowNotificationUseCase {
    private let repository: NotificationRepository

    public init(repository: NotificationRepository) {
        self.repository = repository
    }

    public func execute(content: NotificationContent, trigger: NotificationTrigger? = nil) async throws {
        try await repository.show(content: content, trigger: trigger)
    }
}

/// Updates an existing pending notification.
public struct UpdateNotificationUseCase {
    private let repository: NotificationRepository

    public init(repository: NotificationRepository) {
        self.repository = repository
    }

    public func execute(identifier: String, content: NotificationContent, trigger: NotificationTrigger?) async throws {
        try await repository.update(identifier: identifier, content: content, trigger: trigger)
    }
}

/// Cancels a specific pending notification.
public struct CancelNotificationUseCase {
    private let repository: NotificationRepository

    public init(repository: NotificationRepository) {
        self.repository = repository
    }

    public func execute(identifier: String) async {
        await repository.cancel(identifier: identifier)
    }
}

/// Cancels all pending notifications.
public struct CancelAllNotificationsUseCase {
    private let repository: NotificationRepository

    public init(repository: NotificationRepository) {
        self.repository = repository
    }

    public func execute() async {
        await repository.cancelAll()
    }
}

/// Removes a specific delivered notification from Notification Center.
public struct RemoveDeliveredNotificationUseCase {
    private let repository: NotificationRepository

    public init(repository: NotificationRepository) {
        self.repository = repository
    }

    public func execute(identifier: String) async {
        await repository.removeDelivered(identifier: identifier)
    }
}

/// Removes all delivered notifications from Notification Center.
public struct RemoveAllDeliveredNotificationsUseCase {
    private let repository: NotificationRepository

    public init(repository: NotificationRepository) {
        self.repository = repository
    }

    public func execute() async {
        await repository.removeAllDelivered()
    }
}
