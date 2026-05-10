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
///
/// - Note: `UNAuthorizationOptions` is retained here as it is a thin bitmask with no
///   domain-level equivalent, and is also part of the Manager's public API.
public protocol NotificationRepository {
    // MARK: - Permission

    /// Requests notification authorization with the specified options.
    func requestAuthorization(
        options: UNAuthorizationOptions,
        completion: @escaping (Result<Bool, NotificationDomainError>) -> Void
    )

    /// Returns the current notification authorization status as a domain value.
    func getAuthorizationStatus(
        completion: @escaping (Result<NotificationAuthorizationStatus, NotificationDomainError>) -> Void
    )

    // MARK: - Add / Remove

    /// Adds a notification with the given domain content and trigger.
    func add(
        content: NotificationContent,
        trigger: NotificationTrigger,
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

    /// Returns all pending (scheduled) notifications as domain values.
    func getScheduled(
        completion: @escaping (Result<[ScheduledNotification], NotificationDomainError>) -> Void
    )

    /// Returns all delivered notifications as domain values.
    func getDelivered(
        completion: @escaping (Result<[ActiveNotification], NotificationDomainError>) -> Void
    )

    // MARK: - Category

    /// Registers the given notification categories, replacing the current set.
    func setCategories(_ categories: [NotificationCategory])

    // MARK: - Badge

    /// Sets the application badge count.
    func setBadgeCount(
        _ count: Int,
        completion: @escaping (Result<Void, NotificationDomainError>) -> Void
    )
}
