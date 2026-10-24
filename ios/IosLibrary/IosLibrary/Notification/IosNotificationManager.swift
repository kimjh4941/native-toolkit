//
//  IosNotificationManager.swift
//  IosLibrary
//

import Foundation
import Synchronization
import UserNotifications

/// Callback invoked when a notification action is tapped.
///
/// It is `@Sendable` because the manager stores it and calls it from the
/// `UNUserNotificationCenterDelegate` callback, whose thread the system does not document.
/// - Parameters:
///   - notificationIdentifier: The identifier of the notification.
///   - actionIdentifier: The identifier of the tapped action.
///   - userInfo: Custom data from the notification.
public typealias NotificationActionHandler = @Sendable (
    _ notificationIdentifier: String,
    _ actionIdentifier: String,
    _ userInfo: [AnyHashable: Any]
) -> Void

/// Callback invoked when a text input notification action is submitted.
///
/// It is `@Sendable` for the same reason as ``NotificationActionHandler``.
/// - Parameters:
///   - notificationIdentifier: The identifier of the notification.
///   - actionIdentifier: The identifier of the tapped action.
///   - userText: The text entered by the user.
///   - userInfo: Custom data from the notification.
public typealias NotificationTextInputActionHandler = @Sendable (
    _ notificationIdentifier: String,
    _ actionIdentifier: String,
    _ userText: String,
    _ userInfo: [AnyHashable: Any]
) -> Void

/// # IosNotificationManager
///
/// Central entry point for local notification operations.
///
/// ## Overview
/// * Provides a singleton (`shared`) for global access.
/// * Owns `UNUserNotificationCenterDelegate` to control foreground presentation and action handling.
/// * Wraps all use cases and converts errors to `(isSuccess, errorMessage)` for Unity interop.
/// * Call `setup()` once at app launch (e.g. in `AppDelegate.didFinishLaunching`).
///
/// ## Threading
/// The manager is `Sendable` and may be called from any thread. Every `completion` of an
/// operation is invoked on the main thread (main actor), exactly once, on every path, and always
/// asynchronously (also when the operation is started on the main thread). The completion types are
/// `@MainActor @Sendable`: `@Sendable` because the closure is carried from the calling thread to
/// the main actor, and `@MainActor` to state in the type where it runs, so that a closure written
/// on the main actor (for example in a SwiftUI view) can use main-actor state directly.
///
/// ``onActionReceived`` and ``onTextInputActionReceived`` are called synchronously from the
/// `UNUserNotificationCenterDelegate` callback, before the system's completion handler, on the
/// thread the system uses for that callback. They, and ``foregroundPresentationOptions``, may be
/// read and written from any thread.
///
/// ## Example
/// ```swift
/// IosNotificationManager.setup()
/// IosNotificationManager.shared.show(
///     content: NotificationContent(id: "1", title: "Hello"),
///     trigger: nil
/// ) { isSuccess, errorMessage in
///     print(isSuccess, errorMessage ?? "")
/// }
/// ```
public final class IosNotificationManager: NSObject, Sendable {

    private let TAG = "IosNotificationManager"

    /// Shared singleton instance.
    public static let shared = IosNotificationManager()

    private let repository: NotificationRepository
    private let showUseCase: ShowNotificationUseCase
    private let updateUseCase: UpdateNotificationUseCase
    private let cancelUseCase: CancelNotificationUseCase
    private let cancelAllUseCase: CancelAllNotificationsUseCase
    private let removeDeliveredUseCase: RemoveDeliveredNotificationUseCase
    private let removeAllDeliveredUseCase: RemoveAllDeliveredNotificationsUseCase
    private let scheduleUseCase: ScheduleNotificationUseCase
    private let cancelScheduledUseCase: CancelScheduledNotificationUseCase
    private let cancelAllScheduledUseCase: CancelAllScheduledNotificationsUseCase
    private let getScheduledUseCase: GetScheduledNotificationsUseCase
    private let getDeliveredUseCase: GetDeliveredNotificationsUseCase
    private let hasPermissionUseCase: HasNotificationPermissionUseCase
    private let getAuthStatusUseCase: GetAuthorizationStatusUseCase
    private let registerCategoryUseCase: RegisterNotificationCategoryUseCase
    private let removeCategoryUseCase: RemoveNotificationCategoryUseCase
    private let permissionHelper: NotificationPermissionHelper

