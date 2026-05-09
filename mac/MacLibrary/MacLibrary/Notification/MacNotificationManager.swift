//
//  MacNotificationManager.swift
//  MacLibrary
//
//  Created by Kim Jong Hyun on 2026/05/09.
//
import UserNotifications

/// Facade for all macOS local notification operations.
///
/// `MacNotificationManager` is the **sole owner** of `UNUserNotificationCenterDelegate`.
/// No other layer should set the delegate on `UNUserNotificationCenter`.
///
/// ## OS Requirement
/// All APIs require macOS 15+. Calls on earlier OS versions return `unsupportedOS`.
///
/// ## Thread Safety
/// Public API can be called from any thread. All completion callbacks are dispatched to
/// the **main queue**.
///
/// ## Usage
/// ```swift
/// MacNotificationManager.shared.setup()
///
/// MacNotificationManager.shared.requestPermission { result in
///     // runs on main queue
/// }
///
/// MacNotificationManager.shared.show(
///     content: NotificationContent(id: "hello", title: "Hello"),
///     trigger: .immediate
/// ) { result in
///     // runs on main queue
/// }
/// ```
public final class MacNotificationManager: NSObject {

    private let TAG = "MacNotificationManager"

    /// Shared singleton instance.
    public static let shared = MacNotificationManager()

    private let repository: NotificationRepository
    private let permissionHelper: NotificationPermissionHelper
    private let dispatchUseCases: NotificationDispatchUseCases
    private let scheduleUseCases: NotificationScheduleUseCases
    private let queryUseCases: NotificationQueryUseCases
    private let categoryUseCases: NotificationCategoryUseCases

    /// Called when a notification action is received (button tap).
    /// Signature: `(notificationId: String, actionId: String)`
    public var onActionReceived: ((String, String) -> Void)?

    /// Called when a text-input notification action is received.
    /// Signature: `(notificationId: String, actionId: String, userText: String)`
    public var onTextInputActionReceived: ((String, String, String) -> Void)?

    private static let minimumOS = "macOS 15.0"

    // MARK: - Init

    private override init() {
        Log.d("MacNotificationManager", "init")
        let repo = NotificationRepositoryImpl()
        self.repository = repo
        self.permissionHelper = NotificationPermissionHelper(repository: repo)
        self.dispatchUseCases = NotificationDispatchUseCases(repository: repo)
        self.scheduleUseCases = NotificationScheduleUseCases(repository: repo)
        self.queryUseCases = NotificationQueryUseCases(repository: repo)
        self.categoryUseCases = NotificationCategoryUseCases(repository: repo)
        super.init()
    }

    /// Initializer for dependency injection (testing).
    internal init(repository: NotificationRepository) {
        Log.d("MacNotificationManager", "init(repository:)")
        self.repository = repository
        self.permissionHelper = NotificationPermissionHelper(repository: repository)
        self.dispatchUseCases = NotificationDispatchUseCases(repository: repository)
        self.scheduleUseCases = NotificationScheduleUseCases(repository: repository)
        self.queryUseCases = NotificationQueryUseCases(repository: repository)
        self.categoryUseCases = NotificationCategoryUseCases(repository: repository)
        super.init()
    }

    // MARK: - Setup

    /// Registers this manager as the `UNUserNotificationCenter` delegate.
    ///
    /// Call once at application startup before using any notification API.
    public func setup() {
        Log.d(TAG, "setup called")
        UNUserNotificationCenter.current().delegate = self
    }

    // MARK: - OS Guard

    @discardableResult
    private func guardOS<T>(
        _ completion: @escaping (Result<T, NotificationDomainError>) -> Void
    ) -> Bool {
        if #available(macOS 15.0, *) { return true }
        Log.e(TAG, "unsupportedOS")
        DispatchQueue.main.async {
            completion(.failure(.unsupportedOS(minimum: Self.minimumOS)))
        }
        return false
    }

    // MARK: - Permission

    /// Requests notification authorization from the user.
    ///
    /// - Parameters:
    ///   - options: Desired authorization options. Defaults to alert, sound, and badge.
    ///   - completion: Called on the main queue.
    public func requestPermission(
        options: UNAuthorizationOptions = [.alert, .sound, .badge],
        completion: @escaping (Result<Bool, NotificationDomainError>) -> Void
    ) {
        Log.d(TAG, "requestPermission called")
        guard guardOS(completion) else { return }
        permissionHelper.requestPermission(options: options, completion: completion)
    }

