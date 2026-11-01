//
//  IosNotificationManager.swift
//  IosLibrary
//

import Foundation
import os
import Synchronization
import UIKit
import UserNotifications

private let logger = Logger(subsystem: "com.jonghyunkim.nativetoolkit.IosLibrary", category: "IosNotificationManager")

/// Callback invoked when a notification action is tapped.
///
/// It is `@Sendable` because the manager stores it, may have it set from any thread, and calls
/// it on the main thread.
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
/// * ``installDelegate()`` installs the library's `UNUserNotificationCenterDelegate`, which
///   presents the library's notifications in the foreground and receives the responses to them,
///   and forwards the other notifications to the delegate that was set before it. Call it on the
///   main thread at launch, before `application(_:didFinishLaunchingWithOptions:)` returns (or
///   inside `scene(_:willConnectTo:options:)`; in a SwiftUI app, in `App.init` or in the
///   `UIApplicationDelegateAdaptor`'s `application(_:didFinishLaunchingWithOptions:)`). The
///   manager itself is not a `UNUserNotificationCenterDelegate`.
/// * ``responses`` delivers the responses to the library's notifications (taps, actions, replies,
///   the custom dismiss action) and ``settingsRequests`` the system's requests to show the app's
///   notification settings. Each keeps up to 32 events while it has no listener, so a listener
///   added after launch still receives the response that launched the app.
///   ``launchResponse()`` returns that response.
/// * The library marks the notifications it adds with a reserved userInfo key
///   (`com.jonghyunkim.nativetoolkit`) to tell them from other components' notifications; it
///   rejects a userInfo that uses the key and removes the key from every userInfo it hands back.
/// * Every operation goes through its use case. The operations that complete have a callback
///   form (the existing `(isSuccess, errorMessage)` forms, whose `errorMessage` is the fixed
///   English description of a ``NotificationError``) and an `async` form. The `async` forms are
///   declared `async throws` without a thrown type; the library's repository throws a
///   ``NotificationError`` (a repository of your own may throw its own errors). The queries and
///   the categories do not throw.
/// * ``requestPermission(options:presenter:completion:)`` and
///   ``openNotificationSettings(presenter:completion:)`` take a ``PresenterSelection``:
///   `.foreground` (what the C ABI passes) fails with ``NotificationError/notForeground`` instead
///   of bringing up system UI while the app is not in the foreground.
/// * ``registerCategory(_:completion:)`` and ``removeCategory(identifier:completion:)`` queue the
///   change inside the call; the changes take effect in the order of the calls, and the
///   completion follows the change.
///
/// ## Threading
/// The manager is `Sendable` and may be called from any thread. Every `completion` of an
/// operation is invoked on the main thread (main actor), exactly once, on every path, and always
/// asynchronously (also when the operation is started on the main thread). The completion types are
/// `@MainActor @Sendable`: `@Sendable` because the closure is carried from the calling thread to
/// the main actor, and `@MainActor` to state in the type where it runs, so that a closure written
/// on the main actor (for example in a SwiftUI view) can use main-actor state directly.
///
/// ``responses`` and ``settingsRequests`` can be read on any thread; their listeners are added,
/// removed and called on the main actor. ``launchResponse()`` is main actor only.
/// ``installDelegate()`` does its work on the main thread only; ``isDelegateInstalled`` can be
/// read on any thread. The deprecated ``onActionReceived`` and ``onTextInputActionReceived`` are
/// called on the main thread, after the delegate's
/// `userNotificationCenter(_:didReceive:withCompletionHandler:)` has returned and before the
/// system's completion handler is called; they, and ``foregroundPresentationOptions``, may be
/// read and written from any thread.
///
/// ## Example
/// ```swift
/// // In application(_:didFinishLaunchingWithOptions:), on the main thread:
/// IosNotificationManager.installDelegate()
/// let registration = try IosNotificationManager.shared.responses.addListener { event, _ in
///     print(event.notificationIdentifier, event.actionIdentifier)
/// }
///
/// IosNotificationManager.shared.show(
///     content: NotificationContent(id: "1", title: "Hello"),
///     trigger: nil
/// ) { isSuccess, errorMessage in
///     print(isSuccess, errorMessage ?? "")
/// }
/// ```
public final class IosNotificationManager: NSObject, Sendable {

    /// Shared singleton instance.
    public static let shared = IosNotificationManager()

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
    private let setBadgeCountUseCase: SetBadgeCountUseCase
    private let requestPermissionUseCase: RequestNotificationPermissionUseCase
    private let openSettingsUseCase: OpenNotificationSettingsUseCase
    /// The foreground check of the permission request and the settings page (design 8.5.4).
    private let presentationGate: NotificationPresentationGate

    /// The values the app sets and the delegate callbacks read, possibly on different threads.
    private struct DelegateSettings {
        var foregroundPresentationOptions: UNNotificationPresentationOptions = [.banner, .list, .sound, .badge]
        var onActionReceived: NotificationActionHandler?
        var onTextInputActionReceived: NotificationTextInputActionHandler?
    }

    private let delegateSettings = Mutex(DelegateSettings())

    /// Whether the library's delegate is installed and the launch response it found (the
    /// library's installer; tests pass their own).
    private let delegateStatus: NotificationDelegateStatus
    private let responseHub: NotificationEventHub<NotificationResponseEvent>
    private let settingsRequestHub: NotificationEventHub<NotificationSettingsRequest>