    /// The values the app sets and the delegate callbacks read, possibly on different threads.
    private struct DelegateSettings {
        var foregroundPresentationOptions: UNNotificationPresentationOptions = [.banner, .list, .sound, .badge]
        var onActionReceived: NotificationActionHandler?
        var onTextInputActionReceived: NotificationTextInputActionHandler?
    }

    private let delegateSettings = Mutex(DelegateSettings())

    /// Presentation options for foreground notifications.
    public var foregroundPresentationOptions: UNNotificationPresentationOptions {
        get { delegateSettings.withLock { $0.foregroundPresentationOptions } }
        set { delegateSettings.withLock { $0.foregroundPresentationOptions = newValue } }
    }

    /// Called when a notification action button is tapped.
    public var onActionReceived: NotificationActionHandler? {
        get { delegateSettings.withLock { $0.onActionReceived } }
        set { delegateSettings.withLock { $0.onActionReceived = newValue } }
    }

    /// Called when a text input notification action is submitted.
    public var onTextInputActionReceived: NotificationTextInputActionHandler? {
        get { delegateSettings.withLock { $0.onTextInputActionReceived } }
        set { delegateSettings.withLock { $0.onTextInputActionReceived = newValue } }
    }

    private override init() {
        Log.d(TAG, "[init]")
        let repo = NotificationRepositoryImpl()
        self.repository = repo
        self.showUseCase = ShowNotificationUseCase(repository: repo)
        self.updateUseCase = UpdateNotificationUseCase(repository: repo)
        self.cancelUseCase = CancelNotificationUseCase(repository: repo)
        self.cancelAllUseCase = CancelAllNotificationsUseCase(repository: repo)
        self.removeDeliveredUseCase = RemoveDeliveredNotificationUseCase(repository: repo)
        self.removeAllDeliveredUseCase = RemoveAllDeliveredNotificationsUseCase(repository: repo)
        self.scheduleUseCase = ScheduleNotificationUseCase(repository: repo)
        self.cancelScheduledUseCase = CancelScheduledNotificationUseCase(repository: repo)
        self.cancelAllScheduledUseCase = CancelAllScheduledNotificationsUseCase(repository: repo)
        self.getScheduledUseCase = GetScheduledNotificationsUseCase(repository: repo)
        self.getDeliveredUseCase = GetDeliveredNotificationsUseCase(repository: repo)
        self.hasPermissionUseCase = HasNotificationPermissionUseCase(repository: repo)
        self.getAuthStatusUseCase = GetAuthorizationStatusUseCase(repository: repo)
        self.registerCategoryUseCase = RegisterNotificationCategoryUseCase(repository: repo)
        self.removeCategoryUseCase = RemoveNotificationCategoryUseCase(repository: repo)
        self.permissionHelper = NotificationPermissionHelper(repository: repo)
        super.init()
    }

    /// Internal initializer for tests to inject a repository and helper.
    init(repository: NotificationRepository, permissionHelper: NotificationPermissionHelper) {
        Log.d(TAG, "[init:test]")
        self.repository = repository
        self.showUseCase = ShowNotificationUseCase(repository: repository)
        self.updateUseCase = UpdateNotificationUseCase(repository: repository)
        self.cancelUseCase = CancelNotificationUseCase(repository: repository)
        self.cancelAllUseCase = CancelAllNotificationsUseCase(repository: repository)
        self.removeDeliveredUseCase = RemoveDeliveredNotificationUseCase(repository: repository)
        self.removeAllDeliveredUseCase = RemoveAllDeliveredNotificationsUseCase(repository: repository)
        self.scheduleUseCase = ScheduleNotificationUseCase(repository: repository)
        self.cancelScheduledUseCase = CancelScheduledNotificationUseCase(repository: repository)
        self.cancelAllScheduledUseCase = CancelAllScheduledNotificationsUseCase(repository: repository)
        self.getScheduledUseCase = GetScheduledNotificationsUseCase(repository: repository)
        self.getDeliveredUseCase = GetDeliveredNotificationsUseCase(repository: repository)
        self.hasPermissionUseCase = HasNotificationPermissionUseCase(repository: repository)
        self.getAuthStatusUseCase = GetAuthorizationStatusUseCase(repository: repository)
        self.registerCategoryUseCase = RegisterNotificationCategoryUseCase(repository: repository)
        self.removeCategoryUseCase = RemoveNotificationCategoryUseCase(repository: repository)
        self.permissionHelper = permissionHelper
        super.init()
    }

