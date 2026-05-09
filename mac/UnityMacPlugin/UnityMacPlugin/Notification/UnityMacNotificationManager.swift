//
//  UnityMacNotificationManager.swift
//  UnityMacPlugin
//
//  Created by Kim Jong Hyun on 2026/05/09.
//
import Foundation
import MacLibrary

@objcMembers
/// Swift facade that bridges `MacNotificationManager` to the Objective-C / C layer.
///
/// All public methods convert Swift `Result<_, NotificationDomainError>` into Obj-C
/// compatible completion blocks with `(Bool isSuccess, Int errorCode, String? errorMessage)`.
///
/// - Thread Safety: Can be called from any thread. Completions are dispatched to the
///   main queue by `MacNotificationManager`.
public class UnityMacNotificationManager: NSObject {

    private let TAG = "UnityMacNotificationManager"

    public static let shared = UnityMacNotificationManager()
    private let parser = UnityMacNotificationJsonParser()

    private override init() {
        Log.d("UnityMacNotificationManager", "init")
        super.init()
    }

    // MARK: - Setup

    /// Registers the notification delegate. Call once at application launch.
    public func setup() {
        Log.d(TAG, "setup called")
        MacNotificationManager.shared.setup()
    }

    // MARK: - Permission

    /// Requests notification authorization.
    ///
    /// - Parameter completion: Called on the main queue with `(isSuccess, errorCode, errorMessage)`.
    public func requestPermission(
        completion: @escaping (Bool, Int, String?) -> Void
    ) {
        Log.d(TAG, "requestPermission called")
        MacNotificationManager.shared.requestPermission { [weak self] result in
            guard let self else { return }
            let r = self.bridgeComponents(result); completion(r.0, r.1, r.2)
        }
    }

    /// Returns the current notification authorization status as JSON.
    ///
    /// JSON shape: `{"status": "authorized"|"denied"|"notDetermined"|"provisional"|"unsupported"}`
    ///
    /// - Parameter completion: Called on the main queue with `(json, errorCode, errorMessage)`.
    public func getAuthorizationStatus(
        completion: @escaping (String?, Int, String?) -> Void
    ) {
        Log.d(TAG, "getAuthorizationStatus called")
        MacNotificationManager.shared.getAuthorizationStatus { [weak self] result in
            guard let self else { return }
            switch result {
            case .failure(let e):
                Log.e(self.TAG, "getAuthorizationStatus failed: \(e.errorMessage)")
                completion(nil, e.errorCode, e.errorMessage)
            case .success(let status):
                let json = self.parser.toJson(status: status)
                completion(json, 0, nil)
            }
        }
    }

    /// Opens the system Notification Settings page.
    ///
    /// - Parameter completion: Called on the main queue with `(isSuccess, errorCode, errorMessage)`.
    public func openNotificationSettings(
        completion: @escaping (Bool, Int, String?) -> Void
    ) {
        Log.d(TAG, "openNotificationSettings called")
        MacNotificationManager.shared.openNotificationSettings { [weak self] result in
            guard let self else { return }
            let r = self.bridgeComponents(result); completion(r.0, r.1, r.2)
        }
    }

    // MARK: - Show / Update

    /// Shows a notification using JSON-encoded content and trigger.
    ///
    /// - Parameters:
    ///   - contentJson: JSON string for `NotificationContent`.
    ///   - triggerJson: JSON string for `NotificationTrigger`.
    ///   - completion: Called on the main queue with `(isSuccess, errorCode, errorMessage)`.
    public func show(
        contentJson: String,
        triggerJson: String,
        completion: @escaping (Bool, Int, String?) -> Void
    ) {
        Log.d(TAG, "show called")
        let contentResult = parser.parseContent(contentJson)
        let triggerResult = parser.parseTrigger(triggerJson)
        switch (contentResult, triggerResult) {
        case (.failure(let e), _), (_, .failure(let e)):
            Log.e(TAG, "show parse error: \(e.errorMessage)")
            completion(false, e.errorCode, e.errorMessage)
        case (.success(let content), .success(let trigger)):
            MacNotificationManager.shared.show(content: content, trigger: trigger) { [weak self] result in
                guard let self else { return }
                let r = self.bridgeComponents(result); completion(r.0, r.1, r.2)
            }
        }
    }

