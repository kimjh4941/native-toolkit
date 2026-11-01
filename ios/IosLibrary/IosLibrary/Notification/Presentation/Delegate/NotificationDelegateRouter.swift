//
//  NotificationDelegateRouter.swift
//  IosLibrary
//

import Foundation
import os
import Synchronization

private let logger = Logger(subsystem: "com.jonghyunkim.nativetoolkit.IosLibrary", category: "NotificationDelegateRouter")

// MARK: - Values the proxy builds

/// One notification as the router sees it: what tells the library's notifications from the
/// others (part 1, 5.12.2) and what makes the key of a cycle (5.12.5). The proxy builds it from
/// `UNNotification` inside the delegate method, so no `UNNotification` crosses threads.
struct NotificationDelegateNotification: Sendable, Equatable {
    /// `request.identifier`.
    let identifier: String
    /// `date` (two deliveries of one identifier differ here).
    let date: Date
    /// Whether `request.trigger` is a `UNPushNotificationTrigger`.
    let isPush: Bool
    /// Whether `request.content.userInfo` carries ``NotificationMarker/key``.
    let hasMarker: Bool

    /// Part 1, 5.12.2: a push is never the library's (even with the marker, 1a-12); otherwise
    /// the marker decides. A notification without the marker (the host's, or a 1.x one) is not
    /// the library's.
    var isLibraryNotification: Bool {
        !isPush && hasMarker
    }
}

/// One `didReceive` response as the router sees it.
struct NotificationDelegateResponse: Sendable, Equatable {
    /// The notification the user responded to.
    let notification: NotificationDelegateNotification
    /// `actionIdentifier` (the system's constants for the body and for dismissing).
    let actionIdentifier: String
    /// `notification.request.content.categoryIdentifier`.
    let categoryIdentifier: String
    /// The reply of a text input action (`UNTextInputNotificationResponse.userText`); `nil` for
    /// any other response. A secret value: never logged.
    let userText: String?
    /// `notification.request.content.userInfo` as the value tree, without the library's marker
    /// (design S-P11). The values are the user's content: never logged (only the key count).
    let userInfo: [String: NotificationUserInfoValue]
    /// Whether this response brings the app to the foreground. Only such a response can be the
    /// launch response (H2-1).
    let foreground: Foreground

    /// Whether a response brings the app to the foreground (H2-1).
    ///
    /// The response does not say whether a custom action has the foreground option, and at a
    /// cold start the application state inside `didReceive` is `.background` for every response
    /// (MS-05). Inside the main-queue block the router queues from `didReceive`, the scene has
    /// already entered the foreground for a response that brings the app there, and is still in
    /// the background for a background action (MS-05).
    enum Foreground: String, Sendable, Equatable {
        /// A tap on the body (`UNNotificationDefaultActionIdentifier`).
        case always
        /// The custom dismiss action (`UNNotificationDismissActionIdentifier`).
        case never
        /// A custom action: decided from the application state on the main queue.
        case whenTheApplicationIsInTheForeground
    }
}

/// Where the router hands what the library handles. The library's implementation is
/// `IosNotificationManager`; tests pass their own.
protocol NotificationDelegateEventSink: Sendable {
    /// A `didReceive` response the library handles, inside the main-queue block that then calls
    /// the system completion.
    @MainActor func deliver(response: NotificationDelegateResponse, isLaunchResponse: Bool)

    /// An `openSettingsFor` request the library handles (`notificationIdentifier` is `nil` when
    /// the request came without a notification, from Settings). Main queue.
    @MainActor func deliver(settingsRequestFor notificationIdentifier: String?)
}

// MARK: - Router

