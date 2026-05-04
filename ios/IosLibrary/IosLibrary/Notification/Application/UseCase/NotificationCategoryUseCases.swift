//
//  NotificationCategoryUseCases.swift
//  IosLibrary
//

import Foundation

/// Registers a notification category with the notification center.
public struct RegisterNotificationCategoryUseCase {
    private let repository: NotificationRepository

    public init(repository: NotificationRepository) {
        self.repository = repository
    }

    public func execute(_ category: NotificationCategory) async {
        await repository.registerCategory(category)
    }
}

/// Removes a registered notification category.
public struct RemoveNotificationCategoryUseCase {
    private let repository: NotificationRepository

    public init(repository: NotificationRepository) {
        self.repository = repository
    }

    public func execute(identifier: String) async {
        await repository.removeCategory(identifier: identifier)
    }
}