    /// Presentation options of the notifications the library presents while the app is in the
    /// foreground: the library's notifications, and the others when no previous delegate
    /// implements `userNotificationCenter(_:willPresent:withCompletionHandler:)`.
    public var foregroundPresentationOptions: UNNotificationPresentationOptions {
        get { delegateSettings.withLock { $0.foregroundPresentationOptions } }
        set { delegateSettings.withLock { $0.foregroundPresentationOptions = newValue } }
    }

    /// Called when the user responds to a notification the library handles (a tap on the body, an
    /// action button, or dismissing it with the custom dismiss action), except a text input action.
    ///
    /// The library handles the responses to its notifications, and to the others when no previous
    /// delegate implements `userNotificationCenter(_:didReceive:withCompletionHandler:)`; the
    /// other responses go to the previous delegate only. Called on the main thread (see the type's
    /// Threading section), with the userInfo without the library's own key. Requires
    /// ``installDelegate()``.
    ///
    /// - Important: Deprecated: use ``responses``. This receiver is called for every response in
    ///   addition to the listeners of ``responses``, so an app that uses both receives each
    ///   response twice. It is not a listener: setting it does not take the events
    ///   ``responses`` keeps while it has no listener, and a response that arrives before it is set
    ///   (at a cold start, for example) is not called again.
    @available(*, deprecated, message: "Use responses")
    public var onActionReceived: NotificationActionHandler? {
        get {
            logger.log(level: .libraryDebug, "[onActionReceived.get]")
            return delegateSettings.withLock { $0.onActionReceived }
        }
        set {
            logger.log(level: .libraryDebug, "[onActionReceived.set] newValue: \(newValue == nil ? "nil" : "provided", privacy: .public)")
            delegateSettings.withLock { $0.onActionReceived = newValue }
        }
    }

    /// Called when a text input action is submitted on a notification the library handles (see
    /// ``onActionReceived``). Called on the main thread. Requires ``installDelegate()``.
    ///
    /// - Important: Deprecated: use ``responses`` (the reply is
    ///   ``NotificationResponseEvent/userText``). The same notes as ``onActionReceived`` apply.
    @available(*, deprecated, message: "Use responses")
    public var onTextInputActionReceived: NotificationTextInputActionHandler? {
        get {
            logger.log(level: .libraryDebug, "[onTextInputActionReceived.get]")
            return delegateSettings.withLock { $0.onTextInputActionReceived }
        }
        set {
            logger.log(level: .libraryDebug, "[onTextInputActionReceived.set] newValue: \(newValue == nil ? "nil" : "provided", privacy: .public)")
            delegateSettings.withLock { $0.onTextInputActionReceived = newValue }
        }
    }

    private override init() {
        logger.log(level: .libraryDebug, "[init]")
        let repo = NotificationRepositoryImpl()
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
        self.setBadgeCountUseCase = SetBadgeCountUseCase(repository: repo)
        self.requestPermissionUseCase = RequestNotificationPermissionUseCase(repository: repo)
        self.openSettingsUseCase = OpenNotificationSettingsUseCase(repository: repo)
        self.presentationGate = NotificationPresentationGate(repository: repo, makeEnvironment: { UIKitPresentationEnvironment() })
        let status = NotificationDelegateStatus.library
        self.delegateStatus = status
        self.responseHub = NotificationEventHub(name: "responses", isDelegateInstalled: status.isInstalled)
        self.settingsRequestHub = NotificationEventHub(name: "settingsRequests", isDelegateInstalled: status.isInstalled)
        super.init()
    }

    /// Internal initializer for tests to inject a repository, the delegate's status (the library's
    /// installer by default) and the foreground check of the permission request and the settings
    /// page (UIKit's by default).
    init(
        repository: NotificationRepository,
        delegateStatus: NotificationDelegateStatus = .library,
        presentationGate: NotificationPresentationGate? = nil
    ) {
        logger.log(level: .libraryDebug, "[init:test] repository: \(String(describing: type(of: repository)), privacy: .public), delegateStatus: provided, presentationGate: \(presentationGate == nil ? "UIKit" : "provided", privacy: .public)")
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
        self.setBadgeCountUseCase = SetBadgeCountUseCase(repository: repository)
        self.requestPermissionUseCase = RequestNotificationPermissionUseCase(repository: repository)
        self.openSettingsUseCase = OpenNotificationSettingsUseCase(repository: repository)
        self.presentationGate = presentationGate
            ?? NotificationPresentationGate(repository: repository, makeEnvironment: { UIKitPresentationEnvironment() })
        self.delegateStatus = delegateStatus
        self.responseHub = NotificationEventHub(name: "responses", isDelegateInstalled: delegateStatus.isInstalled)
        self.settingsRequestHub = NotificationEventHub(name: "settingsRequests", isDelegateInstalled: delegateStatus.isInstalled)
        super.init()
    }

    /// Installs the library's notification delegate: the same as ``installDelegate()``.
    ///
    /// Call it on the main thread at app launch. On another thread it logs an error and installs
    /// nothing (before 2.0.0 it installed the manager itself as the delegate from any thread).
    @available(*, deprecated, message: "Use installDelegate()")
    public static func setup() {
        logger.log(level: .libraryDebug, "[setup]")
        let result = installDelegate()
        if result == .notMainThread {
            logger.error("[setup] not on the main thread: the delegate was not installed")
        }
    }

    // MARK: - Public API