/// Decides, for each delegate call, whether the library or the previous delegate handles it,
/// and carries it out: part 1, 5.12.2 (which notifications are the library's), 5.12.3
/// (forwarding), 5.12.4 (each system completion through ``CompletionOnce``), 5.12.5 (cycles,
/// P1-21) and the launch response (P1-22 as narrowed by H2-1). Design 8.3.2, S-P20.
///
/// The router never sees a UserNotifications type (it does not import the framework): the proxy
/// passes small values and, when the previous delegate implements the method, a closure that
/// calls it. The presentation options of `willPresent` are a generic `Options` the router only
/// passes through. So every combination of the 1a table can be checked in unit tests.
///
/// ## Threading
/// Every method may be called on any thread (the system documents none). The state is behind
/// one `Mutex`; the previous delegate, the system completion and the sink are never called while
/// it is held (S-8). What the library handles from `didReceive` and `openSettingsFor` is queued
/// on the main queue; `willPresent` completes at once.
///
/// `Sendable` without `@unchecked`: the sink is `Sendable` and the state is a `Mutex`.
final class NotificationDelegateRouter: Sendable {
    /// Calls the previous delegate's `willPresent` with `handler` as its completion (`Options` is
    /// `UNNotificationPresentationOptions` in the library).
    typealias ForwardWillPresent<Options: Sendable> = (_ handler: @escaping @Sendable (Options) -> Void) -> Void
    /// Calls the previous delegate's `didReceive` with `handler` as its completion.
    typealias ForwardDidReceive = (_ handler: @escaping @Sendable () -> Void) -> Void
    /// Calls the previous delegate's `openSettingsFor`.
    typealias ForwardOpenSettings = () -> Void

    /// The delegate methods, for cycle keys and the log.
    enum Method: String, Sendable, Hashable {
        case willPresent
        case didReceive
        case openSettings
    }

    /// The key of a call while it is being forwarded (part 1, 5.12.5): the method, the
    /// notification's identifier and date, and for `didReceive` the action. `openSettingsFor`
    /// without a notification has one fixed key (all `nil`).
    struct CycleKey: Sendable, Hashable {
        let method: Method
        let identifier: String?
        let date: Date?
        let actionIdentifier: String?
    }

    /// Everything that changes, behind one lock.
    struct State: Sendable {
        /// The calls being forwarded right now.
        var forwarding: Set<CycleKey> = []
        /// Whether the app has been active in this process (the first `didBecomeActive` came, or
        /// the app was already active when the proxy was first installed).
        var hasBeenActive = false
        /// Whether a response that brings the app to the foreground has been noted (handled or
        /// forwarded). Only the first such response can be the launch response.
        var hasSeenForegroundResponse = false
        /// The launch response, once decided.
        var launchResponse: NotificationDelegateResponse?

        /// P1-22 as narrowed by H2-1. The launch response is the first response of the process
        /// that brings the app to the foreground (forwarded ones count), when it arrived before
        /// the app had been active, the library handles it, and it is not a cycle. A response that
        /// does not bring the app to the foreground (a background action) is neither the launch
        /// response nor uses up the first place.
        ///
        /// Responses are noted in the order they arrived (main queue, FIFO).
        ///
        /// - Parameters:
        ///   - response: The response.
        ///   - bringsAppToForeground: Whether it brings the app to the foreground.
        ///   - mayBeLaunchResponse: Whether it arrived before the app had been active, the library
        ///     handles it and it is not a cycle.
        /// - Returns: Whether `response` is the launch response.
        mutating func noteResponse(
            _ response: NotificationDelegateResponse,
            bringsAppToForeground: Bool,
            mayBeLaunchResponse: Bool
        ) -> Bool {
            let seen = hasSeenForegroundResponse
            logger.log(level: .libraryDebug, "[State.noteResponse] identifier: \(response.notification.identifier, privacy: .public), bringsAppToForeground: \(bringsAppToForeground, privacy: .public), mayBeLaunchResponse: \(mayBeLaunchResponse, privacy: .public), hasSeenForegroundResponse: \(seen, privacy: .public)")
            guard bringsAppToForeground, !hasSeenForegroundResponse else { return false }
            hasSeenForegroundResponse = true
            guard mayBeLaunchResponse else { return false }
            launchResponse = response
            return true
        }
    }

    /// What one forwarding call found under the lock.
    private enum Start {
        case forward
        case cycle
    }

    private let sink: any NotificationDelegateEventSink
    private let isApplicationInForeground: @MainActor @Sendable () -> Bool
    private let state = Mutex(State())

