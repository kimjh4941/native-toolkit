//
//  NotificationDelegateProxy.swift
//  IosLibrary
//

import Foundation
import os
import Synchronization
import UIKit
import UserNotifications

private let logger = Logger(subsystem: "com.jonghyunkim.nativetoolkit.IosLibrary", category: "NotificationDelegateProxy")

/// The library's `UNUserNotificationCenterDelegate` (part 1, 5.12; design 8.3.2).
///
/// It implements the three methods always, turns each `UNNotification` into the small values of
/// ``NotificationDelegateRouter`` and lets the router decide; when the previous delegate
/// implements the method (`responds(to:)`, checked on every call), the router gets a closure that
/// calls it. The previous delegate is held weakly, like `UNUserNotificationCenter.delegate`;
/// when it is gone it is as if there were none.
///
/// It also watches `UNUserNotificationCenter.delegate` with key-value observing and logs a
/// warning when another object replaces it (part 1, 5.12.1; H2-3); its own assignment is not a
/// replacement. It does not install itself again: calling
/// `IosNotificationManager.installDelegate()` again does (1a-10). And it receives
/// `UIApplication.didBecomeActiveNotification` for the launch response (P1-22).
///
/// ## Threading
/// The system documents no thread for the delegate methods (the simulator used the main thread),
/// so nothing here assumes one: the class and its methods are nonisolated, and the state is
/// behind `Mutex`es that are never held while outside code runs (S-8).
///
/// `Sendable` without `@unchecked`: only the router, the `@Sendable` closure that reads the
/// presentation options, a `Mutex` (the previous delegate's holder) and an `Atomic` (the
/// replacement count) are stored. There is no `deinit`: the library's proxy is never freed
/// (part 1, 5.14).
final class NotificationDelegateProxy: NSObject, UNUserNotificationCenterDelegate, Sendable {
    static let willPresentSelector = #selector(UNUserNotificationCenterDelegate.userNotificationCenter(_:willPresent:withCompletionHandler:))
    static let didReceiveSelector = #selector(UNUserNotificationCenterDelegate.userNotificationCenter(_:didReceive:withCompletionHandler:))
    static let openSettingsSelector = #selector(UNUserNotificationCenterDelegate.userNotificationCenter(_:openSettingsFor:))

    /// The key path watched on the center.
    static let delegateKeyPath = "delegate"

    let router: NotificationDelegateRouter
    private let presentationOptions: @Sendable () -> UNNotificationPresentationOptions
    /// The holder of the previous delegate. A new holder replaces the old one on every install:
    /// a `Mutex` can take a value that is not `Sendable` only when it is created (`sending`), so
    /// the weak reference lives in an immutable `Sendable` holder.
    private let previous = Mutex(WeakNotificationDelegate(nil))
    private let replacements = Atomic<Int>(0)

    /// - Parameters:
    ///   - router: Decides and carries out each delegate call.
    ///   - presentationOptions: The options of the notifications the library presents in the
    ///     foreground (`IosNotificationManager.foregroundPresentationOptions`). Any thread.
    init(router: NotificationDelegateRouter, presentationOptions: @escaping @Sendable () -> UNNotificationPresentationOptions) {
        logger.log(level: .libraryDebug, "[init] router: provided, presentationOptions: provided")
        self.router = router
        self.presentationOptions = presentationOptions
        super.init()
    }

    // MARK: Previous delegate

    /// The previous delegate, or `nil` when there is none or it is gone.
    var previousDelegate: (any UNUserNotificationCenterDelegate)? {
        previous.withLock { $0 }.delegate
    }

    /// Replaces the previous delegate (the installer, when it installs the proxy). `sending`:
    /// the caller hands the reference over and does not use it afterwards.
    func setPreviousDelegate(_ delegate: sending (any UNUserNotificationCenterDelegate)?) {
        logger.log(level: .libraryDebug, "[setPreviousDelegate] delegate: \(Self.typeName(delegate), privacy: .public)")
        let holder = WeakNotificationDelegate(delegate)
        previous.withLock { $0 = holder }
    }

    /// The previous delegate when it implements `selector`; read under the lock, used outside.
    func previousDelegate(responding selector: Selector) -> (any UNUserNotificationCenterDelegate)? {
        logger.log(level: .libraryDebug, "[previousDelegate] selector: \(NSStringFromSelector(selector), privacy: .public)")
        guard let delegate = previousDelegate, delegate.responds(to: selector) else { return nil }
        return delegate
    }

