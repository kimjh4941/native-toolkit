//
//  UnityIosNotificationManager.swift
//  UnityIosPlugin
//

import Foundation
import IosLibrary

/// # UnityIosNotificationManager
///
/// Swift façade exposing notification APIs to Unity via the Objective-C bridge (`UnityIosNotificationManagerBridge`).
/// Internally delegates to `IosNotificationManager` and normalizes callback signatures for C# interop.
///
/// ## Overview
/// * Provides a singleton: `shared`.
/// * All callbacks use `(isSuccess: Bool, errorMessage: String?)` semantics.
/// * JSON parsing is handled by `UnityIosNotificationJsonParser`.
///
/// ## Threading
/// Safe to call from any thread; work is dispatched internally.
@objcMembers
public class UnityIosNotificationManager: NSObject {

    private let TAG = "UnityIosNotificationManager"

    /// Shared singleton instance used by the Objective-C bridge.
    public static let shared = UnityIosNotificationManager()

    private let parser = UnityIosNotificationJsonParser()

    private override init() {
        Log.d(TAG, "[init]")
        super.init()
    }

    /// Registers `IosNotificationManager` as the `UNUserNotificationCenterDelegate`.
    /// Call once at app launch.
    public func setup() {
        Log.d(TAG, "[setup]")
        IosNotificationManager.setup()
    }

    /// Immediately shows a notification from a JSON content string.
    /// - Parameters:
    ///   - contentJson: JSON string for `NotificationContent`.
    ///   - triggerJson: JSON string for `NotificationTrigger`, or nil for immediate delivery.
    ///   - completion: `(isSuccess, errorMessage)`.
    public func showNotification(contentJson: String, triggerJson: String?, completion: ((Bool, String?) -> Void)?) {
        Log.d(TAG, "[showNotification] contentJson: \(contentJson), triggerJson: \(triggerJson ?? "nil")")
        guard let content = parser.parseContent(from: contentJson) else {
            completion?(false, "Failed to parse notification content JSON")
            return
        }
        let trigger = parser.parseTrigger(from: triggerJson)
        IosNotificationManager.shared.show(content: content, trigger: trigger, completion: completion)
    }

    /// Schedules a notification from JSON strings.
    public func scheduleNotification(contentJson: String, triggerJson: String, identifier: String, completion: ((Bool, String?) -> Void)?) {
        Log.d(TAG, "[scheduleNotification] identifier: \(identifier)")
        guard let content = parser.parseContent(from: contentJson),
              let trigger = parser.parseTrigger(from: triggerJson)
        else {
            completion?(false, "Failed to parse notification content or trigger JSON")
            return
        }
        IosNotificationManager.shared.schedule(content: content, trigger: trigger, identifier: identifier, completion: completion)
    }

    /// Updates an existing pending notification.
    public func updateNotification(identifier: String, contentJson: String, triggerJson: String?, completion: ((Bool, String?) -> Void)?) {
        Log.d(TAG, "[updateNotification] identifier: \(identifier)")
        guard let content = parser.parseContent(from: contentJson) else {
            completion?(false, "Failed to parse notification content JSON")
            return
        }
        let trigger = parser.parseTrigger(from: triggerJson)
        IosNotificationManager.shared.update(identifier: identifier, content: content, trigger: trigger, completion: completion)
    }

    /// Cancels a specific pending notification.
    public func cancelNotification(identifier: String) {
        Log.d(TAG, "[cancelNotification] identifier: \(identifier)")
        IosNotificationManager.shared.cancel(identifier: identifier)
    }

    /// Cancels all pending notifications.
    public func cancelAllNotifications() {
        Log.d(TAG, "[cancelAllNotifications]")
        IosNotificationManager.shared.cancelAll()
    }

    /// Removes a specific delivered notification from Notification Center.
    public func removeDeliveredNotification(identifier: String) {
        Log.d(TAG, "[removeDeliveredNotification] identifier: \(identifier)")
        IosNotificationManager.shared.removeDelivered(identifier: identifier)
    }

    /// Removes all delivered notifications from Notification Center.
    public func removeAllDeliveredNotifications() {
        Log.d(TAG, "[removeAllDeliveredNotifications]")
        IosNotificationManager.shared.removeAllDelivered()
    }