    /// - Parameters:
    ///   - sink: Receives what the library handles.
    ///   - isApplicationInForeground: Whether the application state is not `.background`; read
    ///     on the main queue for a response to a custom action (``NotificationDelegateResponse/Foreground``).
    init(sink: any NotificationDelegateEventSink, isApplicationInForeground: @escaping @MainActor @Sendable () -> Bool) {
        logger.log(level: .libraryDebug, "[init] sink: \(String(describing: type(of: sink)), privacy: .public), isApplicationInForeground: provided")
        self.sink = sink
        self.isApplicationInForeground = isApplicationInForeground
    }

    // MARK: Launch response (P1-22, H2-1)

    /// The launch response, or `nil` when there is none (yet).
    var launchResponse: NotificationDelegateResponse? {
        let response = state.withLock { $0.launchResponse }
        logger.log(level: .libraryDebug, "[launchResponse] identifier: \(response?.notification.identifier ?? "nil", privacy: .public)")
        return response
    }

    /// Whether the launch response can no longer change: the app has been active, or the first
    /// response that brings the app to the foreground has been noted. A response is noted on the
    /// main queue after it arrived, so right after a `didReceive` this can still be `false`.
    var isLaunchResponseSettled: Bool {
        let settled = state.withLock { $0.hasBeenActive || $0.hasSeenForegroundResponse }
        logger.log(level: .libraryDebug, "[isLaunchResponseSettled] settled: \(settled, privacy: .public)")
        return settled
    }

    /// Records that the proxy was installed for the first time, and whether the app was already
    /// active then (no launch response is possible then).
    func noteFirstInstall(applicationIsActive: Bool) {
        logger.log(level: .libraryDebug, "[noteFirstInstall] applicationIsActive: \(applicationIsActive, privacy: .public)")
        if applicationIsActive {
            state.withLock { $0.hasBeenActive = true }
        }
    }

    /// Records `UIApplication.didBecomeActiveNotification`.
    func noteDidBecomeActive() {
        logger.log(level: .libraryDebug, "[noteDidBecomeActive]")
        let first = state.withLock { state -> Bool in
            defer { state.hasBeenActive = true }
            return !state.hasBeenActive
        }
        if first {
            logger.log(level: .libraryDebug, "[noteDidBecomeActive] the app became active for the first time; the launch response is settled")
        }
    }

    // MARK: Delegate calls

    /// `userNotificationCenter(_:willPresent:withCompletionHandler:)`.
    ///
    /// - Parameters:
    ///   - notification: The notification.
    ///   - previous: Calls the previous delegate, or `nil` when there is none or it does not
    ///     implement `willPresent`.
    ///   - libraryOptions: The options the library presents its notifications with (read only
    ///     when the library handles the call).
    ///   - completion: The system's completion handler.
    func willPresent<Options: Sendable>(
        _ notification: NotificationDelegateNotification,
        previous: ForwardWillPresent<Options>?,
        libraryOptions: () -> Options,
        completion: @escaping @Sendable (Options) -> Void
    ) {
        logger.log(level: .libraryDebug, "[willPresent] \(notification.logSummary, privacy: .public), previous: \(previous == nil ? "nil" : "provided", privacy: .public), libraryOptions: provided, completion: provided")
        let once = CompletionOnce(method: Method.willPresent.rawValue, completion)
        if !notification.isLibraryNotification, let previous {
            let key = CycleKey(method: .willPresent, identifier: notification.identifier, date: notification.date, actionIdentifier: nil)
            switch start(key) {
            case .forward:
                defer { end(key) }
                logger.log(level: .libraryDebug, "[willPresent] identifier: \(notification.identifier, privacy: .public), forwarded to the previous delegate")
                // A nonisolated @Sendable closure: the previous delegate may call it from any
                // thread (part 1 R-4).
                previous { options in once.call(options) }
                return
            case .cycle:
                logger.info("[willPresent] identifier: \(notification.identifier, privacy: .public) came back while being forwarded; handled as unclaimed (P1-21)")
            }
        }
        logger.log(level: .libraryDebug, "[willPresent] identifier: \(notification.identifier, privacy: .public), handled by the library")
        once.call(libraryOptions())
    }

