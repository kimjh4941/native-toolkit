// Hand-off 2 probe: receivers of Notification.h / ProbeNotification.h (part 1 1.4, 5.7, 5.12.7).
import Foundation
import UIKit
@preconcurrency import UserNotifications

private func code(_ value: Int) -> ntk_notification_error { ntk_notification_error(value) }

final class ListenerRegistration: Registration, @unchecked Sendable {
    let callback: ntk_probe_notification_event_fn
    init(_ callback: @escaping ntk_probe_notification_event_fn, _ userData: UnsafeMutableRawPointer?, _ release: ntk_release_fn?) {
        self.callback = callback
        super.init(id: Registry.nextId(), userData: userData, release: release)
    }

    @MainActor func send(_ event: NotificationEvent) {
        let kind = event.kind == .response ? NTK_PROBE_NOTIFICATION_EVENT_RESPONSE : NTK_PROBE_NOTIFICATION_EVENT_SETTINGS
        callback(userData, ntk_probe_notification_event_kind(kind), event.identifier.map(Handle.makeString),
                 event.action.map(Handle.makeString), event.userText.map(Handle.makeString), event.isLaunchResponse ? 1 : 0)
    }
}

final class NotificationDoneRegistration: Registration, @unchecked Sendable {
    let callback: ntk_probe_notification_done_fn
    init(_ callback: @escaping ntk_probe_notification_done_fn, _ userData: UnsafeMutableRawPointer?, _ release: ntk_release_fn?) {
        self.callback = callback
        super.init(id: Registry.nextId(), userData: userData, release: release)
    }

    @MainActor func finish(_ error: Int, granted: Bool = false) {
        Registry.complete(self) { _ in callback(userData, code(error), 0, granted ? 1 : 0) }
    }
}

/// Main-only book of the C listeners (part 1 5.7, 5.12.7): the active registrations in order and the
/// events that arrived while none was active.
@MainActor enum NotificationLedger {
    static var listeners: [ListenerRegistration] = []
    static var held: [NotificationEvent] = []
    static var hubListenerAdded = false

    static func dispatch(_ event: NotificationEvent) {
        let active = listeners.filter { $0.currentState == .active }
        guard !active.isEmpty else {
            held.append(event)
            if held.count > NotificationEventHub.limit { held.removeFirst(held.count - NotificationEventHub.limit) }
            return
        }
        for registration in active where registration.currentState == .active { registration.send(event) }
    }

    /// The "insert and start" block of a C listener.
    static func insert(_ registration: ListenerRegistration) {
        guard registration.currentState == .active else { return }
        listeners.append(registration)
        if !hubListenerAdded {
            hubListenerAdded = true   // added once, never removed (5.12.7); the hubs flush their buffers here
            _ = try? NotificationEventHub.responses.addListener { dispatch($0) }
            _ = try? NotificationEventHub.settings.addListener { dispatch($0) }
        }
        let pending = held
        held = []
        for event in pending { dispatch(event) }
    }
}

let probeCategoryIdentifier = "com.jonghyunkim.nativetoolkit.stage1a.probe"

enum NotificationReceiver {
    private static func reject(_ error: Int, _ userData: UnsafeMutableRawPointer?, _ release: ntk_release_fn?) -> ntk_notification_error {
        ntkNotificationLog.debug("rejected error=\(error, privacy: .public)")
        release?(userData)
        return code(error)
    }

    static func install() -> ntk_notification_error {
        guard pthread_main_np() != 0 else {
            ntkNotificationLog.error("ntk_notification_install called off the main thread: WRONG_THREAD")
            return code(NTK_NOTIFICATION_ERROR_WRONG_THREAD)
        }
        MainActor.assumeIsolated { NotificationDelegateProxy.shared.install() }
        return code(NTK_NOTIFICATION_ERROR_NONE)
    }

    static func addListener(_ callback: ntk_probe_notification_event_fn?, _ userData: UnsafeMutableRawPointer?, _ release: ntk_release_fn?,
                            _ outListener: UnsafeMutablePointer<OpaquePointer?>?) -> ntk_notification_error {
        outListener?.pointee = nil
        ntkNotificationLog.debug("add_listener")
        guard let callback, let outListener else { return reject(NTK_NOTIFICATION_ERROR_INVALID_PARAMETER, userData, release) }
        guard NotificationDelegateProxy.installed.load(ordering: .acquiring) else {
            return reject(NTK_NOTIFICATION_ERROR_NOT_INITIALIZED, userData, release)
        }
        let registration = ListenerRegistration(callback, userData, release)
        Registry.insert(registration)
        outListener.pointee = Handle.make(registration)
        DispatchQueue.main.async { MainActor.assumeIsolated { NotificationLedger.insert(registration) } }
        return code(NTK_NOTIFICATION_ERROR_NONE)
    }

