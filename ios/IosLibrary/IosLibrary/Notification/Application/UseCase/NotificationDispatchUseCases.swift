//
//  NotificationDispatchUseCases.swift
//  IosLibrary
//

import Foundation
import os

private let showLogger = Logger(subsystem: "com.jonghyunkim.nativetoolkit.IosLibrary", category: "ShowNotificationUseCase")
private let updateLogger = Logger(subsystem: "com.jonghyunkim.nativetoolkit.IosLibrary", category: "UpdateNotificationUseCase")
private let cancelLogger = Logger(subsystem: "com.jonghyunkim.nativetoolkit.IosLibrary", category: "CancelNotificationUseCase")
private let cancelAllLogger = Logger(subsystem: "com.jonghyunkim.nativetoolkit.IosLibrary", category: "CancelAllNotificationsUseCase")
private let removeDeliveredLogger = Logger(subsystem: "com.jonghyunkim.nativetoolkit.IosLibrary", category: "RemoveDeliveredNotificationUseCase")
private let removeAllDeliveredLogger = Logger(subsystem: "com.jonghyunkim.nativetoolkit.IosLibrary", category: "RemoveAllDeliveredNotificationsUseCase")

/// Shows an immediate or triggered notification.
public struct ShowNotificationUseCase: Sendable {
    private let repository: NotificationRepository

    public init(repository: NotificationRepository) {
        showLogger.log(level: .libraryDebug, "[init] repository: \(String(describing: type(of: repository)), privacy: .public)")
        self.repository = repository
    }

    public func execute(content: NotificationContent, trigger: NotificationTrigger? = nil) async throws {
        showLogger.log(level: .libraryDebug, "[execute] content.id: \(content.id, privacy: .public), trigger: \(String(describing: trigger), privacy: .private)")
        try await repository.show(content: content, trigger: trigger)
    }
}

/// Updates an existing pending notification.
public struct UpdateNotificationUseCase: Sendable {
    private let repository: NotificationRepository

    public init(repository: NotificationRepository) {
        updateLogger.log(level: .libraryDebug, "[init] repository: \(String(describing: type(of: repository)), privacy: .public)")
        self.repository = repository
    }

    public func execute(identifier: String, content: NotificationContent, trigger: NotificationTrigger?) async throws {
        updateLogger.log(level: .libraryDebug, "[execute] identifier: \(identifier, privacy: .public), content.id: \(content.id, privacy: .public), trigger: \(String(describing: trigger), privacy: .private)")
        try await repository.update(identifier: identifier, content: content, trigger: trigger)
    }
}

/// Cancels a specific pending notification.
public struct CancelNotificationUseCase: Sendable {
    private let repository: NotificationRepository

    public init(repository: NotificationRepository) {
        cancelLogger.log(level: .libraryDebug, "[init] repository: \(String(describing: type(of: repository)), privacy: .public)")
        self.repository = repository
    }

    public func execute(identifier: String) async {
        cancelLogger.log(level: .libraryDebug, "[execute] identifier: \(identifier, privacy: .public)")
        await repository.cancel(identifier: identifier)
    }
}

/// Cancels all pending notifications.
public struct CancelAllNotificationsUseCase: Sendable {
    private let repository: NotificationRepository

    public init(repository: NotificationRepository) {
        cancelAllLogger.log(level: .libraryDebug, "[init] repository: \(String(describing: type(of: repository)), privacy: .public)")
        self.repository = repository
    }

    public func execute() async {
        cancelAllLogger.log(level: .libraryDebug, "[execute]")
        await repository.cancelAll()
    }
}

/// Removes a specific delivered notification from Notification Center.
public struct RemoveDeliveredNotificationUseCase: Sendable {
    private let repository: NotificationRepository

    public init(repository: NotificationRepository) {
        removeDeliveredLogger.log(level: .libraryDebug, "[init] repository: \(String(describing: type(of: repository)), privacy: .public)")
        self.repository = repository
    }

    public func execute(identifier: String) async {
        removeDeliveredLogger.log(level: .libraryDebug, "[execute] identifier: \(identifier, privacy: .public)")
        await repository.removeDelivered(identifier: identifier)
    }
}

/// Removes all delivered notifications from Notification Center.
public struct RemoveAllDeliveredNotificationsUseCase: Sendable {
    private let repository: NotificationRepository

    public init(repository: NotificationRepository) {
        removeAllDeliveredLogger.log(level: .libraryDebug, "[init] repository: \(String(describing: type(of: repository)), privacy: .public)")
        self.repository = repository
    }

    public func execute() async {
        removeAllDeliveredLogger.log(level: .libraryDebug, "[execute]")
        await repository.removeAllDelivered()
    }
}