    /// Immediately delivers a notification.
    ///
    /// The userInfo is checked first: ``NotificationError/reservedUserInfoKey`` when it uses the
    /// library's key, ``NotificationError/invalidUserInfo`` when it holds a value that is not a
    /// property-list value; nothing is added then.
    ///
    /// - Note: `completion` is invoked on the main thread, exactly once (see the type's Threading
    ///   section), with `errorMessage` the fixed English description of the ``NotificationError``.
    ///   `content` is `sending` because it is not `Sendable` (its `userInfo` is `[String: Any]`)
    ///   and is handed to a task; pass a value that is not used afterwards.
    public func show(
        content: sending NotificationContent,
        trigger: NotificationTrigger? = nil,
        completion: (@MainActor @Sendable (Bool, String?) -> Void)? = nil
    ) {
        logger.log(level: .libraryDebug, "[show] content.id: \(content.id, privacy: .public), trigger: \(String(describing: trigger), privacy: .private), completion: \(completion == nil ? "nil" : "provided", privacy: .public)")
        Task {
            do {
                try await showUseCase.execute(content: content, trigger: trigger)
                Task { @MainActor in completion?(true, nil) }
            } catch {
                logger.error("[show] error: \(LogRedaction.describe(error), privacy: .public)")
                let message = Self.errorMessage(of: error)
                Task { @MainActor in completion?(false, message) }
            }
        }
    }

    /// Immediately delivers a notification, or delivers it when `trigger` fires.
    ///
    /// The `async` form of ``show(content:trigger:completion:)``: the same checks, and the error
    /// the use case reports. `trigger` has no default, so `show(content:)` without a trigger keeps
    /// calling the callback form.
    /// - Throws: ``NotificationError`` (or what a repository of your own throws).
    public func show(content: sending NotificationContent, trigger: NotificationTrigger?) async throws {
        logger.log(level: .libraryDebug, "[show async] content.id: \(content.id, privacy: .public), trigger: \(String(describing: trigger), privacy: .private)")
        try await showUseCase.execute(content: content, trigger: trigger)
    }

    /// Updates an existing pending notification.
    ///
    /// The userInfo is checked first, as in ``show(content:trigger:completion:)``, and the library's
    /// repository makes the content (with its attachments) before it removes the pending request:
    /// an update rejected by the checks or by an attachment that cannot be made leaves the pending
    /// request in place. When the system then does not add the new request
    /// (``NotificationError/addRequestFailed(_:)``), the pending request has already been removed.
    ///
    /// - Note: `completion` is invoked on the main thread, exactly once. `content` is `sending`
    ///   for the reason given on ``show(content:trigger:completion:)``.
    public func update(
        identifier: String,
        content: sending NotificationContent,
        trigger: NotificationTrigger?,
        completion: (@MainActor @Sendable (Bool, String?) -> Void)? = nil
    ) {
        logger.log(level: .libraryDebug, "[update] identifier: \(identifier, privacy: .public), content.id: \(content.id, privacy: .public), trigger: \(String(describing: trigger), privacy: .private), completion: \(completion == nil ? "nil" : "provided", privacy: .public)")
        Task {
            do {
                try await updateUseCase.execute(identifier: identifier, content: content, trigger: trigger)
                Task { @MainActor in completion?(true, nil) }
            } catch {
                logger.error("[update] error: \(LogRedaction.describe(error), privacy: .public)")
                let message = Self.errorMessage(of: error)
                Task { @MainActor in completion?(false, message) }
            }
        }
    }

    /// The `async` form of ``update(identifier:content:trigger:completion:)``.
    /// - Throws: ``NotificationError`` (or what a repository of your own throws).
    public func update(identifier: String, content: sending NotificationContent, trigger: NotificationTrigger?) async throws {
        logger.log(level: .libraryDebug, "[update async] identifier: \(identifier, privacy: .public), content.id: \(content.id, privacy: .public), trigger: \(String(describing: trigger), privacy: .private)")
        try await updateUseCase.execute(identifier: identifier, content: content, trigger: trigger)
    }

    /// Cancels a specific pending notification.
    ///
    /// The same operation as ``cancelScheduled(identifier:)``: both remove the pending request
    /// with `identifier` and leave a delivered notification in place (design S-P16).
    public func cancel(identifier: String) {
        logger.log(level: .libraryDebug, "[cancel] identifier: \(identifier, privacy: .public)")
        Task { await cancelUseCase.execute(identifier: identifier) }
    }

    /// Cancels all pending notifications.
    ///
    /// The same operation as ``cancelAllScheduled()``. It removes every pending request of the
    /// app, also those another component (a game engine's notification package, for example)
    /// added (design 3.4).
    public func cancelAll() {
        logger.log(level: .libraryDebug, "[cancelAll]")
        Task { await cancelAllUseCase.execute() }
    }

    /// Removes a specific delivered notification from Notification Center.
    public func removeDelivered(identifier: String) {
        logger.log(level: .libraryDebug, "[removeDelivered] identifier: \(identifier, privacy: .public)")
        Task { await removeDeliveredUseCase.execute(identifier: identifier) }
    }

    /// Removes all delivered notifications from Notification Center, also those another component
    /// delivered (design 3.4).
    public func removeAllDelivered() {
        logger.log(level: .libraryDebug, "[removeAllDelivered]")
        Task { await removeAllDeliveredUseCase.execute() }
    }