    /// Updates an existing pending notification.
    ///
    /// - Parameters:
    ///   - identifier: The notification identifier to update.
    ///   - contentJson: JSON string for `NotificationContent`.
    ///   - triggerJson: JSON string for `NotificationTrigger`.
    ///   - completion: Called on the main queue with `(isSuccess, errorCode, errorMessage)`.
    public func update(
        identifier: String,
        contentJson: String,
        triggerJson: String,
        completion: @escaping (Bool, Int, String?) -> Void
    ) {
        Log.d(TAG, "update called with identifier: \(identifier)")
        let contentResult = parser.parseContent(contentJson)
        let triggerResult = parser.parseTrigger(triggerJson)
        switch (contentResult, triggerResult) {
        case (.failure(let e), _), (_, .failure(let e)):
            Log.e(TAG, "update parse error: \(e.errorMessage)")
            completion(false, e.errorCode, e.errorMessage)
        case (.success(let content), .success(let trigger)):
            MacNotificationManager.shared.update(
                identifier: identifier,
                content: content,
                trigger: trigger
            ) { [weak self] result in
                guard let self else { return }
                let r = self.bridgeComponents(result); completion(r.0, r.1, r.2)
            }
        }
    }

    // MARK: - Schedule

    /// Schedules a future notification.
    ///
    /// - Parameters:
    ///   - contentJson: JSON string for `NotificationContent`.
    ///   - triggerJson: JSON string for `NotificationTrigger` (must not be `immediate`).
    ///   - completion: Called on the main queue with `(isSuccess, errorCode, errorMessage)`.
    public func schedule(
        contentJson: String,
        triggerJson: String,
        completion: @escaping (Bool, Int, String?) -> Void
    ) {
        Log.d(TAG, "schedule called")
        let contentResult = parser.parseContent(contentJson)
        let triggerResult = parser.parseTrigger(triggerJson)
        switch (contentResult, triggerResult) {
        case (.failure(let e), _), (_, .failure(let e)):
            Log.e(TAG, "schedule parse error: \(e.errorMessage)")
            completion(false, e.errorCode, e.errorMessage)
        case (.success(let content), .success(let trigger)):
            MacNotificationManager.shared.schedule(content: content, trigger: trigger) { [weak self] result in
                guard let self else { return }
                let r = self.bridgeComponents(result); completion(r.0, r.1, r.2)
            }
        }
    }

    /// Cancels the pending notification with the given identifier.
    public func cancelScheduled(identifier: String) {
        Log.d(TAG, "cancelScheduled called with identifier: \(identifier)")
        MacNotificationManager.shared.cancelScheduled(identifier: identifier)
    }

    /// Cancels all pending notifications.
    public func cancelAllScheduled() {
        Log.d(TAG, "cancelAllScheduled called")
        MacNotificationManager.shared.cancelAllScheduled()
    }

    /// Returns all scheduled notifications as a UTF-8 JSON array string.
    ///
    /// - Parameter completion: Called on the main queue with `(json, errorCode, errorMessage)`.
    public func getScheduled(
        completion: @escaping (String?, Int, String?) -> Void
    ) {
        Log.d(TAG, "getScheduled called")
        MacNotificationManager.shared.getScheduled { [weak self] result in
            guard let self else { return }
            switch result {
            case .failure(let e):
                Log.e(self.TAG, "getScheduled failed: \(e.errorMessage)")
                completion(nil, e.errorCode, e.errorMessage)
            case .success(let notifications):
                let json = self.parser.toJson(scheduled: notifications)
                completion(json, 0, nil)
            }
        }
    }

    // MARK: - Delivered

    /// Returns all delivered notifications as a UTF-8 JSON array string.
    ///
    /// - Parameter completion: Called on the main queue with `(json, errorCode, errorMessage)`.
    public func getDelivered(
        completion: @escaping (String?, Int, String?) -> Void
    ) {
        Log.d(TAG, "getDelivered called")
        MacNotificationManager.shared.getDelivered { [weak self] result in
            guard let self else { return }
            switch result {
            case .failure(let e):
                Log.e(self.TAG, "getDelivered failed: \(e.errorMessage)")
                completion(nil, e.errorCode, e.errorMessage)
            case .success(let notifications):
                let json = self.parser.toJson(delivered: notifications)
                completion(json, 0, nil)
            }
        }
    }