    /// Registers this manager as the `UNUserNotificationCenterDelegate`.
    /// Call once at app launch.
    public static func setup() {
        Log.d("IosNotificationManager", "[setup]")
        UNUserNotificationCenter.current().delegate = shared
    }

    // MARK: - Public API

    /// Immediately delivers a notification.
    ///
    /// - Note: `completion` is invoked on the main thread, exactly once (see the type's Threading
    ///   section). `content` is `sending` because it is not `Sendable` (its `userInfo` is
    ///   `[String: Any]`) and is handed to a task; pass a value that is not used afterwards.
    public func show(
        content: sending NotificationContent,
        trigger: NotificationTrigger? = nil,
        completion: (@MainActor @Sendable (Bool, String?) -> Void)? = nil
    ) {
        Log.d(TAG, "[show] content.id: \(content.id)")
        Task {
            do {
                try await showUseCase.execute(content: content, trigger: trigger)
                Task { @MainActor in completion?(true, nil) }
            } catch {
                Log.e(TAG, "[show] error: \(error)")
                let message = error.localizedDescription
                Task { @MainActor in completion?(false, message) }
            }
        }
    }

    /// Updates an existing pending notification.
    ///
    /// - Note: `completion` is invoked on the main thread, exactly once. `content` is `sending`
    ///   for the reason given on ``show(content:trigger:completion:)``.
    public func update(
        identifier: String,
        content: sending NotificationContent,
        trigger: NotificationTrigger?,
        completion: (@MainActor @Sendable (Bool, String?) -> Void)? = nil
    ) {
        Log.d(TAG, "[update] identifier: \(identifier)")
        Task {
            do {
                try await updateUseCase.execute(identifier: identifier, content: content, trigger: trigger)
                Task { @MainActor in completion?(true, nil) }
            } catch {
                Log.e(TAG, "[update] error: \(error)")
                let message = error.localizedDescription
                Task { @MainActor in completion?(false, message) }
            }
        }
    }

    /// Cancels a specific pending notification.
    public func cancel(identifier: String) {
        Log.d(TAG, "[cancel] identifier: \(identifier)")
        Task { await cancelUseCase.execute(identifier: identifier) }
    }

    /// Cancels all pending notifications.
    public func cancelAll() {
        Log.d(TAG, "[cancelAll]")
        Task { await cancelAllUseCase.execute() }
    }

    /// Removes a specific delivered notification from Notification Center.
    public func removeDelivered(identifier: String) {
        Log.d(TAG, "[removeDelivered] identifier: \(identifier)")
        Task { await removeDeliveredUseCase.execute(identifier: identifier) }
    }

    /// Removes all delivered notifications from Notification Center.
    public func removeAllDelivered() {
        Log.d(TAG, "[removeAllDelivered]")
        Task { await removeAllDeliveredUseCase.execute() }
    }

    /// Schedules a notification for future delivery.
    ///
    /// - Note: `completion` is invoked on the main thread, exactly once. `content` is `sending`
    ///   for the reason given on ``show(content:trigger:completion:)``.
    public func schedule(
        content: sending NotificationContent,
        trigger: NotificationTrigger,
        identifier: String,
        completion: (@MainActor @Sendable (Bool, String?) -> Void)? = nil
    ) {
        Log.d(TAG, "[schedule] identifier: \(identifier)")
        Task {
            do {
                try await scheduleUseCase.execute(content: content, trigger: trigger, identifier: identifier)
                Task { @MainActor in completion?(true, nil) }
            } catch {
                Log.e(TAG, "[schedule] error: \(error)")
                let message = error.localizedDescription
                Task { @MainActor in completion?(false, message) }
            }
        }
    }

    /// Cancels a specific scheduled notification.
    public func cancelScheduled(identifier: String) {
        Log.d(TAG, "[cancelScheduled] identifier: \(identifier)")
        Task { await cancelScheduledUseCase.execute(identifier: identifier) }
    }

    /// Cancels all scheduled notifications.
    public func cancelAllScheduled() {
        Log.d(TAG, "[cancelAllScheduled]")
        Task { await cancelAllScheduledUseCase.execute() }
    }

    /// Returns all pending (not yet delivered) notification requests.
    ///
    /// - Note: `completion` is invoked on the main thread, exactly once.
    public func getScheduled(completion: @escaping @MainActor @Sendable ([ScheduledNotification]) -> Void) {
        Log.d(TAG, "[getScheduled]")
        Task {
            let result = await getScheduledUseCase.execute()
            Task { @MainActor in completion(result) }
        }
    }