    /// Schedules a notification for future delivery.
    ///
    /// The request's identifier is `identifier`; `content.id` is not used (design S-P16). The
    /// userInfo is checked first, as in ``show(content:trigger:completion:)``.
    ///
    /// - Note: `completion` is invoked on the main thread, exactly once. `content` is `sending`
    ///   for the reason given on ``show(content:trigger:completion:)``.
    public func schedule(
        content: sending NotificationContent,
        trigger: NotificationTrigger,
        identifier: String,
        completion: (@MainActor @Sendable (Bool, String?) -> Void)? = nil
    ) {
        logger.log(level: .libraryDebug, "[schedule] identifier: \(identifier, privacy: .public), content.id: \(content.id, privacy: .public), trigger: \(String(describing: trigger), privacy: .private), completion: \(completion == nil ? "nil" : "provided", privacy: .public)")
        if content.id != identifier {
            logger.log(level: .libraryDebug, "[schedule] content.id differs from identifier; the request uses identifier")
        }
        Task {
            do {
                try await scheduleUseCase.execute(content: content, trigger: trigger, identifier: identifier)
                Task { @MainActor in completion?(true, nil) }
            } catch {
                logger.error("[schedule] error: \(LogRedaction.describe(error), privacy: .public)")
                let message = Self.errorMessage(of: error)
                Task { @MainActor in completion?(false, message) }
            }
        }
    }

    /// The `async` form of ``schedule(content:trigger:identifier:completion:)``.
    /// - Throws: ``NotificationError`` (or what a repository of your own throws).
    public func schedule(content: sending NotificationContent, trigger: NotificationTrigger, identifier: String) async throws {
        logger.log(level: .libraryDebug, "[schedule async] identifier: \(identifier, privacy: .public), content.id: \(content.id, privacy: .public), trigger: \(String(describing: trigger), privacy: .private)")
        try await scheduleUseCase.execute(content: content, trigger: trigger, identifier: identifier)
    }

    /// Cancels a specific scheduled notification: the same operation as ``cancel(identifier:)``.
    public func cancelScheduled(identifier: String) {
        logger.log(level: .libraryDebug, "[cancelScheduled] identifier: \(identifier, privacy: .public)")
        Task { await cancelScheduledUseCase.execute(identifier: identifier) }
    }

    /// Cancels all scheduled notifications: the same operation as ``cancelAll()``.
    public func cancelAllScheduled() {
        logger.log(level: .libraryDebug, "[cancelAllScheduled]")
        Task { await cancelAllScheduledUseCase.execute() }
    }

    /// Returns all pending (not yet delivered) notification requests.
    ///
    /// - Note: `completion` is invoked on the main thread, exactly once.
    public func getScheduled(completion: @escaping @MainActor @Sendable ([ScheduledNotification]) -> Void) {
        logger.log(level: .libraryDebug, "[getScheduled] completion: provided")
        Task {
            let result = await getScheduledUseCase.execute()
            Task { @MainActor in completion(result) }
        }
    }

    /// Returns all pending (not yet delivered) notification requests; the `async` form of
    /// ``getScheduled(completion:)``. Does not throw: the system reports no failure.
    public func getScheduled() async -> [ScheduledNotification] {
        logger.log(level: .libraryDebug, "[getScheduled async]")
        return await getScheduledUseCase.execute()
    }

    /// Returns all notifications visible in Notification Center.
    ///
    /// - Note: `completion` is invoked on the main thread, exactly once.
    public func getDelivered(completion: @escaping @MainActor @Sendable ([ActiveNotification]) -> Void) {
        logger.log(level: .libraryDebug, "[getDelivered] completion: provided")
        Task {
            let result = await getDeliveredUseCase.execute()
            Task { @MainActor in completion(result) }
        }
    }

    /// Returns all notifications visible in Notification Center; the `async` form of
    /// ``getDelivered(completion:)``. Does not throw.
    public func getDelivered() async -> [ActiveNotification] {
        logger.log(level: .libraryDebug, "[getDelivered async]")
        return await getDeliveredUseCase.execute()
    }

    /// Returns whether the app currently has notification authorization.
    ///
    /// - Note: `completion` is invoked on the main thread, exactly once.
    public func hasPermission(completion: @escaping @MainActor @Sendable (Bool) -> Void) {
        logger.log(level: .libraryDebug, "[hasPermission] completion: provided")
        Task {
            let result = await hasPermissionUseCase.execute()
            Task { @MainActor in completion(result) }
        }
    }

    /// Returns whether the app currently has notification authorization; the `async` form of
    /// ``hasPermission(completion:)``. Does not throw.
    public func hasPermission() async -> Bool {
        logger.log(level: .libraryDebug, "[hasPermission async]")
        return await hasPermissionUseCase.execute()
    }

    /// Returns the current notification authorization status.
    ///
    /// - Note: `completion` is invoked on the main thread, exactly once.
    public func authorizationStatus(completion: @escaping @MainActor @Sendable (NotificationAuthorizationStatus) -> Void) {
        logger.log(level: .libraryDebug, "[authorizationStatus] completion: provided")
        Task {
            let result = await getAuthStatusUseCase.execute()
            Task { @MainActor in completion(result) }
        }
    }

    /// Returns the current notification authorization status; the `async` form of
    /// ``authorizationStatus(completion:)``. Does not throw.
    public func authorizationStatus() async -> NotificationAuthorizationStatus {
        logger.log(level: .libraryDebug, "[authorizationStatus async]")
        return await getAuthStatusUseCase.execute()
    }

