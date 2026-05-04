//
//  NotificationRepository.swift
//  IosLibrary
//

import Foundation
import UserNotifications

/// Defines the contract for all notification operations.
/// Implemented by `NotificationRepositoryImpl` in the Data layer.
public protocol NotificationRepository {

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
    /// - Parameter options: The authorization options to request.
    /// - Returns: `true` if the user granted permission.
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
    func getScheduled() async -> [UNNotificationRequest]

    /// Returns all notifications currently visible in Notification Center.
    func getDelivered() async -> [ActiveNotification]

    /// Returns the current notification authorization status.
    func authorizationStatus() async -> UNAuthorizationStatus

    /// Opens the app's notification settings page in the Settings app.
    func openNotificationSettings()

    /// Registers a notification category with the notification center.
    /// - Parameter category: The category to register.
    func registerCategory(_ category: NotificationCategory) async

    /// Removes a registered notification category.
    /// - Parameter identifier: The identifier of the category to remove.
    func removeCategory(identifier: String) async
}
