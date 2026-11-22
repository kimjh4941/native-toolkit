//
//  NotificationBadgeUseCases.swift
//  IosLibrary
//

import Foundation
import os

private let logger = Logger(subsystem: "com.jonghyunkim.nativetoolkit.IosLibrary", category: "SetBadgeCountUseCase")

/// Sets the app icon badge count.
public struct SetBadgeCountUseCase: Sendable {
    private let repository: NotificationRepository

    public init(repository: NotificationRepository) {
        logger.log(level: .libraryDebug, "[init] repository: \(String(describing: type(of: repository)), privacy: .public)")
        self.repository = repository
    }

    /// - Parameter count: The number to display. Pass 0 to clear the badge.
    /// - Throws: What the repository threw (``NotificationError/setBadgeCountFailed(_:)`` from
    ///   the library's repository).
    public func execute(_ count: Int) async throws {
        logger.log(level: .libraryDebug, "[execute] count: \(count, privacy: .public)")
        try await repository.setBadgeCount(count)
    }
}