    /// Requests authorization to display notifications.
    ///
    /// A denial is reported as `(false, <the description of NotificationError.permissionDenied>)`
    /// and a failed request as `(false, <its description>)`, as before 2.0.0. The app is not
    /// required to be in the foreground. For a result that tells a denial from a failure, use
    /// ``requestPermission(options:presenter:completion:)``.
    ///
    /// - Note: `completion` is invoked on the main thread, exactly once.
    public func requestPermission(
        options: UNAuthorizationOptions = [.alert, .sound, .badge],
        completion: (@MainActor @Sendable (Bool, String?) -> Void)? = nil
    ) {
        logger.log(level: .libraryDebug, "[requestPermission] options: \(options.rawValue, privacy: .public), completion: \(completion == nil ? "nil" : "provided", privacy: .public)")
        Task {
            do {
                let granted = try await requestPermissionUseCase.execute(options: options)
                // The existing form reports a denial as a failure (design S-P27).
                let message = granted ? nil : NotificationError.permissionDenied.errorDescription
                Task { @MainActor in completion?(granted, message) }
            } catch {
                logger.error("[requestPermission] error: \(LogRedaction.describe(error), privacy: .public)")
                let message = Self.errorMessage(of: error)
                Task { @MainActor in completion?(false, message) }
            }
        }
    }

    /// Requests authorization to display notifications, checking the foreground first for
    /// `presenter` (design 8.5.4, S-13).
    ///
    /// | `presenter` | What happens |
    /// |---|---|
    /// | `.firstActiveScene` | Requests at once, as ``requestPermission(options:completion:)`` |
    /// | `.foreground`, `.viewController(_:)` | Reads the status first. When it is not `notDetermined`, nothing is requested and the status answers: `authorized`, `provisional` and `ephemeral` are `true`, the others `false`. When it is `notDetermined`, fails with ``NotificationError/notForeground`` while the app is not in the foreground (no alert is shown); otherwise requests |
    ///
    /// The result is `.success(true)` when granted, `.success(false)` when denied (a denial is not
    /// a failure), and ``NotificationError/authorizationFailed(_:)`` when the request itself
    /// failed. Calls made while another is in progress each get their own completion.
    ///
    /// - Important: With `.foreground` or `.viewController(_:)`, an app whose permission is
    ///   already decided is not asked again, so options added later (for example
    ///   `.providesAppNotificationSettings`) are not requested. Ask with `.firstActiveScene` for
    ///   that.
    /// - Note: `completion` is invoked on the main thread, exactly once, never inside the call.
    ///   `presenter` has no default, so that a call without it still selects
    ///   ``requestPermission(options:completion:)``.
    public func requestPermission(
        options: UNAuthorizationOptions = [.alert, .sound, .badge],
        presenter: PresenterSelection,
        completion: @escaping @MainActor @Sendable (Result<Bool, NotificationError>) -> Void
    ) {
        logger.log(level: .libraryDebug, "[requestPermission(presenter:)] options: \(options.rawValue, privacy: .public), presenter: \(presenter.logName, privacy: .public), completion: provided")
        let gate = presentationGate
        Task { @MainActor in
            let result = await gate.requestPermission(options: options, presenter: presenter)
            completion(result)
        }
    }

    /// The `async` form of ``requestPermission(options:presenter:completion:)``.
    ///
    /// - Important: Unlike ``requestPermission(options:completion:)``, a denial returns `false`;
    ///   it does not throw.
    /// - Returns: `true` when granted, `false` when denied.
    /// - Throws: ``NotificationError/notForeground`` or ``NotificationError/authorizationFailed(_:)``.
    @discardableResult
    public func requestPermission(
        options: UNAuthorizationOptions = [.alert, .sound, .badge],
        presenter: PresenterSelection = .firstActiveScene
    ) async throws -> Bool {
        logger.log(level: .libraryDebug, "[requestPermission async] options: \(options.rawValue, privacy: .public), presenter: \(presenter.logName, privacy: .public)")
        return try await presentationGate.requestPermission(options: options, presenter: presenter).get()
    }

    /// Opens the app's notification settings page.
    ///
    /// Returns at once, as before 2.0.0: whether the page opened is not reported, and the app is
    /// not required to be in the foreground. Use ``openNotificationSettings(presenter:completion:)``
    /// for the result.
    public func openNotificationSettings() {
        logger.log(level: .libraryDebug, "[openNotificationSettings]")
        let useCase = openSettingsUseCase
        Task {
            let opened = await useCase.execute()
            logger.log(level: .libraryDebug, "[openNotificationSettings] opened: \(opened, privacy: .public)")
        }
    }

    /// Opens the app's notification settings page in the Settings app, checking the foreground
    /// first for `presenter` (design 8.5.5).
    ///
    /// | `presenter` | What happens |
    /// |---|---|
    /// | `.firstActiveScene` | Opens at once, as ``openNotificationSettings()`` |
    /// | `.foreground`, `.viewController(_:)` | Fails with ``NotificationError/notForeground`` while the app is not in the foreground; otherwise opens |
    ///
    /// The result is `.success(())` when the system opened the page and
    /// ``NotificationError/openSettingsFailed`` when it did not.
    ///
    /// - Note: `completion` is invoked on the main thread, exactly once, never inside the call
    ///   (usually after the app has moved to the background).
    public func openNotificationSettings(
        presenter: PresenterSelection,
        completion: @escaping @MainActor @Sendable (Result<Void, NotificationError>) -> Void
    ) {
        logger.log(level: .libraryDebug, "[openNotificationSettings(presenter:)] presenter: \(presenter.logName, privacy: .public), completion: provided")
        let gate = presentationGate
        Task { @MainActor in
            let result = await gate.openNotificationSettings(presenter: presenter)
            completion(result)
        }
    }

    /// The `async` form of ``openNotificationSettings(presenter:completion:)``.
    /// - Throws: ``NotificationError/notForeground`` or ``NotificationError/openSettingsFailed``.
    public func openNotificationSettings(presenter: PresenterSelection = .firstActiveScene) async throws {
        logger.log(level: .libraryDebug, "[openNotificationSettings async] presenter: \(presenter.logName, privacy: .public)")
        try await presentationGate.openNotificationSettings(presenter: presenter).get()
    }