    /// Returns the current notification authorization status.
    ///
    /// - Parameter completion: Called on the main queue.
    public func getAuthorizationStatus(
        completion: @escaping (Result<NotificationAuthorizationStatus, NotificationDomainError>) -> Void
    ) {
        Log.d(TAG, "getAuthorizationStatus called")
        guard guardOS(completion) else { return }
        permissionHelper.getAuthorizationStatus(completion: completion)
    }

    /// Opens the system Notification Settings page.
    ///
    /// - Parameter completion: Called on the main queue.
    public func openNotificationSettings(
        completion: @escaping (Result<Void, NotificationDomainError>) -> Void
    ) {
        Log.d(TAG, "openNotificationSettings called")
        guard guardOS(completion) else { return }
        permissionHelper.openNotificationSettings(completion: completion)
    }

    // MARK: - Show / Update

    /// Displays a notification immediately or at the specified trigger time.
    ///
    /// - Parameters:
    ///   - content: Notification payload.
    ///   - trigger: When to fire. Use `.immediate` to show right away.
    ///   - completion: Called on the main queue.
    public func show(
        content: NotificationContent,
        trigger: NotificationTrigger = .immediate,
        completion: @escaping (Result<Void, NotificationDomainError>) -> Void
    ) {
        Log.d(TAG, "show called with id: \(content.id)")
        guard guardOS(completion) else { return }
        dispatchUseCases.show(content: content, trigger: trigger) { result in
            DispatchQueue.main.async { completion(result) }
        }
    }

    /// Updates an existing pending notification.
    ///
    /// - Parameters:
    ///   - identifier: Identifier of the notification to replace.
    ///   - content: New notification payload.
    ///   - trigger: New trigger.
    ///   - completion: Called on the main queue.
    public func update(
        identifier: String,
        content: NotificationContent,
        trigger: NotificationTrigger = .immediate,
        completion: @escaping (Result<Void, NotificationDomainError>) -> Void
    ) {
        Log.d(TAG, "update called with identifier: \(identifier)")
        guard guardOS(completion) else { return }
        dispatchUseCases.update(identifier: identifier, content: content, trigger: trigger) { result in
            DispatchQueue.main.async { completion(result) }
        }
    }

    // MARK: - Schedule

    /// Schedules a future notification.
    ///
    /// - Parameters:
    ///   - content: Notification payload.
    ///   - trigger: When to fire. Must not be `.immediate`.
    ///   - completion: Called on the main queue.
    public func schedule(
        content: NotificationContent,
        trigger: NotificationTrigger,
        completion: @escaping (Result<Void, NotificationDomainError>) -> Void
    ) {
        Log.d(TAG, "schedule called with id: \(content.id)")
        guard guardOS(completion) else { return }
        scheduleUseCases.schedule(content: content, trigger: trigger) { result in
            DispatchQueue.main.async { completion(result) }
        }
    }

    /// Cancels the pending notification with the given identifier.
    ///
    /// - Parameter identifier: The notification identifier to cancel.
    public func cancelScheduled(identifier: String) {
        Log.d(TAG, "cancelScheduled called with identifier: \(identifier)")
        scheduleUseCases.cancelScheduled(identifier: identifier)
    }

    /// Cancels all pending notifications.
    public func cancelAllScheduled() {
        Log.d(TAG, "cancelAllScheduled called")
        scheduleUseCases.cancelAllScheduled()
    }

    /// Returns all pending (scheduled) notifications.
    ///
    /// - Parameter completion: Called on the main queue.
    public func getScheduled(
        completion: @escaping (Result<[ScheduledNotification], NotificationDomainError>) -> Void
    ) {
        Log.d(TAG, "getScheduled called")
        guard guardOS(completion) else { return }
        scheduleUseCases.getScheduled { result in
            DispatchQueue.main.async { completion(result) }
        }
    }

    // MARK: - Delivered

