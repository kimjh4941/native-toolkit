//
//  NotificationScheduleUseCases.swift
//  IosLibrary
//

import Foundation
import os

private let scheduleLogger = Logger(subsystem: "com.jonghyunkim.nativetoolkit.IosLibrary", category: "ScheduleNotificationUseCase")
private let cancelScheduledLogger = Logger(subsystem: "com.jonghyunkim.nativetoolkit.IosLibrary", category: "CancelScheduledNotificationUseCase")
private let cancelAllScheduledLogger = Logger(subsystem: "com.jonghyunkim.nativetoolkit.IosLibrary", category: "CancelAllScheduledNotificationsUseCase")
private let scheduledLogger = Logger(subsystem: "com.jonghyunkim.nativetoolkit.IosLibrary", category: "GetScheduledNotificationsUseCase")

/// Schedules a notification for future delivery.
public struct ScheduleNotificationUseCase: Sendable {
    private let repository: NotificationRepository

    public init(repository: NotificationRepository) {
        scheduleLogger.log(level: .libraryDebug, "[init] repository: \(String(describing: type(of: repository)), privacy: .public)")
        self.repository = repository
    }

    public func execute(content: NotificationContent, trigger: NotificationTrigger, identifier: String) async throws {
        scheduleLogger.log(level: .libraryDebug, "[execute] identifier: \(identifier, privacy: .public), content.id: \(content.id, privacy: .public), trigger: \(String(describing: trigger), privacy: .private)")
        try await repository.schedule(content: content, trigger: trigger, identifier: identifier)
    }
}

/// Cancels a specific scheduled notification.
public struct CancelScheduledNotificationUseCase: Sendable {
    private let repository: NotificationRepository

    public init(repository: NotificationRepository) {
        cancelScheduledLogger.log(level: .libraryDebug, "[init] repository: \(String(describing: type(of: repository)), privacy: .public)")
        self.repository = repository
    }

    public func execute(identifier: String) async {
        cancelScheduledLogger.log(level: .libraryDebug, "[execute] identifier: \(identifier, privacy: .public)")
        await repository.cancelScheduled(identifier: identifier)
    }
}

/// Cancels all scheduled notifications.
public struct CancelAllScheduledNotificationsUseCase: Sendable {
    private let repository: NotificationRepository

    public init(repository: NotificationRepository) {
        cancelAllScheduledLogger.log(level: .libraryDebug, "[init] repository: \(String(describing: type(of: repository)), privacy: .public)")
        self.repository = repository
    }

    public func execute() async {
        cancelAllScheduledLogger.log(level: .libraryDebug, "[execute]")
        await repository.cancelAllScheduled()
    }
}

/// Returns all pending (scheduled, not yet delivered) notification requests.
public struct GetScheduledNotificationsUseCase: Sendable {
    private let repository: NotificationRepository

    public init(repository: NotificationRepository) {
        scheduledLogger.log(level: .libraryDebug, "[init] repository: \(String(describing: type(of: repository)), privacy: .public)")
        self.repository = repository
    }

    public func execute() async -> [ScheduledNotification] {
        scheduledLogger.log(level: .libraryDebug, "[execute]")
        return await repository.getScheduled()
    }
}