    /// How many times another object replaced the proxy as the center's delegate (log, tests).
    var replacementCount: Int {
        replacements.load(ordering: .relaxed)
    }

    // MARK: UNUserNotificationCenterDelegate

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping @Sendable (UNNotificationPresentationOptions) -> Void
    ) {
        logger.log(level: .libraryDebug, "[willPresent] identifier: \(notification.request.identifier, privacy: .public), completionHandler: provided, isMainThread: \(Thread.isMainThread, privacy: .public)")
        let forward: NotificationDelegateRouter.ForwardWillPresent<UNNotificationPresentationOptions>? = previousDelegate(responding: Self.willPresentSelector).map { delegate in
            { handler in delegate.userNotificationCenter?(center, willPresent: notification, withCompletionHandler: handler) }
        }
        router.willPresent(Self.value(of: notification), previous: forward, libraryOptions: presentationOptions, completion: completionHandler)
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping @Sendable () -> Void
    ) {
        logger.log(level: .libraryDebug, "[didReceive] identifier: \(response.notification.request.identifier, privacy: .public), actionIdentifier: \(response.actionIdentifier, privacy: .public), completionHandler: provided, isMainThread: \(Thread.isMainThread, privacy: .public)")
        let forward: NotificationDelegateRouter.ForwardDidReceive? = previousDelegate(responding: Self.didReceiveSelector).map { delegate in
            { handler in delegate.userNotificationCenter?(center, didReceive: response, withCompletionHandler: handler) }
        }
        router.didReceive(Self.value(of: response), previous: forward, completion: completionHandler)
    }

    func userNotificationCenter(_ center: UNUserNotificationCenter, openSettingsFor notification: UNNotification?) {
        logger.log(level: .libraryDebug, "[openSettingsFor] identifier: \(notification?.request.identifier ?? "nil", privacy: .public), isMainThread: \(Thread.isMainThread, privacy: .public)")
        let forward: NotificationDelegateRouter.ForwardOpenSettings? = previousDelegate(responding: Self.openSettingsSelector).map { delegate in
            { delegate.userNotificationCenter?(center, openSettingsFor: notification) }
        }
        router.openSettings(for: notification.map(Self.value(of:)), previous: forward)
    }

    // MARK: Application state and replacement

    /// `UIApplication.didBecomeActiveNotification` (registered on the first install).
    @objc func applicationDidBecomeActive(_ notification: Notification) {
        logger.log(level: .libraryDebug, "[applicationDidBecomeActive] name: \(notification.name.rawValue, privacy: .public)")
        router.noteDidBecomeActive()
    }

    /// Key-value observing of the center's `delegate` (registered on the first install). Logs a
    /// warning when another object replaced the proxy; never installs the proxy again.
    override func observeValue(
        forKeyPath keyPath: String?,
        of object: Any?,
        change: [NSKeyValueChangeKey: Any]?,
        context: UnsafeMutableRawPointer?
    ) {
        let newValue = change?[.newKey] as AnyObject?
        let newObject: AnyObject? = newValue is NSNull ? nil : newValue
        logger.log(level: .libraryDebug, "[observeValue] keyPath: \(keyPath ?? "nil", privacy: .public), object: \(Self.typeName(object), privacy: .public), new: \(Self.typeName(newObject), privacy: .public), context: \(context == nil ? "nil" : "provided", privacy: .public)")
        guard keyPath == Self.delegateKeyPath else {
            super.observeValue(forKeyPath: keyPath, of: object, change: change, context: context)
            return
        }
        guard newObject !== self else {
            logger.log(level: .libraryDebug, "[observeValue] the proxy itself was set: not a replacement")
            return
        }
        let count = replacements.wrappingAdd(1, ordering: .relaxed).newValue
        logger.error("[observeValue] warning: UNUserNotificationCenter.delegate was replaced by \(Self.typeName(newObject), privacy: .public) (replacement \(count, privacy: .public)); the library's notification callbacks stop until installDelegate() is called again (it is not reinstalled automatically)")
    }

    // MARK: Values for the router

    /// The router's value of `notification`.
    static func value(of notification: UNNotification) -> NotificationDelegateNotification {
        logger.log(level: .libraryDebug, "[value(of: notification)] identifier: \(notification.request.identifier, privacy: .public)")
        return NotificationDelegateNotification(
            identifier: notification.request.identifier,
            date: notification.date,
            isPush: notification.request.trigger is UNPushNotificationTrigger,
            hasMarker: NotificationMarker.isPresent(in: notification.request.content.userInfo)
        )
    }

    /// The router's value of `response`.
    static func value(of response: UNNotificationResponse) -> NotificationDelegateResponse {
        logger.log(level: .libraryDebug, "[value(of: response)] identifier: \(response.notification.request.identifier, privacy: .public), actionIdentifier: \(response.actionIdentifier, privacy: .public)")
        let content = response.notification.request.content
        return NotificationDelegateResponse(
            notification: value(of: response.notification),
            actionIdentifier: response.actionIdentifier,
            categoryIdentifier: content.categoryIdentifier,
            userText: (response as? UNTextInputNotificationResponse)?.userText,
            userInfo: userInfoValues(of: content.userInfo),
            foreground: foreground(ofAction: response.actionIdentifier)
        )
    }

    /// The value tree of a delivered userInfo without the library's marker (design S-P11,
    /// 8.3.3). `[AnyHashable: Any]` is not `Sendable`; the tree is, so it can reach the main
    /// queue. The values are never logged.
    static func userInfoValues(of userInfo: [AnyHashable: Any]) -> [String: NotificationUserInfoValue] {
        logger.log(level: .libraryDebug, "[userInfoValues(of:)] keyCount: \(userInfo.count, privacy: .public), hasMarker: \(NotificationMarker.isPresent(in: userInfo), privacy: .public)")
        return NotificationUserInfoValue.tree(of: NotificationMarker.removing(from: userInfo)).values
    }

    /// Whether a response with `actionIdentifier` brings the app to the foreground (H2-1): a tap
    /// on the body always does, the custom dismiss action never does, and for a custom action the
    /// router reads the application state on the main queue (the response does not carry the
    /// action's options).
    static func foreground(ofAction actionIdentifier: String) -> NotificationDelegateResponse.Foreground {
        logger.log(level: .libraryDebug, "[foreground(ofAction:)] actionIdentifier: \(actionIdentifier, privacy: .public)")
        switch actionIdentifier {
        case UNNotificationDefaultActionIdentifier: return .always
        case UNNotificationDismissActionIdentifier: return .never
        default: return .whenTheApplicationIsInTheForeground
        }
    }

    /// Whether an application in `state` is in the foreground for H2-1: `.active` and `.inactive`
    /// are, `.background` is not. The router reads it on the main queue for a response to a custom
    /// action (``foreground(ofAction:)``); there, a response that brings the app to the foreground
    /// has already moved the scene into the foreground, and a background action has not (MS-05).
    static func bringsAppToForeground(_ state: UIApplication.State) -> Bool {
        logger.log(level: .libraryDebug, "[bringsAppToForeground] state: \(state.rawValue, privacy: .public)")
        return state != .background
    }

    /// The type name of a delegate or another object, for the log (never its content).
    static func typeName(_ object: Any?) -> String {
        logger.log(level: .libraryDebug, "[typeName] object: \(object == nil ? "nil" : "provided", privacy: .public)")
        guard let object else { return "nil" }
        return String(describing: type(of: object))
    }
}