    /// Cancels a specific scheduled notification.
    public func cancelScheduledNotification(identifier: String) {
        Log.d(TAG, "[cancelScheduledNotification] identifier: \(identifier)")
        IosNotificationManager.shared.cancelScheduled(identifier: identifier)
    }

    /// Cancels all scheduled notifications.
    public func cancelAllScheduledNotifications() {
        Log.d(TAG, "[cancelAllScheduledNotifications]")
        IosNotificationManager.shared.cancelAllScheduled()
    }

    /// Returns all pending notification requests as a JSON string.
    public func getScheduledNotifications(completion: @escaping (String) -> Void) {
        Log.d(TAG, "[getScheduledNotifications]")
        IosNotificationManager.shared.getScheduled { notifications in
            let array: [[String: Any]] = notifications.map { n in
                var dict: [String: Any] = [
                    "identifier": n.identifier,
                    "title": n.title,
                    "categoryIdentifier": n.categoryIdentifier
                ]
                if let subtitle = n.subtitle { dict["subtitle"] = subtitle }
                if let body = n.body { dict["body"] = body }
                return dict
            }
            let json = (try? JSONSerialization.data(withJSONObject: array))
                .flatMap { String(data: $0, encoding: .utf8) } ?? "[]"
            completion(json)
        }
    }

    /// Returns all delivered notifications as a JSON string.
    public func getDeliveredNotifications(completion: @escaping (String) -> Void) {
        Log.d(TAG, "[getDeliveredNotifications]")
        IosNotificationManager.shared.getDelivered { notifications in
            let array: [[String: Any]] = notifications.map { n in
                var dict: [String: Any] = [
                    "identifier": n.identifier,
                    "title": n.title,
                    "categoryIdentifier": n.categoryIdentifier,
                    "date": ISO8601DateFormatter().string(from: n.date)
                ]
                if let subtitle = n.subtitle { dict["subtitle"] = subtitle }
                if let body = n.body { dict["body"] = body }
                return dict
            }
            let json = (try? JSONSerialization.data(withJSONObject: array))
                .flatMap { String(data: $0, encoding: .utf8) } ?? "[]"
            completion(json)
        }
    }

    /// Requests notification authorization.
    public func requestPermission(completion: ((Bool, String?) -> Void)?) {
        Log.d(TAG, "[requestPermission]")
        IosNotificationManager.shared.requestPermission(completion: completion)
    }

    /// Returns the current authorization status as a string.
    public func getAuthorizationStatus(completion: @escaping (String) -> Void) {
        Log.d(TAG, "[getAuthorizationStatus]")
        IosNotificationManager.shared.authorizationStatus { status in
            let statusStr: String
            switch status {
            case .authorized: statusStr = "authorized"
            case .denied: statusStr = "denied"
            case .notDetermined: statusStr = "notDetermined"
            case .provisional: statusStr = "provisional"
            case .ephemeral: statusStr = "ephemeral"
            case .unknown: statusStr = "unknown"
            }
            completion(statusStr)
        }
    }

    /// Opens the app's notification settings page.
    public func openNotificationSettings() {
        Log.d(TAG, "[openNotificationSettings]")
        IosNotificationManager.shared.openNotificationSettings()
    }

    /// Sets the app icon badge count.
    public func setBadgeCount(_ count: Int, completion: ((Bool, String?) -> Void)?) {
        Log.d(TAG, "[setBadgeCount] count: \(count)")
        IosNotificationManager.shared.setBadgeCount(count, completion: completion)
    }

    /// Registers a notification category from a JSON string.
    public func registerCategory(categoryJson: String, completion: ((Bool, String?) -> Void)?) {
        Log.d(TAG, "[registerCategory] categoryJson: \(categoryJson)")
        guard let category = parser.parseCategory(from: categoryJson) else {
            completion?(false, "Failed to parse category JSON")
            return
        }
        IosNotificationManager.shared.registerCategory(category)
        completion?(true, nil)
    }

    /// Removes a registered notification category.
    public func removeCategory(identifier: String) {
        Log.d(TAG, "[removeCategory] identifier: \(identifier)")
        IosNotificationManager.shared.removeCategory(identifier: identifier)
    }
}
