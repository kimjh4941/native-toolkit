//
//  NotificationRepository.swift
//  MacLibrary
//
//  Created by Kim Jong Hyun on 2026/05/09.
//
import UserNotifications

/// Port (interface) for all notification data operations.
///
/// Implementations must be thread-safe. All completion handlers are called on
/// an unspecified queue; callers are responsible for main-queue dispatch if needed.
public protocol NotificationRepository {
    // MARK: - Permission

    /// Requests notification authorization with the specified options.
    func requestAuthorization(
        options: UNAuthorizationOptions,
        completion: @escaping (Result<Bool, NotificationDomainError>) -> Void
    )

    /// Returns the current notification authorization settings.
    func getAuthorizationStatus(
        completion: @escaping (Result<UNNotificationSettings, NotificationDomainError>) -> Void
    )

    // MARK: - Add / Remove

    /// Adds a notification request.
    func add(
        request: UNNotificationRequest,
        completion: @escaping (Result<Void, NotificationDomainError>) -> Void
    )

    /// Removes pending notification requests for the given identifiers.
    func removePending(identifiers: [String])

    /// Removes all pending notification requests.
    func removeAllPending()

    /// Removes delivered notifications for the given identifiers.
    func removeDelivered(identifiers: [String])

    /// Removes all delivered notifications.
    func removeAllDelivered()

    // MARK: - Query

    /// Returns all pending notification requests.
    func getPendingRequests(
        completion: @escaping (Result<[UNNotificationRequest], NotificationDomainError>) -> Void
    )

    /// Returns all delivered notifications.
    func getDeliveredNotifications(
        completion: @escaping (Result<[UNNotification], NotificationDomainError>) -> Void
    )

    // MARK: - Category

    /// Registers the given set of notification categories.
    func setNotificationCategories(_ categories: Set<UNNotificationCategory>)

    // MARK: - Badge

    /// Sets the application badge count.
    func setBadgeCount(
        _ count: Int,
        completion: @escaping (Result<Void, NotificationDomainError>) -> Void
    )
}