    /// Removes a delivered notification by identifier.
    public func removeDelivered(identifier: String) {
        Log.d(TAG, "removeDelivered called with identifier: \(identifier)")
        MacNotificationManager.shared.removeDelivered(identifier: identifier)
    }

    /// Removes all delivered notifications.
    public func removeAllDelivered() {
        Log.d(TAG, "removeAllDelivered called")
        MacNotificationManager.shared.removeAllDelivered()
    }

    // MARK: - Category

    /// Registers a notification category from a JSON string.
    ///
    /// - Parameters:
    ///   - categoryJson: JSON string for `NotificationCategory`.
    ///   - completion: Called on the main queue with `(isSuccess, errorCode, errorMessage)`.
    public func registerCategory(
        categoryJson: String,
        completion: @escaping (Bool, Int, String?) -> Void
    ) {
        Log.d(TAG, "registerCategory called")
        switch parser.parseCategory(categoryJson) {
        case .failure(let e):
            Log.e(TAG, "registerCategory parse error: \(e.errorMessage)")
            completion(false, e.errorCode, e.errorMessage)
        case .success(let category):
            MacNotificationManager.shared.registerCategory(category) { [weak self] result in
                guard let self else { return }
                let r = self.bridgeComponents(result); completion(r.0, r.1, r.2)
            }
        }
    }

    /// Removes a registered category by identifier.
    ///
    /// - Parameters:
    ///   - identifier: Category identifier.
    ///   - completion: Called on the main queue with `(isSuccess, errorCode, errorMessage)`.
    public func removeCategory(
        identifier: String,
        completion: @escaping (Bool, Int, String?) -> Void
    ) {
        Log.d(TAG, "removeCategory called with identifier: \(identifier)")
        MacNotificationManager.shared.removeCategory(identifier: identifier) { [weak self] result in
            guard let self else { return }
            let r = self.bridgeComponents(result); completion(r.0, r.1, r.2)
        }
    }

    // MARK: - Action Handlers

    /// Sets the handler invoked when the user taps a notification action button.
    ///
    /// - Parameter handler: Receives `(notificationId, actionId)` on the main queue.
    public func setActionReceivedHandler(_ handler: @escaping (String, String) -> Void) {
        Log.d(TAG, "setActionReceivedHandler called")
        MacNotificationManager.shared.setActionReceivedHandler(handler)
    }

    /// Sets the handler invoked when the user submits text in a text-input action.
    ///
    /// - Parameter handler: Receives `(notificationId, actionId, userText)` on the main queue.
    public func setTextInputActionReceivedHandler(_ handler: @escaping (String, String, String) -> Void) {
        Log.d(TAG, "setTextInputActionReceivedHandler called")
        MacNotificationManager.shared.setTextInputActionReceivedHandler(handler)
    }

    // MARK: - Badge

    /// Sets the application badge count.
    ///
    /// - Parameters:
    ///   - count: Badge count (`0..9999`). Use `0` to clear.
    ///   - completion: Called on the main queue with `(isSuccess, errorCode, errorMessage)`.
    public func setBadgeCount(
        _ count: Int,
        completion: @escaping (Bool, Int, String?) -> Void
    ) {
        Log.d(TAG, "setBadgeCount called with count: \(count)")
        MacNotificationManager.shared.setBadgeCount(count) { [weak self] result in
            guard let self else { return }
            let r = self.bridgeComponents(result); completion(r.0, r.1, r.2)
        }
    }

    // MARK: - Private Helpers

    private func bridgeComponents<T>(
        _ result: Result<T, NotificationDomainError>
    ) -> (Bool, Int, String?) {
        switch result {
        case .success:
            return (true, 0, nil)
        case .failure(let e):
            Log.e(TAG, "operation failed with errorCode: \(e.errorCode): \(e.errorMessage)")
            return (false, e.errorCode, e.errorMessage)
        }
    }
}