    /// Sets the app icon badge count.
    ///
    /// - Note: `completion` is invoked on the main thread, exactly once.
    public func setBadgeCount(_ count: Int, completion: (@MainActor @Sendable (Bool, String?) -> Void)? = nil) {
        logger.log(level: .libraryDebug, "[setBadgeCount] count: \(count, privacy: .public), completion: \(completion == nil ? "nil" : "provided", privacy: .public)")
        Task {
            do {
                try await setBadgeCountUseCase.execute(count)
                Task { @MainActor in completion?(true, nil) }
            } catch {
                logger.error("[setBadgeCount] error: \(LogRedaction.describe(error), privacy: .public)")
                let message = Self.errorMessage(of: error)
                Task { @MainActor in completion?(false, message) }
            }
        }
    }

    /// The `async` form of ``setBadgeCount(_:completion:)``.
    /// - Throws: ``NotificationError/setBadgeCountFailed(_:)`` (or what a repository of your own
    ///   throws).
    public func setBadgeCount(_ count: Int) async throws {
        logger.log(level: .libraryDebug, "[setBadgeCount async] count: \(count, privacy: .public)")
        try await setBadgeCountUseCase.execute(count)
    }

    /// Registers a notification category.
    ///
    /// The change is queued inside this call: the category changes of the process take effect in
    /// the order of the calls, one at a time (design 8.5.6). `completion` is invoked on the main
    /// thread, exactly once, never inside the call, after the category is registered (the system
    /// shows its actions on a notification posted from then on).
    ///
    /// - Note: Before 2.0.0 this method took no `completion`, and two changes could undo each
    ///   other.
    public func registerCategory(_ category: NotificationCategory, completion: (@MainActor @Sendable () -> Void)? = nil) {
        logger.log(level: .libraryDebug, "[registerCategory] identifier: \(category.identifier, privacy: .public), completion: \(completion == nil ? "nil" : "provided", privacy: .public)")
        registerCategoryUseCase.enqueue(category) {
            Self.complete(completion, method: "registerCategory")
        }
    }

    /// The `async` form of ``registerCategory(_:completion:)``: returns once the category is
    /// registered. Does not throw.
    ///
    /// `nonisolated(nonsending)`: the change is queued on the caller's executor before the first
    /// suspension, so calls made in order from one task (or from main-actor tasks started in
    /// order) are applied in that order (design S-P28, SR3-1).
    nonisolated(nonsending)
    public func registerCategory(_ category: NotificationCategory) async {
        logger.log(level: .libraryDebug, "[registerCategory async] identifier: \(category.identifier, privacy: .public)")
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            registerCategoryUseCase.enqueue(category) { continuation.resume() }
        }
    }

    /// Removes a registered notification category.
    ///
    /// Queued like ``registerCategory(_:completion:)``; `completion` is invoked on the main thread,
    /// exactly once, after the category is removed.
    public func removeCategory(identifier: String, completion: (@MainActor @Sendable () -> Void)? = nil) {
        logger.log(level: .libraryDebug, "[removeCategory] identifier: \(identifier, privacy: .public), completion: \(completion == nil ? "nil" : "provided", privacy: .public)")
        removeCategoryUseCase.enqueue(identifier: identifier) {
            Self.complete(completion, method: "removeCategory")
        }
    }

    /// The `async` form of ``removeCategory(identifier:completion:)``: returns once the category
    /// is removed. Does not throw. `nonisolated(nonsending)` as
    /// ``registerCategory(_:)``.
    nonisolated(nonsending)
    public func removeCategory(identifier: String) async {
        logger.log(level: .libraryDebug, "[removeCategory async] identifier: \(identifier, privacy: .public)")
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            removeCategoryUseCase.enqueue(identifier: identifier) { continuation.resume() }
        }
    }

    // MARK: - Helpers

    /// The `errorMessage` of the callback forms: the fixed English description of a
    /// ``NotificationError`` (design S-P7), or the description of an error a repository of your
    /// own threw.
    static func errorMessage(of error: any Error) -> String {
        logger.log(level: .libraryDebug, "[errorMessage] error: \(LogRedaction.describe(error), privacy: .public)")
        if let error = error as? NotificationError, let description = error.errorDescription {
            return description
        }
        return error.localizedDescription
    }

    /// Queues the user's completion of a category change on the main queue (design 8.5.6, SR3-6).
    private static func complete(_ completion: (@MainActor @Sendable () -> Void)?, method: String) {
        logger.log(level: .libraryDebug, "[complete] method: \(method, privacy: .public), completion: \(completion == nil ? "nil" : "provided", privacy: .public)")
        guard let completion else { return }
        DispatchQueue.main.async {
            MainActor.assumeIsolated { completion() }
        }
    }
}

// MARK: - Notification delegate

extension IosNotificationManager {