/// A weak reference to a delegate, fixed when it is created (``NotificationDelegateProxy``).
///
/// `Sendable` without `@unchecked`: the reference is inside a `Mutex` that is given it when it is
/// created (`sending`) and only read afterwards. The weak reference lives in a heap object, not
/// inline in the `Mutex`: an Objective-C weak reference is registered at its address and must
/// not be moved, and the `Mutex` initializer moves its value.
final class WeakNotificationDelegate: Sendable {
    private final class Reference {
        weak var delegate: (any UNUserNotificationCenterDelegate)?

        init(_ delegate: (any UNUserNotificationCenterDelegate)?) {
            logger.log(level: .libraryDebug, "[WeakNotificationDelegate.Reference.init] delegate: \(NotificationDelegateProxy.typeName(delegate), privacy: .public)")
            self.delegate = delegate
        }
    }

    private let reference: Mutex<Reference>

    /// - Parameter delegate: The delegate, handed over (not used by the caller afterwards).
    init(_ delegate: sending (any UNUserNotificationCenterDelegate)?) {
        logger.log(level: .libraryDebug, "[WeakNotificationDelegate.init] delegate: \(NotificationDelegateProxy.typeName(delegate), privacy: .public)")
        reference = Mutex(Reference(delegate))
    }

    /// The delegate, or `nil` when there was none or it is gone.
    var delegate: (any UNUserNotificationCenterDelegate)? {
        reference.withLock { $0.delegate }
    }
}
