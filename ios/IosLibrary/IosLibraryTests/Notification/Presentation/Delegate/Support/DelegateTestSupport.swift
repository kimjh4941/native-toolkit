//
//  DelegateTestSupport.swift
//  IosLibraryTests
//
//  Stand-ins for the notification delegate tests (UT-19〜UT-22, UT-24): notifications as the
//  router sees them, the sink, a recorder for the system completion, the previous delegate's
//  behaviours of the 1a table (stage 1a delegate notes, chapter 3), and a center.
//

import Foundation
import Synchronization
import UIKit
import UserNotifications
@testable import IosLibrary

// MARK: - Notifications

/// The kinds of notification of the 1a table.
enum TestNotificationKind: String, CaseIterable, Sendable, CustomStringConvertible {
    /// The library's (has the marker).
    case library
    /// Another component's local notification (no marker).
    case host
    /// One a 1.x version of the library scheduled (no marker; like `host` to the router).
    case legacy
    /// A push with the marker (still not the library's, 1a-12).
    case pushWithMarker
    /// A push without the marker.
    case push

    var description: String { rawValue }

    /// Whether the router must treat it as the library's.
    var isLibrary: Bool { self == .library }

    func notification(identifier: String = "n-1", date: Date = Date(timeIntervalSince1970: 1_000)) -> NotificationDelegateNotification {
        NotificationDelegateNotification(
            identifier: identifier,
            date: date,
            isPush: self == .push || self == .pushWithMarker,
            hasMarker: self == .library || self == .pushWithMarker
        )
    }

    /// The userInfo such a notification carries.
    var userInfo: [AnyHashable: Any] {
        switch self {
        case .library: [NotificationMarker.key: NotificationMarker.value, "k": "v"]
        case .host: ["host": 1]
        case .legacy: ["k": "v"]
        case .pushWithMarker: [NotificationMarker.key: NotificationMarker.value, "aps": ["alert": "a"]]
        case .push: ["aps": ["alert": "a"]]
        }
    }

    func response(
        identifier: String = "n-1",
        date: Date = Date(timeIntervalSince1970: 1_000),
        action: String = UNNotificationDefaultActionIdentifier,
        userText: String? = nil,
        foreground: NotificationDelegateResponse.Foreground = .always
    ) -> NotificationDelegateResponse {
        NotificationDelegateResponse(
            notification: notification(identifier: identifier, date: date),
            actionIdentifier: action,
            categoryIdentifier: "category",
            userText: userText,
            userInfo: NotificationDelegateProxy.userInfoValues(of: userInfo),
            foreground: foreground
        )
    }
}

// MARK: - Sink

/// Records what the router hands to the library, in order, with the thread.
final class RecordingSink: NotificationDelegateEventSink {
    struct Delivered: Sendable, Equatable {
        let identifier: String?
        let actionIdentifier: String?
        let isLaunchResponse: Bool
        let isSettingsRequest: Bool
        let isMainThread: Bool
    }

    private let delivered = Mutex<[Delivered]>([])
    /// Called inside `deliver(response:isLaunchResponse:)` (to see what happened before it).
    let onResponse: @Sendable () -> Void

    init(onResponse: @escaping @Sendable () -> Void = {}) {
        self.onResponse = onResponse
    }

    var all: [Delivered] { delivered.withLock { $0 } }
    var responses: [Delivered] { all.filter { !$0.isSettingsRequest } }
    var settingsRequests: [Delivered] { all.filter(\.isSettingsRequest) }

    @MainActor
    func deliver(response: NotificationDelegateResponse, isLaunchResponse: Bool) {
        onResponse()
        let item = Delivered(identifier: response.notification.identifier, actionIdentifier: response.actionIdentifier,
                             isLaunchResponse: isLaunchResponse, isSettingsRequest: false, isMainThread: Thread.isMainThread)
        delivered.withLock { $0.append(item) }
    }

    @MainActor
    func deliver(settingsRequestFor notificationIdentifier: String?) {
        let item = Delivered(identifier: notificationIdentifier, actionIdentifier: nil,
                             isLaunchResponse: false, isSettingsRequest: true, isMainThread: Thread.isMainThread)
        delivered.withLock { $0.append(item) }
    }
}

// MARK: - System completion

/// Counts the calls of a system completion handler, with the value and the thread.
final class CompletionRecorder<Value: Sendable>: Sendable {
    struct Call: Sendable {
        let value: Value
        let isMainThread: Bool
    }

    private let calls = Mutex<[Call]>([])

    var all: [Call] { calls.withLock { $0 } }
    var count: Int { all.count }

    /// A completion handler that records its calls.
    var handler: @Sendable (Value) -> Void {
        { value in
            let call = Call(value: value, isMainThread: Thread.isMainThread)
            self.calls.withLock { $0.append(call) }
        }
    }
}

// MARK: - Previous delegate behaviours (1a table)