    /// Returns all delivered (already shown) notifications.
    ///
    /// - Parameter completion: Called on the main queue.
    public func getDelivered(
        completion: @escaping (Result<[ActiveNotification], NotificationDomainError>) -> Void
    ) {
        Log.d(TAG, "getDelivered called")
        guard guardOS(completion) else { return }
        queryUseCases.getDelivered { result in
            DispatchQueue.main.async { completion(result) }
        }
    }

    /// Removes a delivered notification by identifier.
    ///
    /// - Parameter identifier: The notification identifier.
    public func removeDelivered(identifier: String) {
        Log.d(TAG, "removeDelivered called with identifier: \(identifier)")
        queryUseCases.removeDelivered(identifier: identifier)
    }

    /// Removes all delivered notifications.
    public func removeAllDelivered() {
        Log.d(TAG, "removeAllDelivered called")
        queryUseCases.removeAllDelivered()
    }

    // MARK: - Category

    /// Registers a notification category (overwrites existing with the same id).
    ///
    /// - Parameters:
    ///   - category: The category to register.
    ///   - completion: Called on the main queue.
    public func registerCategory(
        _ category: NotificationCategory,
        completion: @escaping (Result<Void, NotificationDomainError>) -> Void
    ) {
        Log.d(TAG, "registerCategory called with id: \(category.id)")
        categoryUseCases.registerCategory(category) { result in
            DispatchQueue.main.async { completion(result) }
        }
    }

    /// Removes a registered category by identifier.
    ///
    /// - Parameters:
    ///   - identifier: The category identifier to remove.
    ///   - completion: Called on the main queue.
    public func removeCategory(
        identifier: String,
        completion: @escaping (Result<Void, NotificationDomainError>) -> Void
    ) {
        Log.d(TAG, "removeCategory called with identifier: \(identifier)")
        categoryUseCases.removeCategory(identifier: identifier) { result in
            DispatchQueue.main.async { completion(result) }
        }
    }

    // MARK: - Action Handlers

    /// Sets the handler called when the user taps a notification action button.
    ///
    /// - Parameter handler: Receives `(notificationId, actionId)` on the main queue.
    public func setActionReceivedHandler(_ handler: @escaping (String, String) -> Void) {
        Log.d(TAG, "setActionReceivedHandler called")
        onActionReceived = handler
    }

    /// Sets the handler called when the user submits text in a text-input action.
    ///
    /// - Parameter handler: Receives `(notificationId, actionId, userText)` on the main queue.
    public func setTextInputActionReceivedHandler(_ handler: @escaping (String, String, String) -> Void) {
        Log.d(TAG, "setTextInputActionReceivedHandler called")
        onTextInputActionReceived = handler
    }

    // MARK: - Badge

    /// Sets the application badge count.
    ///
    /// - Parameters:
    ///   - count: Badge count. Use `0` to clear.
    ///   - completion: Called on the main queue.
    public func setBadgeCount(
        _ count: Int,
        completion: @escaping (Result<Void, NotificationDomainError>) -> Void
    ) {
        Log.d(TAG, "setBadgeCount called with count: \(count)")
        guard guardOS(completion) else { return }
        repository.setBadgeCount(count) { result in
            DispatchQueue.main.async { completion(result) }
        }
    }
}

// MARK: - UNUserNotificationCenterDelegate

extension MacNotificationManager: UNUserNotificationCenterDelegate {

    /// Determines presentation options for notifications that arrive while the app is in the foreground.
    public func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        Log.d(TAG, "willPresent called for id: \(notification.request.identifier)")
        completionHandler([.banner, .sound, .badge])
    }

    /// Handles the user's response to a delivered notification (action taps, text input).
    public func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        Log.d(TAG, "didReceive called for id: \(response.notification.request.identifier), action: \(response.actionIdentifier)")
        defer { completionHandler() }
        let notificationId = response.notification.request.identifier
        let actionId = response.actionIdentifier
        if let textResponse = response as? UNTextInputNotificationResponse {
            let userText = textResponse.userText
            DispatchQueue.main.async { [weak self] in
                self?.onTextInputActionReceived?(notificationId, actionId, userText)
            }
        } else {
            DispatchQueue.main.async { [weak self] in
                self?.onActionReceived?(notificationId, actionId)
            }
        }
    }
}
