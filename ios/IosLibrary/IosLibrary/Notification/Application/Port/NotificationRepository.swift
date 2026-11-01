//
//  NotificationRepository.swift
//  IosLibrary
//

import Foundation
import os
// `UNAuthorizationOptions` only (`requestPermission(options:)`): the one platform type of this
// port, an allowed exception of common.md (a thin bit mask the system defines; a domain copy of
// its options would only be converted back). Every other parameter and result is a domain type.
import UserNotifications

private let logger = Logger(subsystem: "com.jonghyunkim.nativetoolkit.IosLibrary", category: "NotificationRepository")

/// Defines the contract for all notification operations.
/// Implemented by `NotificationRepositoryImpl` in the Data layer.
///
/// - Note: `requestPermission(options:)` takes the platform's `UNAuthorizationOptions`: a thin
///   bit mask whose domain copy would not be worth its conversion (the one exception to the rule
///   that a port uses domain types only).
///
/// Only the library's `NotificationRepositoryImpl` marks the requests it adds as the library's
/// (with the reserved userInfo key `com.jonghyunkim.nativetoolkit`), rejects a userInfo that uses
/// that key (``NotificationError/reservedUserInfoKey``) or holds a value that is not a
/// property-list value (``NotificationError/invalidUserInfo``), and removes the key from the lists
/// it returns. A request that an implementation of your own adds is not one of the library's
/// notifications: when another delegate was set before `IosNotificationManager.installDelegate()`
/// and implements the delegate method, the library forwards its presentation and its responses
/// to that delegate instead of handling them.
public protocol NotificationRepository: Sendable {

    // MARK: - Throwing operations (Apple API has error callback)

    /// Immediately delivers a notification.
    /// - Parameters:
    ///   - content: The content of the notification.
    ///   - trigger: The condition that triggers delivery, or nil for immediate delivery.
    func show(content: NotificationContent, trigger: NotificationTrigger?) async throws

    /// Updates an existing pending notification request.
    /// - Parameters:
    ///   - identifier: The identifier of the request to update.
    ///   - content: The new content.
    ///   - trigger: The new trigger condition.
    func update(identifier: String, content: NotificationContent, trigger: NotificationTrigger?) async throws

    /// Schedules a notification for future delivery.
    /// - Parameters:
    ///   - content: The content of the notification.
    ///   - trigger: The condition that triggers delivery.
    ///   - identifier: A unique identifier for the request.
    func schedule(content: NotificationContent, trigger: NotificationTrigger, identifier: String) async throws

    /// Requests authorization to display notifications.
    /// - Parameter options: The authorization options to request (`UNAuthorizationOptions`, the
    ///   port's one platform type; see the type's note).
    /// - Returns: `true` if the user granted permission, `false` if the user denied it.
    /// - Throws: The library's repository throws ``NotificationError/authorizationFailed(_:)``
    ///   when the request itself failed. `RequestNotificationPermissionUseCase` reports any other
    ///   error as `authorizationFailed` too.
    func requestPermission(options: UNAuthorizationOptions) async throws -> Bool

    /// Sets the app icon badge count.
    /// - Parameter count: The number to display. Pass 0 to clear the badge.
    func setBadgeCount(_ count: Int) async throws

    // MARK: - Non-throwing operations (Apple API is void-returning)

    /// Removes a pending (not yet delivered) notification request.
    /// - Parameter identifier: The identifier of the request to cancel.
    func cancel(identifier: String) async

    /// Removes all pending notification requests.
    func cancelAll() async

    /// Removes a specific delivered notification from Notification Center.
    /// - Parameter identifier: The identifier of the delivered notification.
    func removeDelivered(identifier: String) async

    /// Removes all delivered notifications from Notification Center.
    func removeAllDelivered() async

    /// Removes a specific scheduled notification request.
    /// - Parameter identifier: The identifier of the scheduled request.
    func cancelScheduled(identifier: String) async

    /// Removes all scheduled notification requests.
    func cancelAllScheduled() async

    /// Returns all pending notification requests (scheduled, not yet delivered).
    func getScheduled() async -> [ScheduledNotification]

    /// Returns all notifications currently visible in Notification Center.
    func getDelivered() async -> [ActiveNotification]

    /// Returns the current notification authorization status.
    func authorizationStatus() async -> NotificationAuthorizationStatus

    /// Opens the app's notification settings page in the Settings app.
    /// - Returns: Whether the system opened it (`UIApplication.open(_:)`).
    /// - Note: Before 2.0.0 this was `func openNotificationSettings()` and returned nothing.
    func openNotificationSettings() async -> Bool

    /// Registers a notification category with the notification center.
    ///
    /// The library's repository queues the change like
    /// ``enqueueCategoryChange(_:completion:)`` and returns once it is applied.
    /// - Parameter category: The category to register.
    func registerCategory(_ category: NotificationCategory) async

    /// Removes a registered notification category.
    ///
    /// The library's repository queues the change like
    /// ``enqueueCategoryChange(_:completion:)`` and returns once it is applied.
    /// - Parameter identifier: The identifier of the category to remove.
    func removeCategory(identifier: String) async

    /// Queues a change to the categories and returns at once; `completion` is called once the
    /// change is applied (design S-P28).
    ///
    /// The library's repository puts every change of the process in one first-in first-out
    /// queue, synchronously inside this call, and applies one change at a time (read the
    /// categories, change them, write them back, read them again): the changes take effect in the
    /// order of the calls, and one never undoes another. `completion` may be called on any
    /// thread.
    ///
    /// - Important: The default implementation, for a repository of your own, starts a task per
    ///   change that calls ``registerCategory(_:)`` or ``removeCategory(identifier:)`` and then
    ///   `completion`: the order of the changes is not kept.
    /// - Parameters:
    ///   - change: The category to register or the identifier to remove.
    ///   - completion: Called once, after the change is applied.
    func enqueueCategoryChange(_ change: NotificationCategoryChange, completion: @escaping @Sendable () -> Void)
}

extension NotificationRepository {
    /// The default for a repository of your own: a task per change, so the order is not kept
    /// (see the requirement's documentation).
    public func enqueueCategoryChange(_ change: NotificationCategoryChange, completion: @escaping @Sendable () -> Void) {
        logger.log(level: .libraryDebug, "[enqueueCategoryChange] change: \(change.logSummary, privacy: .public), completion: provided, implementation: default")
        Task {
            switch change {
            case .register(let category):
                await registerCategory(category)
            case .remove(let identifier):
                await removeCategory(identifier: identifier)
            }
            completion()
        }
    }
}