    /// Installs the library's `UNUserNotificationCenterDelegate` on
    /// `UNUserNotificationCenter.current()`, keeping the current delegate as the previous delegate.
    ///
    /// The library's delegate presents the library's notifications in the foreground with
    /// ``foregroundPresentationOptions`` and hands the responses to them to ``responses`` (and the
    /// system's requests to show the app's notification settings to ``settingsRequests``). A
    /// notification that is not the library's (another component's, a push, or one a 1.x version
    /// of the library scheduled) goes to the previous delegate when it implements the delegate
    /// method, and is handled like the library's when it does not. The previous delegate is held
    /// weakly, and only one is kept: installing again after another object replaced the library's
    /// delegate makes that object the previous delegate in place of the earlier one, which is then
    /// reached only if that object forwards to it.
    ///
    /// | Situation | What the call does |
    /// |---|---|
    /// | Not on the main thread | Nothing; returns ``NotificationDelegateInstallResult/notMainThread`` at once |
    /// | The library's delegate is the current delegate | Nothing |
    /// | First call in the process | Installs it before returning, and starts watching `UNUserNotificationCenter.delegate` and `UIApplication.didBecomeActiveNotification` |
    /// | Another object replaced the library's delegate since | Installs it again in front of that object, which becomes the only previous delegate (logged) |
    ///
    /// When another object replaces `UNUserNotificationCenter.delegate` later, the library logs a
    /// warning and does not install itself again: call this method again to restore it. A
    /// response that launches the app is delivered only to the delegate that is set when
    /// `application(_:didFinishLaunchingWithOptions:)` (or `scene(_:willConnectTo:options:)`)
    /// returns, so a later call loses it; the call still installs the delegate and logs that this
    /// may be after launch when the app is already active.
    ///
    /// - Important: Do not install the library's delegate again in front of a delegate that
    ///   forwards to the library asynchronously (calls the library from a later turn, another
    ///   queue or a task): only a call that comes back synchronously while the library forwards
    ///   is recognised as a cycle.
    /// - Important: Call it at launch. In a SwiftUI app, `App.init` and the
    ///   `UIApplicationDelegateAdaptor`'s `application(_:didFinishLaunchingWithOptions:)` both
    ///   work. `App.init` (like a call before `UIApplicationMain` in a UIKit `main.swift`) runs
    ///   before the application object exists: the library then takes the app for not active yet,
    ///   so the response that launches the app is still found by ``launchResponse()`` and nothing
    ///   is logged about a late install.
    /// - Note: Main thread only, synchronous, never waits; it may be called again (idempotent).
    /// - Returns: ``NotificationDelegateInstallResult/installed``, or
    ///   ``NotificationDelegateInstallResult/notMainThread`` when called on another thread.
    @discardableResult
    public static func installDelegate() -> NotificationDelegateInstallResult {
        let isMainThread = pthread_main_np() != 0
        logger.log(level: .libraryDebug, "[installDelegate] isMainThread: \(isMainThread, privacy: .public)")
        // The thread, not the queue: UIKit and MainActor.assumeIsolated go by the thread, also
        // inside DispatchQueue(label:).sync on the main thread (part 1, 1.3; MS-06).
        guard isMainThread else {
            logger.error("[installDelegate] not on the main thread: nothing was changed")
            return .notMainThread
        }
        return MainActor.assumeIsolated {
            delegateInstaller.install(
                on: { UNUserNotificationCenter.current() },
                applicationIsActive: NotificationDelegateInstaller.isActive(NotificationDelegateInstaller.sharedApplication())
            )
        }
    }

    /// Whether ``installDelegate()`` (or the deprecated ``setup()``, which calls it) has installed
    /// the library's delegate in this process. Once `true`, it stays `true`, also when another
    /// object replaced the delegate later. Any thread.
    public static var isDelegateInstalled: Bool {
        logger.log(level: .libraryDebug, "[isDelegateInstalled]")
        return delegateInstaller.isInstalled
    }

    /// The library's delegate installer: its proxy is the one `UNUserNotificationCenter` gets, and
    /// the manager is its sink. Composed here, so that the delegate's types (Presentation) know
    /// only the sink protocol. Never freed (part 1, 5.14).
    static let delegateInstaller = NotificationDelegateInstaller(
        sink: IosNotificationManager.shared,
        presentationOptions: { IosNotificationManager.shared.foregroundPresentationOptions }
    )
}

extension NotificationDelegateStatus {
    /// The library's installer (``IosNotificationManager/delegateInstaller``), read when called,
    /// so that creating ``IosNotificationManager/shared`` does not create the installer.
    static var library: NotificationDelegateStatus {
        logger.log(level: .libraryDebug, "[NotificationDelegateStatus.library]")
        return NotificationDelegateStatus(
            isInstalled: { IosNotificationManager.delegateInstaller.isInstalled },
            launchResponse: { IosNotificationManager.delegateInstaller.proxy.router.launchResponse }
        )
    }
}

// MARK: - Notification events

extension IosNotificationManager {

    /// The responses to the notifications the library handles: a tap on the body, an action
    /// button, a text input reply, or the custom dismiss action (design 8.4).
    ///
    /// The library handles the responses to its own notifications, and to other notifications
    /// when the delegate set before ``installDelegate()`` does not implement
    /// `userNotificationCenter(_:didReceive:withCompletionHandler:)` (see ``installDelegate()``).
    /// Each response is one ``NotificationResponseEvent``, delivered on the main actor after the
    /// delegate call has returned and before the library calls the system's completion handler.
    /// While no listener is added, up to 32 responses are kept and handed to the next listener
    /// inside its ``NotificationEventHub/addListener(_:)`` call (see ``NotificationEventHub``), so
    /// a listener added after launch still receives the response that launched the app.
    ///
    /// | Situation | ``NotificationEventHub/addListener(_:)`` |
    /// |---|---|
    /// | ``installDelegate()`` has not installed the delegate in this process | Throws ``NotificationError/delegateNotInstalled`` |
    /// | Installed, responses were kept | Adds the listener and hands it the kept responses before returning |
    /// | Installed, nothing kept | Adds the listener |
    ///
    /// - Note: Read it on any thread; add and remove listeners on the main actor. The deprecated
    ///   ``onActionReceived`` and ``onTextInputActionReceived`` are called in addition to the
    ///   listeners: use one or the other, or each response arrives twice.
    public var responses: NotificationEventHub<NotificationResponseEvent> {
        logger.log(level: .libraryDebug, "[responses]")
        return responseHub
    }

