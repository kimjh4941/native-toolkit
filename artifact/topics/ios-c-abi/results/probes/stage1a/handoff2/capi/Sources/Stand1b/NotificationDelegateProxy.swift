// Hand-off 2 probe: stand-in for what 1b adds to IosLibrary (Swift API design 8.3, part 1 5.12):
// the forwarding delegate (proxy and router in one class here), CompletionOnce, the launch response
// (P1-22) and the install entry. 1b must build these in IosLibraryʼs Notification/Presentation layer
// with the unit tests of the Swift API design 13.1; the C ABI then only calls installDelegate().
import Foundation
import os
import Synchronization
import UIKit
import UserNotifications

let ntkNotificationLog = Logger(subsystem: "com.jonghyunkim.nativetoolkit.IosLibraryCApi", category: "Notification")

/// One notification event as plain values (part 1 5.12.7). Built synchronously inside the delegate
/// method, so no UNNotification object crosses threads.
struct NotificationEvent: Sendable, Equatable {
    enum Kind: Sendable { case response, settings }
    let kind: Kind
    let identifier: String?
    let action: String?
    let userText: String?
    var isLaunchResponse = false
}

/// Calls the wrapped completion at most once from any thread (part 1 5.12.4). @unchecked Sendable
/// (P1-17 (3)): the SDK completion is not @Sendable; it is taken out under the lock and called outside.
final class CompletionOnce<Value>: @unchecked Sendable {
    private let called = Mutex(false)
    private nonisolated(unsafe) let completion: (Value) -> Void

    init(_ completion: @escaping (Value) -> Void) { self.completion = completion }

    nonisolated func call(_ value: Value) {
        let first = called.withLock { done -> Bool in
            defer { done = true }
            return !done
        }
        guard first else {
            ntkNotificationLog.debug("completion called again; dropped")
            return
        }
        completion(value)
    }
}

/// P1-22: the first didReceive of the process is the launch response when it comes before the first
/// didBecomeActive and the library handled it.
enum LaunchTracker {
    private struct State {
        var firstDidReceiveSeen = false
        var becameActive = false
        var launch: NotificationEvent?
    }

    private static let state = Mutex(State())
    private nonisolated(unsafe) static var observer: NSObjectProtocol?

    @MainActor static func start() {
        if UIApplication.shared.applicationState == .active { state.withLock { $0.becameActive = true } }
        observer = NotificationCenter.default.addObserver(forName: UIApplication.didBecomeActiveNotification, object: nil, queue: .main) { _ in
            state.withLock { $0.becameActive = true }
        }
    }

    /// Called once per didReceive, before forwarding. Returns true when this one is the launch response.
    static func noteDidReceive(handledByLibrary: Bool) -> Bool {
        state.withLock { s in
            guard !s.firstDidReceiveSeen else { return false }
            s.firstDidReceiveSeen = true
            return handledByLibrary && !s.becameActive
        }
    }

    static func setLaunch(_ event: NotificationEvent) { state.withLock { $0.launch = event } }
    static var launch: NotificationEvent? { state.withLock { $0.launch } }
}

final class NotificationDelegateProxy: NSObject, UNUserNotificationCenterDelegate, @unchecked Sendable {
    static let shared = NotificationDelegateProxy()
    /// P1-9: the userInfo key of every notification the library makes; the value is the integer 1.
    static let markerKey = "com.jonghyunkim.nativetoolkit"
    /// P1-6 / S-14: true once the proxy has been installed in this process (C or Swift entry).
    static let installed = Atomic<Bool>(false)
    static let libraryOptions: UNNotificationPresentationOptions = [.banner, .list, .sound, .badge]

    /// P1-21: keys of the calls being forwarded right now.
    private let forwarding = Mutex(Set<String>())
    /// The delegate that was set before the proxy (weak, like UNUserNotificationCenter.delegate).
    private let previousLock = NSLock()
    private nonisolated(unsafe) weak var previousDelegate: (any UNUserNotificationCenterDelegate)?

    private static let willPresentSelector = #selector(UNUserNotificationCenterDelegate.userNotificationCenter(_:willPresent:withCompletionHandler:))
    private static let didReceiveSelector = #selector(UNUserNotificationCenterDelegate.userNotificationCenter(_:didReceive:withCompletionHandler:))
    private static let openSettingsSelector = #selector(UNUserNotificationCenterDelegate.userNotificationCenter(_:openSettingsFor:))

    // MARK: install (Swift API design 8.3.1, part 1 5.12.6)

    @MainActor func install() {
        let center = UNUserNotificationCenter.current()
        let current = center.delegate
        if (current as AnyObject?) === self {
            ntkNotificationLog.debug("install: already installed")
            return
        }
        if Self.installed.load(ordering: .acquiring) {
            ntkNotificationLog.info("install: delegate was replaced by \(current.map { String(describing: type(of: $0)) } ?? "nil", privacy: .public); reinstalling")
        }
        previousLock.withLock { previousDelegate = current }
        center.delegate = self
        if !Self.installed.exchange(true, ordering: .acquiringAndReleasing) {
            LaunchTracker.start()
        }
        if UIApplication.shared.applicationState == .active {
            ntkNotificationLog.info("install: the app is active; this may be after launch (cold-start taps are lost)")
        }
    }

    // MARK: router (part 1 5.12.2, 5.12.3, 5.12.5)

    private enum Kind { case library, other }

    private func kind(_ notification: UNNotification) -> Kind {
        if notification.request.trigger is UNPushNotificationTrigger { return .other }
        return notification.request.content.userInfo[Self.markerKey] != nil ? .library : .other
    }