    static func removeListener(_ listener: OpaquePointer?) {
        guard let registration = Handle.borrow(listener, as: ListenerRegistration.self) else { return }
        let removed = registration.state.compareExchange(expected: RegState.active.rawValue, desired: RegState.cancelRequested.rawValue,
                                                         ordering: .acquiringAndReleasing).exchanged
        Handle.free(listener)   // the caller's reference; the queued block keeps its own
        guard removed else { return }
        DispatchQueue.main.async {
            MainActor.assumeIsolated {
                NotificationLedger.listeners.removeAll { $0 === registration }
                Registry.tryRelease(registration, expected: .cancelRequested)
            }
        }
    }

    static func launchResponse(_ outIdentifier: UnsafeMutablePointer<OpaquePointer?>?, _ outAction: UnsafeMutablePointer<OpaquePointer?>?) -> ntk_notification_error {
        outIdentifier?.pointee = nil
        outAction?.pointee = nil
        guard let outIdentifier, let outAction else { return code(NTK_NOTIFICATION_ERROR_INVALID_PARAMETER) }
        guard NotificationDelegateProxy.installed.load(ordering: .acquiring) else { return code(NTK_NOTIFICATION_ERROR_NOT_INITIALIZED) }
        if let launch = LaunchTracker.launch {
            outIdentifier.pointee = launch.identifier.map(Handle.makeString)
            outAction.pointee = launch.action.map(Handle.makeString)
        }
        return code(NTK_NOTIFICATION_ERROR_NONE)
    }

    static func requestPermission(_ callback: ntk_probe_notification_done_fn?, _ userData: UnsafeMutableRawPointer?,
                                  _ release: ntk_release_fn?) -> ntk_notification_error {
        ntkNotificationLog.debug("request_permission")
        guard let callback else { return reject(NTK_NOTIFICATION_ERROR_INVALID_PARAMETER, userData, release) }
        let registration = NotificationDoneRegistration(callback, userData, release)
        Registry.insert(registration)
        DispatchQueue.main.async {
            MainActor.assumeIsolated {
                UNUserNotificationCenter.current().getNotificationSettings { settings in
                    let status = settings.authorizationStatus
                    DispatchQueue.main.async {
                        MainActor.assumeIsolated {
                            if status == .notDetermined, ForegroundPresenter.topViewController() == nil {
                                registration.finish(NTK_NOTIFICATION_ERROR_NOT_FOREGROUND)
                                return
                            }
                            UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge, .providesAppNotificationSettings]) { granted, _ in
                                DispatchQueue.main.async {
                                    MainActor.assumeIsolated {
                                        registration.finish(granted ? NTK_NOTIFICATION_ERROR_NONE : NTK_NOTIFICATION_ERROR_PERMISSION_DENIED, granted: granted)
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }
        return code(NTK_NOTIFICATION_ERROR_NONE)
    }

    static func scheduleMarked(_ seconds: UInt32, _ identifier: UnsafePointer<CChar>?, _ title: UnsafePointer<CChar>?,
                               _ callback: ntk_probe_notification_done_fn?, _ userData: UnsafeMutableRawPointer?,
                               _ release: ntk_release_fn?) -> ntk_notification_error {
        ntkNotificationLog.debug("schedule_marked seconds=\(seconds, privacy: .public)")
        guard let callback, case .value(let id) = CApiString.input(identifier), !id.isEmpty,
              case .value(let text) = CApiString.input(title), !text.isEmpty else {
            return reject(NTK_NOTIFICATION_ERROR_INVALID_PARAMETER, userData, release)
        }
        let registration = NotificationDoneRegistration(callback, userData, release)
        Registry.insert(registration)
        DispatchQueue.main.async {
            MainActor.assumeIsolated {
                let center = UNUserNotificationCenter.current()
                // Keep the host's categories (setNotificationCategories replaces the whole set).
                center.getNotificationCategories { existing in
                    let category = UNNotificationCategory(
                        identifier: probeCategoryIdentifier,
                        actions: [UNNotificationAction(identifier: "ntk.probe.bg", title: "BgAct", options: []),
                                  UNTextInputNotificationAction(identifier: "ntk.probe.reply", title: "Reply", options: [])],
                        intentIdentifiers: [])
                    let center = UNUserNotificationCenter.current()
                    center.setNotificationCategories(existing.filter { $0.identifier != probeCategoryIdentifier }.union([category]))
                    let content = UNMutableNotificationContent()
                    content.title = text
                    content.categoryIdentifier = probeCategoryIdentifier
                    content.userInfo = [NotificationDelegateProxy.markerKey: 1]   // P1-9
                    let trigger = seconds == 0 ? nil : UNTimeIntervalNotificationTrigger(timeInterval: TimeInterval(seconds), repeats: false)
                    center.add(UNNotificationRequest(identifier: id, content: content, trigger: trigger)) { error in
                        DispatchQueue.main.async {
                            MainActor.assumeIsolated { registration.finish(error == nil ? NTK_NOTIFICATION_ERROR_NONE : NTK_NOTIFICATION_ERROR_UNKNOWN) }
                        }
                    }
                }
            }
        }
        return code(NTK_NOTIFICATION_ERROR_NONE)
    }
}