    /// Returns all notifications visible in Notification Center.
    ///
    /// - Note: `completion` is invoked on the main thread, exactly once.
    public func getDelivered(completion: @escaping @MainActor @Sendable ([ActiveNotification]) -> Void) {
        Log.d(TAG, "[getDelivered]")
        Task {
            let result = await getDeliveredUseCase.execute()
            Task { @MainActor in completion(result) }
        }
    }

    /// Returns whether the app currently has notification authorization.
    ///
    /// - Note: `completion` is invoked on the main thread, exactly once.
    public func hasPermission(completion: @escaping @MainActor @Sendable (Bool) -> Void) {
        Log.d(TAG, "[hasPermission]")
        Task {
            let result = await hasPermissionUseCase.execute()
            Task { @MainActor in completion(result) }
        }
    }

    /// Returns the current notification authorization status.
    ///
    /// - Note: `completion` is invoked on the main thread, exactly once.
    public func authorizationStatus(completion: @escaping @MainActor @Sendable (NotificationAuthorizationStatus) -> Void) {
        Log.d(TAG, "[authorizationStatus]")
        Task {
            let result = await getAuthStatusUseCase.execute()
            Task { @MainActor in completion(result) }
        }
    }

    /// Requests authorization to display notifications.
    ///
    /// - Note: `completion` is invoked on the main thread, exactly once.
    public func requestPermission(
        options: UNAuthorizationOptions = [.alert, .sound, .badge],
        completion: (@MainActor @Sendable (Bool, String?) -> Void)? = nil
    ) {
        Log.d(TAG, "[requestPermission] options: \(options)")
        Task {
            do {
                let granted = try await permissionHelper.requestPermission(options: options)
                Task { @MainActor in completion?(granted, nil) }
            } catch {
                Log.e(TAG, "[requestPermission] error: \(error)")
                let message = error.localizedDescription
                Task { @MainActor in completion?(false, message) }
            }
        }
    }

    /// Opens the app's notification settings page.
    public func openNotificationSettings() {
        Log.d(TAG, "[openNotificationSettings]")
        repository.openNotificationSettings()
    }

    /// Sets the app icon badge count.
    ///
    /// - Note: `completion` is invoked on the main thread, exactly once.
    public func setBadgeCount(_ count: Int, completion: (@MainActor @Sendable (Bool, String?) -> Void)? = nil) {
        Log.d(TAG, "[setBadgeCount] count: \(count)")
        Task {
            do {
                try await repository.setBadgeCount(count)
                Task { @MainActor in completion?(true, nil) }
            } catch {
                Log.e(TAG, "[setBadgeCount] error: \(error)")
                let message = error.localizedDescription
                Task { @MainActor in completion?(false, message) }
            }
        }
    }

    /// Registers a notification category.
    public func registerCategory(_ category: NotificationCategory) {
        Log.d(TAG, "[registerCategory] identifier: \(category.identifier)")
        Task { await registerCategoryUseCase.execute(category) }
    }

    /// Removes a registered notification category.
    public func removeCategory(identifier: String) {
        Log.d(TAG, "[removeCategory] identifier: \(identifier)")
        Task { await removeCategoryUseCase.execute(identifier: identifier) }
    }
}

// MARK: - UNUserNotificationCenterDelegate

extension IosNotificationManager: UNUserNotificationCenterDelegate {

    /// Controls how a notification is presented when the app is in the foreground.
    public func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        Log.d(TAG, "[willPresent] identifier: \(notification.request.identifier)")
        completionHandler(foregroundPresentationOptions)
    }

    /// Handles the user's response to a delivered notification (action tap or default open).
    public func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        Log.d(TAG, "[didReceive] actionIdentifier: \(response.actionIdentifier), notificationIdentifier: \(response.notification.request.identifier)")
        let notificationId = response.notification.request.identifier
        let actionId = response.actionIdentifier
        let userInfo = response.notification.request.content.userInfo

        if let textInputResponse = response as? UNTextInputNotificationResponse {
            onTextInputActionReceived?(notificationId, actionId, textInputResponse.userText, userInfo)
        } else {
            onActionReceived?(notificationId, actionId, userInfo)
        }

        completionHandler()
    }

    /// Called when the user taps the notification settings action from the notification interface.
    public func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        openSettingsFor notification: UNNotification?
    ) {
        Log.d(TAG, "[openSettingsFor] identifier: \(notification?.request.identifier ?? "nil")")
        openNotificationSettings()
    }
}