/// What the previous delegate does with the completion it is given (stage 1a, chapter 1).
enum PreviousBehavior: String, CaseIterable, Sendable, CustomStringConvertible {
    /// There is no previous delegate, or it does not implement the method.
    case none
    /// Calls the completion at once.
    case sync
    /// Calls it 30 ms later on the main queue.
    case asyncMain
    /// Calls it 30 ms later on a global queue.
    case asyncBackground
    /// Calls it twice at once.
    case twice
    /// Drops it without calling it.
    case never
    /// Keeps it and never calls it.
    case hold

    var description: String { rawValue }

    /// How many system completions it causes once everything has settled.
    var expectedSystemCompletions: Int {
        switch self {
        case .none, .sync, .asyncMain, .asyncBackground, .twice: 1
        case .never, .hold: 0
        }
    }
}

/// A previous delegate made of closures: counts its calls and acts as told.
final class FakePrevious: Sendable {
    /// The answer of `willPresent` (the host's options).
    static let hostOptions: UNNotificationPresentationOptions = [.banner]

    let behavior: PreviousBehavior
    private let state = Mutex<(calls: Int, held: [@Sendable () -> Void])>((0, []))

    init(_ behavior: PreviousBehavior) {
        self.behavior = behavior
    }

    var callCount: Int { state.withLock { $0.calls } }

    /// The forwarding closure the proxy would pass, or `nil` for ``PreviousBehavior/none``.
    var willPresent: NotificationDelegateRouter.ForwardWillPresent<UNNotificationPresentationOptions>? {
        guard behavior != .none else { return nil }
        return { handler in self.act { handler(Self.hostOptions) } }
    }

    var didReceive: NotificationDelegateRouter.ForwardDidReceive? {
        guard behavior != .none else { return nil }
        return { handler in self.act { handler() } }
    }

    var openSettings: NotificationDelegateRouter.ForwardOpenSettings? {
        guard behavior != .none else { return nil }
        return { self.state.withLock { $0.calls += 1 } }
    }

    private func act(_ complete: @escaping @Sendable () -> Void) {
        state.withLock { $0.calls += 1 }
        switch behavior {
        case .none: break
        case .sync: complete()
        case .twice:
            complete()
            complete()
        case .asyncMain: DispatchQueue.main.asyncAfter(deadline: .now() + 0.03) { complete() }
        case .asyncBackground: DispatchQueue.global().asyncAfter(deadline: .now() + 0.03) { complete() }
        case .never: break
        case .hold: state.withLock { $0.held.append(complete) }
        }
    }
}

// MARK: - Router

extension NotificationDelegateRouter {
    /// A router for tests; the application is in the foreground unless told otherwise.
    static func forTests(
        _ sink: any NotificationDelegateEventSink,
        isApplicationInForeground: @escaping @MainActor @Sendable () -> Bool = { true }
    ) -> NotificationDelegateRouter {
        NotificationDelegateRouter(sink: sink, isApplicationInForeground: isApplicationInForeground)
    }
}

/// The options the library presents with in these tests.
let libraryTestOptions: UNNotificationPresentationOptions = [.list, .sound]

/// Waits for asynchronous previous delegates (30 ms) and the main queue.
func settle() async {
    try? await Task.sleep(nanoseconds: 150_000_000)
    await drainMainQueue(times: 2)
}

// MARK: - Center and delegates

/// A stand-in for `UNUserNotificationCenter`: `delegate` is weak and key-value observable.
///
/// `@unchecked Sendable` (test code only): it is created and used on the main thread, and only
/// handed to the installer, whose `install(on:)` reads it through a `@Sendable` closure.
final class FakeNotificationCenter: NSObject, NotificationDelegateCenter, @unchecked Sendable {
    /// Called inside the setter of ``delegate``, after the value is stored: stands for a delegate
    /// call the system makes on another thread as soon as the delegate is set.
    var onDelegateSet: (() -> Void)?

    @objc dynamic weak var delegate: (any UNUserNotificationCenterDelegate)? {
        didSet { onDelegateSet?() }
    }
}

extension NotificationDelegateInstaller {
    /// Installs on a stand-in center (the library reads the center through a closure).
    @MainActor
    func install(on center: FakeNotificationCenter, applicationIsActive: Bool) -> NotificationDelegateInstallResult {
        install(on: { center }, applicationIsActive: applicationIsActive)
    }
}

/// A host delegate that implements the three methods.
final class FullHostDelegate: NSObject, UNUserNotificationCenterDelegate {
    func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification,
                                withCompletionHandler completionHandler: @escaping @Sendable (UNNotificationPresentationOptions) -> Void) {
        completionHandler([])
    }

    func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse,
                                withCompletionHandler completionHandler: @escaping @Sendable () -> Void) {
        completionHandler()
    }

    func userNotificationCenter(_ center: UNUserNotificationCenter, openSettingsFor notification: UNNotification?) {}
}

/// A host delegate that implements none of the methods (`responds(to:)` says no).
final class BareHostDelegate: NSObject, UNUserNotificationCenterDelegate {}

/// A sink that ignores everything (for the installer tests).
final class IgnoringSink: NotificationDelegateEventSink {
    @MainActor func deliver(response: NotificationDelegateResponse, isLaunchResponse: Bool) {}
    @MainActor func deliver(settingsRequestFor notificationIdentifier: String?) {}
}