    /// `userNotificationCenter(_:didReceive:withCompletionHandler:)`.
    ///
    /// When the library handles the response, it is queued on the main queue; inside that block
    /// it is noted for the launch response, the sink receives it, and then the system completion
    /// is called once (1a-12). A forwarded response is noted on the main queue too, in the order
    /// the responses arrived.
    ///
    /// - Parameters:
    ///   - response: The response.
    ///   - previous: Calls the previous delegate, or `nil` when there is none or it does not
    ///     implement `didReceive`.
    ///   - completion: The system's completion handler.
    func didReceive(
        _ response: NotificationDelegateResponse,
        previous: ForwardDidReceive?,
        completion: @escaping @Sendable () -> Void
    ) {
        logger.log(level: .libraryDebug, "[didReceive] \(response.logSummary, privacy: .public), previous: \(previous == nil ? "nil" : "provided", privacy: .public), completion: provided")
        let once = CompletionOnce<Void>(method: Method.didReceive.rawValue) { _ in completion() }
        if !response.notification.isLibraryNotification, let previous {
            let key = CycleKey(
                method: .didReceive,
                identifier: response.notification.identifier,
                date: response.notification.date,
                actionIdentifier: response.actionIdentifier
            )
            switch start(key) {
            case .forward:
                defer { end(key) }
                logger.log(level: .libraryDebug, "[didReceive] identifier: \(response.notification.identifier, privacy: .public), forwarded to the previous delegate")
                // Queued before the forwarding call, so that it is noted before anything that
                // comes back during that call. A forwarded response is never the launch response
                // (P1-22: the host handles it), but it can use up the first place.
                noteForwarded(response)
                previous { once.call(()) }
                return
            case .cycle:
                // The outer call of this cycle was forwarded, so this is never the launch
                // response (R4-3).
                logger.info("[didReceive] identifier: \(response.notification.identifier, privacy: .public) came back while being forwarded; handled as unclaimed (P1-21)")
                handle(response, mayBeLaunchResponse: false, once)
                return
            }
        }
        let arrivedBeforeActive = state.withLock { !$0.hasBeenActive }
        handle(response, mayBeLaunchResponse: arrivedBeforeActive, once)
    }

    /// `userNotificationCenter(_:openSettingsFor:)`.
    ///
    /// - Parameters:
    ///   - notification: The notification, or `nil` when the request came from Settings.
    ///   - previous: Calls the previous delegate, or `nil` when there is none or it does not
    ///     implement `openSettingsFor`.
    func openSettings(for notification: NotificationDelegateNotification?, previous: ForwardOpenSettings?) {
        logger.log(level: .libraryDebug, "[openSettings] \(notification?.logSummary ?? "notification: nil", privacy: .public), previous: \(previous == nil ? "nil" : "provided", privacy: .public)")
        // `nil` is not the library's notification (part 1 R-13).
        if notification?.isLibraryNotification != true, let previous {
            let key = CycleKey(method: .openSettings, identifier: notification?.identifier, date: notification?.date, actionIdentifier: nil)
            switch start(key) {
            case .forward:
                defer { end(key) }
                logger.log(level: .libraryDebug, "[openSettings] identifier: \(notification?.identifier ?? "nil", privacy: .public), forwarded to the previous delegate")
                previous()
                return
            case .cycle:
                logger.info("[openSettings] identifier: \(notification?.identifier ?? "nil", privacy: .public) came back while being forwarded; handled as unclaimed (P1-21)")
            }
        }
        let identifier = notification?.identifier
        let sink = self.sink
        logger.log(level: .libraryDebug, "[openSettings] identifier: \(identifier ?? "nil", privacy: .public), handled by the library")
        DispatchQueue.main.async {
            MainActor.assumeIsolated { sink.deliver(settingsRequestFor: identifier) }
        }
    }

    // MARK: Helpers

    /// Puts `key` into the set of calls being forwarded, unless it is already there (a cycle).
    private func start(_ key: CycleKey) -> Start {
        logger.log(level: .libraryDebug, "[start] method: \(key.method.rawValue, privacy: .public), identifier: \(key.identifier ?? "nil", privacy: .public)")
        return state.withLock { state -> Start in
            state.forwarding.insert(key).inserted ? .forward : .cycle
        }
    }

