//
//  NotificationQueryUseCases.swift
//  MacLibrary
//
//  Created by Kim Jong Hyun on 2026/05/09.
//
import Foundation

/// Use cases for querying and removing delivered notifications.
public final class NotificationQueryUseCases {

    private let TAG = "NotificationQueryUseCases"
    private let repository: NotificationRepository

    public init(repository: NotificationRepository) {
        Log.d(TAG, "init")
        self.repository = repository
    }

    // MARK: - Use Cases

    /// Returns all delivered (already shown) notifications.
    ///
    /// - Parameter completion: Called with the list of active notifications or a domain error.
    public func getDelivered(
        completion: @escaping (Result<[ActiveNotification], NotificationDomainError>) -> Void
    ) {
        Log.d(TAG, "getDelivered called")
        repository.getDeliveredNotifications { result in
            switch result {
            case .failure(let e):
                completion(.failure(e))
            case .success(let notifications):
                let active = notifications.map {
                    ActiveNotification(
                        identifier: $0.request.identifier,
                        title: $0.request.content.title,
                        body: $0.request.content.body.isEmpty ? nil : $0.request.content.body,
                        date: $0.date
                    )
                }
                completion(.success(active))
            }
        }
    }

    /// Removes a delivered notification by identifier.
    ///
    /// - Parameter identifier: The notification identifier to remove.
    public func removeDelivered(identifier: String) {
        Log.d(TAG, "removeDelivered called with identifier: \(identifier)")
        repository.removeDelivered(identifiers: [identifier])
    }

    /// Removes all delivered notifications.
    public func removeAllDelivered() {
        Log.d(TAG, "removeAllDelivered called")
        repository.removeAllDelivered()
    }
}