    private func key(_ method: String, _ notification: UNNotification?, _ action: String? = nil) -> String {
        guard let notification else { return method + "|nil" }
        return "\(method)|\(notification.request.identifier)|\(notification.date.timeIntervalSince1970)|\(action ?? "")"
    }

    /// The previous delegate if it implements the method. Read under the lock, used outside it.
    private func previous(_ selector: Selector) -> (any UNUserNotificationCenterDelegate)? {
        guard let previous = previousLock.withLock({ previousDelegate }), previous.responds(to: selector) else { return nil }
        return previous
    }

    /// False when the key is already being forwarded: a synchronous re-entry (cycle).
    private func enter(_ key: String) -> Bool { forwarding.withLock { $0.insert(key).inserted } }
    private func leave(_ key: String) { _ = forwarding.withLock { $0.remove(key) } }

    // MARK: delegate methods

    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification,
                                            withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        let once = CompletionOnce(completionHandler)
        let isLibrary = kind(notification) == .library
        ntkNotificationLog.notice("willPresent id=\(notification.request.identifier, privacy: .public) library=\(isLibrary, privacy: .public) main=\(pthread_main_np() != 0, privacy: .public)")
        guard !isLibrary, let previous = previous(Self.willPresentSelector) else {
            once.call(Self.libraryOptions)   // library notification, or nobody else takes it
            return
        }
        let key = key("wp", notification)
        guard enter(key) else {
            ntkNotificationLog.info("willPresent came back while forwarding: handled as unclaimed (P1-21)")
            once.call(Self.libraryOptions)
            return
        }
        defer { leave(key) }
        previous.userNotificationCenter?(center, willPresent: notification) { @Sendable options in once.call(options) }
    }

    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse,
                                            withCompletionHandler completionHandler: @escaping () -> Void) {
        let once = CompletionOnce<Void> { _ in completionHandler() }
        let event = NotificationEvent(kind: .response, identifier: response.notification.request.identifier,
                                      action: response.actionIdentifier,
                                      userText: (response as? UNTextInputNotificationResponse)?.userText)
        ntkNotificationLog.notice("didReceive id=\(response.notification.request.identifier, privacy: .public) action=\(response.actionIdentifier, privacy: .public) library=\(self.kind(response.notification) == .library, privacy: .public) main=\(pthread_main_np() != 0, privacy: .public)")
        guard kind(response.notification) == .other, let previous = previous(Self.didReceiveSelector) else {
            handle(event, launch: LaunchTracker.noteDidReceive(handledByLibrary: true), once)
            return
        }
        let key = key("dr", response.notification, response.actionIdentifier)
        guard enter(key) else {
            // The outer call of this cycle was forwarded, so this is never the launch response (R4-3).
            ntkNotificationLog.info("didReceive came back while forwarding: handled as unclaimed (P1-21)")
            handle(event, launch: false, once)
            return
        }
        defer { leave(key) }
        _ = LaunchTracker.noteDidReceive(handledByLibrary: false)
        previous.userNotificationCenter?(center, didReceive: response) { @Sendable in once.call(()) }
    }

    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter, openSettingsFor notification: UNNotification?) {
        let event = NotificationEvent(kind: .settings, identifier: notification?.request.identifier, action: nil, userText: nil)
        ntkNotificationLog.notice("openSettingsFor id=\(notification?.request.identifier ?? "nil", privacy: .public)")
        let isLibrary = notification.map { kind($0) == .library } ?? false
        guard !isLibrary, let previous = previous(Self.openSettingsSelector) else {
            deliverOnMain(event)
            return
        }
        let key = key("os", notification)
        guard enter(key) else {
            ntkNotificationLog.info("openSettingsFor came back while forwarding: handled as unclaimed (P1-21)")
            deliverOnMain(event)
            return
        }
        defer { leave(key) }
        previous.userNotificationCenter?(center, openSettingsFor: notification)
    }

    /// Library-handled didReceive: queue on main, hand the event to the hub (listener or buffer), then
    /// call the system completion once inside that block (1a-12).
    private func handle(_ event: NotificationEvent, launch: Bool, _ once: CompletionOnce<Void>) {
        var event = event
        event.isLaunchResponse = launch
        if launch { LaunchTracker.setLaunch(event) }
        let value = event
        DispatchQueue.main.async {
            MainActor.assumeIsolated { NotificationEventHub.responses.deliver(value) }
            once.call(())
        }
    }

    private func deliverOnMain(_ event: NotificationEvent) {
        DispatchQueue.main.async { MainActor.assumeIsolated { NotificationEventHub.settings.deliver(event) } }
    }
}

/// Swift API design 8.4: one hub per kind, keeping up to 32 events while it has no listener and
/// handing them to the next added listener inside addListener. Simplified (no removal mid-flush rule).
@MainActor final class NotificationEventHub {
    static let responses = NotificationEventHub()
    static let settings = NotificationEventHub()
    static let limit = 32

    private var listeners: [(id: Int, body: (NotificationEvent) -> Void)] = []
    private var held: [NotificationEvent] = []
    private var nextId = 0

    enum HubError: Error { case delegateNotInstalled }

    @discardableResult
    func addListener(_ body: @escaping (NotificationEvent) -> Void) throws -> Int {
        guard NotificationDelegateProxy.installed.load(ordering: .acquiring) else { throw HubError.delegateNotInstalled }
        nextId += 1
        listeners.append((nextId, body))
        let pending = held
        held = []
        for event in pending { body(event) }
        return nextId
    }

    func deliver(_ event: NotificationEvent) {
        guard !listeners.isEmpty else {
            held.append(event)
            if held.count > Self.limit { held.removeFirst(held.count - Self.limit) }
            return
        }
        for listener in listeners { listener.body(event) }
    }
}