    /// Takes `key` out of the set of calls being forwarded, right after the forwarding call
    /// returned.
    private func end(_ key: CycleKey) {
        logger.log(level: .libraryDebug, "[end] method: \(key.method.rawValue, privacy: .public), identifier: \(key.identifier ?? "nil", privacy: .public)")
        _ = state.withLock { $0.forwarding.remove(key) }
    }

    /// Queues a response the library handles on the main queue: it is noted for the launch
    /// response, the sink receives it, then the system completion is called once (1a-12).
    ///
    /// - Parameter mayBeLaunchResponse: The response arrived before the app had been active and
    ///   is not a cycle.
    private func handle(_ response: NotificationDelegateResponse, mayBeLaunchResponse: Bool, _ once: CompletionOnce<Void>) {
        logger.log(level: .libraryDebug, "[handle] identifier: \(response.notification.identifier, privacy: .public), mayBeLaunchResponse: \(mayBeLaunchResponse, privacy: .public)")
        DispatchQueue.main.async {
            MainActor.assumeIsolated {
                let isLaunchResponse = self.noteOnMain(response, mayBeLaunchResponse: mayBeLaunchResponse)
                self.sink.deliver(response: response, isLaunchResponse: isLaunchResponse)
            }
            once.call(())
        }
    }

    /// Queues the note of a forwarded response on the main queue (see
    /// ``State/noteResponse(_:bringsAppToForeground:mayBeLaunchResponse:)``): it is never the
    /// launch response, but it can use up the first place.
    private func noteForwarded(_ response: NotificationDelegateResponse) {
        logger.log(level: .libraryDebug, "[noteForwarded] identifier: \(response.notification.identifier, privacy: .public)")
        DispatchQueue.main.async {
            MainActor.assumeIsolated {
                _ = self.noteOnMain(response, mayBeLaunchResponse: false)
            }
        }
    }

    /// Notes `response` for the launch response, inside a main-queue block.
    ///
    /// - Returns: Whether it is the launch response.
    @MainActor
    private func noteOnMain(_ response: NotificationDelegateResponse, mayBeLaunchResponse: Bool) -> Bool {
        logger.log(level: .libraryDebug, "[noteOnMain] identifier: \(response.notification.identifier, privacy: .public), mayBeLaunchResponse: \(mayBeLaunchResponse, privacy: .public), foreground: \(response.foreground.rawValue, privacy: .public)")
        let bringsAppToForeground: Bool
        switch response.foreground {
        case .always: bringsAppToForeground = true
        case .never: bringsAppToForeground = false
        case .whenTheApplicationIsInTheForeground: bringsAppToForeground = isApplicationInForeground()
        }
        let isLaunchResponse = state.withLock {
            $0.noteResponse(response, bringsAppToForeground: bringsAppToForeground, mayBeLaunchResponse: mayBeLaunchResponse)
        }
        if isLaunchResponse {
            logger.info("[noteOnMain] identifier: \(response.notification.identifier, privacy: .public), action: \(response.actionIdentifier, privacy: .public) is the launch response")
        } else {
            logger.log(level: .libraryDebug, "[noteOnMain] identifier: \(response.notification.identifier, privacy: .public), bringsAppToForeground: \(bringsAppToForeground, privacy: .public), not the launch response")
        }
        return isLaunchResponse
    }
}

// MARK: - Log forms

extension NotificationDelegateNotification {
    /// Identifiers and flags only (never the content).
    var logSummary: String {
        "identifier: \(identifier), date: \(date.timeIntervalSince1970), isPush: \(isPush), hasMarker: \(hasMarker)"
    }
}

extension NotificationDelegateResponse {
    /// Identifiers, flags and lengths only: the reply and the userInfo values are secret (8.7).
    var logSummary: String {
        "\(notification.logSummary), actionIdentifier: \(actionIdentifier), categoryIdentifier: \(categoryIdentifier), "
            + "userText: \(LogRedaction.length(userText)), userInfoKeys: \(userInfo.count), foreground: \(foreground.rawValue)"
    }
}
