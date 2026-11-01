//
//  NotificationCategoryUseCases.swift
//  IosLibrary
//

import Foundation
import os

private let registerLogger = Logger(subsystem: "com.jonghyunkim.nativetoolkit.IosLibrary", category: "RegisterNotificationCategoryUseCase")
private let removeLogger = Logger(subsystem: "com.jonghyunkim.nativetoolkit.IosLibrary", category: "RemoveNotificationCategoryUseCase")

/// Registers a notification category with the notification center.
public struct RegisterNotificationCategoryUseCase: Sendable {
    private let repository: NotificationRepository

    public init(repository: NotificationRepository) {
        registerLogger.log(level: .libraryDebug, "[init] repository: \(String(describing: type(of: repository)), privacy: .public)")
        self.repository = repository
    }

    public func execute(_ category: NotificationCategory) async {
        registerLogger.log(level: .libraryDebug, "[execute] identifier: \(category.identifier, privacy: .public)")
        await repository.registerCategory(category)
    }

    /// Queues the registration and returns at once; `completion` is called once it is applied
    /// (``NotificationRepository/enqueueCategoryChange(_:completion:)``, design S-P28).
    /// - Parameters:
    ///   - category: The category to register.
    ///   - completion: Called once, on any thread, after the category is registered.
    public func enqueue(_ category: NotificationCategory, completion: @escaping @Sendable () -> Void) {
        registerLogger.log(level: .libraryDebug, "[enqueue] identifier: \(category.identifier, privacy: .public), completion: provided")
        repository.enqueueCategoryChange(.register(category), completion: completion)
    }
}

/// Removes a registered notification category.
public struct RemoveNotificationCategoryUseCase: Sendable {
    private let repository: NotificationRepository

    public init(repository: NotificationRepository) {
        removeLogger.log(level: .libraryDebug, "[init] repository: \(String(describing: type(of: repository)), privacy: .public)")
        self.repository = repository
    }

    public func execute(identifier: String) async {
        removeLogger.log(level: .libraryDebug, "[execute] identifier: \(identifier, privacy: .public)")
        await repository.removeCategory(identifier: identifier)
    }

    /// Queues the removal and returns at once; `completion` is called once it is applied
    /// (``NotificationRepository/enqueueCategoryChange(_:completion:)``, design S-P28).
    /// - Parameters:
    ///   - identifier: The identifier of the category to remove.
    ///   - completion: Called once, on any thread, after the category is removed.
    public func enqueue(identifier: String, completion: @escaping @Sendable () -> Void) {
        removeLogger.log(level: .libraryDebug, "[enqueue] identifier: \(identifier, privacy: .public), completion: provided")
        repository.enqueueCategoryChange(.remove(identifier: identifier), completion: completion)
    }
}
