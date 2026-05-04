//
//  NotificationScheduleUseCases.swift
//  IosLibrary
//

import Foundation
import UserNotifications

/// Schedules a notification for future delivery.
public struct ScheduleNotificationUseCase {
    private let repository: NotificationRepository

    public init(repository: NotificationRepository) {
        self.repository = repository
    }

    public func execute(content: NotificationContent, trigger: NotificationTrigger, identifier: String) async throws {
        try await repository.schedule(content: content, trigger: trigger, identifier: identifier)
    }
}

/// Cancels a specific scheduled notification.
public struct CancelScheduledNotificationUseCase {
    private let repository: NotificationRepository

    public init(repository: NotificationRepository) {
        self.repository = repository
    }

    public func execute(identifier: String) async {
        await repository.cancelScheduled(identifier: identifier)
    }
}

/// Cancels all scheduled notifications.
public struct CancelAllScheduledNotificationsUseCase {
    private let repository: NotificationRepository

    public init(repository: NotificationRepository) {
        self.repository = repository
    }

    public func execute() async {
        await repository.cancelAllScheduled()
    }
}

/// Returns all pending (scheduled, not yet delivered) notification requests.
public struct GetScheduledNotificationsUseCase {
    private let repository: NotificationRepository

    public init(repository: NotificationRepository) {
        self.repository = repository
    }

    public func execute() async -> [UNNotificationRequest] {
        await repository.getScheduled()
    }
}