    /// The system's requests to show the app's own notification settings
    /// (`userNotificationCenter(_:openSettingsFor:)`), for the requests the library handles: a
    /// request for one of the library's notifications always, and a request without a notification
    /// (from Settings) or for another notification only when the delegate set before
    /// ``installDelegate()`` does not implement the method (otherwise it goes to that delegate).
    ///
    /// The system sends them to an app that asked for
    /// `UNAuthorizationOptions.providesAppNotificationSettings`. The library does not open
    /// anything: show your settings screen when a ``NotificationSettingsRequest`` arrives. The hub
    /// keeps and hands over events like ``responses`` (32 at most), and throws
    /// ``NotificationError/delegateNotInstalled`` in the same situation.
    ///
    /// - Note: Before 2.0.0 the library opened the app's page of the Settings app instead.
    public var settingsRequests: NotificationEventHub<NotificationSettingsRequest> {
        logger.log(level: .libraryDebug, "[settingsRequests]")
        return settingsRequestHub
    }

    /// The response that launched the app, or `nil` when there is none (yet).
    ///
    /// The launch response is the first response of the process that brings the app to the
    /// foreground (a tap on the body, or an action with the foreground option), when it arrived
    /// before the app first became active and the library handled it. A response the library
    /// forwarded to the previous delegate is never the launch response, nor is a background
    /// action (it is delivered as an ordinary event). The same response is also delivered by
    /// ``responses`` with ``NotificationResponseEvent/isLaunchResponse`` set, so handle it in one
    /// place only.
    ///
    /// | When | Result |
    /// |---|---|
    /// | ``installDelegate()`` has not installed the delegate in this process | Throws ``NotificationError/delegateNotInstalled`` |
    /// | The delegate was first installed while the app was already active | `nil` |
    /// | Before the app first becomes active, and before the first response that brings it to the foreground has been handled | `nil` for now; it can become the response later |
    /// | After that | The launch response, or `nil` for good |
    ///
    /// The response does not tell whether a custom action has the foreground option: the library
    /// decides it from the application state in the main-queue block that delivers the response
    /// (not `.background`: brings the app to the foreground). On iOS 18.3, when the user opens the
    /// app within about 0.2 seconds after a background action launched it, that action can be
    /// taken for the launch response.
    ///
    /// - Note: Main actor only.
    /// - Returns: The launch response with ``NotificationResponseEvent/isLaunchResponse`` set, or
    ///   `nil`.
    /// - Throws: ``NotificationError/delegateNotInstalled`` (see the table).
    @MainActor
    public func launchResponse() throws(NotificationError) -> NotificationResponseEvent? {
        logger.log(level: .libraryDebug, "[launchResponse]")
        guard delegateStatus.isInstalled() else {
            logger.error("[launchResponse] the library's delegate is not installed; call IosNotificationManager.installDelegate() first")
            throw .delegateNotInstalled
        }
        return delegateStatus.launchResponse().map { Self.event(of: $0, isLaunchResponse: true) }
    }

    /// The public event of a response the router hands over.
    static func event(of response: NotificationDelegateResponse, isLaunchResponse: Bool) -> NotificationResponseEvent {
        logger.log(level: .libraryDebug, "[event(of:)] \(response.logSummary, privacy: .public), isLaunchResponse: \(isLaunchResponse, privacy: .public)")
        return NotificationResponseEvent(
            notificationIdentifier: response.notification.identifier,
            actionIdentifier: response.actionIdentifier,
            categoryIdentifier: response.categoryIdentifier,
            userText: response.userText,
            userInfo: response.userInfo,
            isLaunchResponse: isLaunchResponse
        )
    }
}

// MARK: - What the delegate hands to the manager

extension IosNotificationManager: NotificationDelegateEventSink {

    /// Hands a response to the listeners of ``responses`` (or keeps it), then to the existing
    /// receivers (design 8.3.2: the event first, then the deprecated receivers, then the router
    /// calls the system completion).
    @MainActor
    func deliver(response: NotificationDelegateResponse, isLaunchResponse: Bool) {
        logger.log(level: .libraryDebug, "[deliver(response:)] \(response.logSummary, privacy: .public), isLaunchResponse: \(isLaunchResponse, privacy: .public)")
        responseHub.deliver(Self.event(of: response, isLaunchResponse: isLaunchResponse))
        let (onAction, onTextInput) = delegateSettings.withLock { ($0.onActionReceived, $0.onTextInputActionReceived) }
        guard onAction != nil || onTextInput != nil else { return }
        // The existing receivers read the userInfo as before: Foundation types (design S-P25).
        let userInfo = NotificationUserInfoValue.foundationDictionary(response.userInfo)
        let identifier = response.notification.identifier
        if let userText = response.userText {
            onTextInput?(identifier, response.actionIdentifier, userText, userInfo)
        } else {
            onAction?(identifier, response.actionIdentifier, userInfo)
        }
    }

    /// Hands a settings request to the listeners of ``settingsRequests`` (or keeps it). The
    /// library opens nothing (design P1-10).
    @MainActor
    func deliver(settingsRequestFor notificationIdentifier: String?) {
        logger.log(level: .libraryDebug, "[deliver(settingsRequestFor:)] notificationIdentifier: \(notificationIdentifier ?? "nil", privacy: .public)")
        settingsRequestHub.deliver(NotificationSettingsRequest(notificationIdentifier: notificationIdentifier))
    }
}
