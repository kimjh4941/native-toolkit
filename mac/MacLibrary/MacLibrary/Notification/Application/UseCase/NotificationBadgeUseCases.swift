//
//  NotificationBadgeUseCases.swift
//  MacLibrary
//
//  Created by Kim Jong Hyun on 2026/05/10.
//

/// Use cases for managing the application badge count.
public final class NotificationBadgeUseCases {

    private let TAG = "NotificationBadgeUseCases"
    private let repository: NotificationRepository

    public init(repository: NotificationRepository) {
        Log.d(TAG, "init")
        self.repository = repository
    }

    /// Sets the application badge count.
    ///
    /// - Parameters:
    ///   - count: Badge count in the range `0...9999`. Use `0` to clear.
    ///   - completion: Called with `.success` or `.failure(NotificationDomainError)`.
    public func setBadgeCount(
        _ count: Int,
        completion: @escaping (Result<Void, NotificationDomainError>) -> Void
    ) {
        Log.d(TAG, "setBadgeCount called with count: \(count)")
        repository.setBadgeCount(count, completion: completion)
    }
}
