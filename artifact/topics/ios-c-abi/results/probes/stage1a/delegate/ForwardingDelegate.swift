// Stage 1a throwaway: prototype of the forwarding UNUserNotificationCenterDelegate (D-7).
// It is installed over the host's delegate, keeps the previous one weakly, handles the library's
// notifications itself and forwards the others. Not shipped; the 1b design decides the real shape.
import Foundation
import UserNotifications

/// userInfo key the 2.0.0 library would put in every notification it schedules.
let ntkMarkerKey = "com.jonghyunkim.nativetoolkit"

/// Calls the wrapped completion at most once; later calls are dropped and logged.
final class Once<T>: @unchecked Sendable {
    private let lock = NSLock()
    private var completion: ((T) -> Void)?
    private var calls = 0
    private let label: String

    init(_ label: String, _ completion: @escaping (T) -> Void) {
        self.label = label
        self.completion = completion
    }

    var isDone: Bool { lock.withLock { completion == nil } }

    @discardableResult
    func call(_ value: T, by caller: String) -> Bool {
        let (fn, n): (((T) -> Void)?, Int) = lock.withLock {
            calls += 1
            let fn = completion
            completion = nil
            return (fn, calls)
        }
        guard let fn else {
            plog("once.drop", ["label": label, "by": caller, "call": "\(n)"])
            return false
        }
        plog("once.system", ["label": label, "by": caller, "call": "\(n)"])
        fn(value)
        return true
    }
}

final class ForwardingDelegate: NSObject, UNUserNotificationCenterDelegate, @unchecked Sendable {
    struct Policy {
        /// Seconds after which the proxy calls the system completion itself when the previous
        /// delegate has not. 0 turns the watchdog off.
        var watchdog: Double = 0
        /// Refuses to forward a call that comes back to the proxy while it is forwarding it.
        var cycleGuard = true
        /// Foreground options for the library's notifications and for unmarked ones nobody claims.
        var libraryOptions: UNNotificationPresentationOptions = [.banner, .list]
    }

    static let wpSel = #selector(UNUserNotificationCenterDelegate.userNotificationCenter(_:willPresent:withCompletionHandler:))
    static let drSel = #selector(UNUserNotificationCenterDelegate.userNotificationCenter(_:didReceive:withCompletionHandler:))
    static let osSel = #selector(UNUserNotificationCenterDelegate.userNotificationCenter(_:openSettingsFor:))

    var policy = Policy()
    /// The delegate that was set before the proxy. Weak, like `UNUserNotificationCenter.delegate`.
    weak var previous: (any UNUserNotificationCenterDelegate)?
    private let lock = NSLock()
    private var forwarding = Set<String>()

    enum Kind: String { case library, push, unmarked }

    func kind(of notification: UNNotification) -> Kind {
        if notification.request.content.userInfo[ntkMarkerKey] != nil { return .library }
        if notification.request.trigger is UNPushNotificationTrigger { return .push }
        return .unmarked
    }

    /// Returns false when `key` is already being forwarded (the call came back to the proxy).
    private func enter(_ key: String) -> Bool {
        lock.withLock { forwarding.insert(key).inserted }
    }

    private func leave(_ key: String) {
        _ = lock.withLock { forwarding.remove(key) }
    }

    private func previousResponds(_ sel: Selector) -> (any UNUserNotificationCenterDelegate)? {
        guard let prev = previous, prev.responds(to: sel) else { return nil }
        return prev
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        let id = notification.request.identifier
        let k = kind(of: notification)
        plog("proxy.willPresent", ["id": id, "kind": k.rawValue])
        let once = Once("wp:\(id)", completionHandler)
        let key = "wp:\(id)"
        if k == .library {
            plog("lib.willPresent", ["id": id])
            once.call(policy.libraryOptions, by: "proxy.library")
            return
        }
        guard let prev = previousResponds(Self.wpSel) else {
            plog("lib.willPresent", ["id": id, "unclaimed": "1"])
            once.call(policy.libraryOptions, by: "proxy.unclaimed")
            return
        }
        if policy.cycleGuard && !enter(key) {
            plog("proxy.cycle", ["method": "willPresent", "id": id])
            once.call(policy.libraryOptions, by: "proxy.cycle")
            return
        }
        if !policy.cycleGuard { _ = enter(key) }
        prev.userNotificationCenter?(center, willPresent: notification) { options in
            once.call(options, by: "previous")
        }
        leave(key)
        plog("proxy.forwarded", ["method": "willPresent", "id": id, "doneOnReturn": "\(once.isDone)"])
        armWatchdog(once, value: [], id: id)
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        let id = response.notification.request.identifier
        let k = kind(of: response.notification)
        plog("proxy.didReceive", ["id": id, "kind": k.rawValue, "action": response.actionIdentifier])
        let once = Once<Void>("dr:\(id)", { _ in completionHandler() })
        let key = "dr:\(id)"
        if k == .library {
            plog("lib.event", ["id": id, "action": response.actionIdentifier])
            once.call((), by: "proxy.library")
            return
        }
        guard let prev = previousResponds(Self.drSel) else {
            plog("lib.event", ["id": id, "action": response.actionIdentifier, "unclaimed": "1"])
            once.call((), by: "proxy.unclaimed")
            return
        }
        if policy.cycleGuard && !enter(key) {
            plog("proxy.cycle", ["method": "didReceive", "id": id])
            once.call((), by: "proxy.cycle")
            return
        }
        if !policy.cycleGuard { _ = enter(key) }
        prev.userNotificationCenter?(center, didReceive: response) {
            once.call((), by: "previous")
        }
        leave(key)
        plog("proxy.forwarded", ["method": "didReceive", "id": id, "doneOnReturn": "\(once.isDone)"])
        armWatchdog(once, value: (), id: id)
    }

    func userNotificationCenter(_ center: UNUserNotificationCenter, openSettingsFor notification: UNNotification?) {
        let id = notification?.request.identifier ?? "nil"
        let k = notification.map { kind(of: $0).rawValue } ?? "nil"
        plog("proxy.openSettings", ["id": id, "kind": k])
        if notification.map({ kind(of: $0) }) != .library, let prev = previousResponds(Self.osSel) {
            prev.userNotificationCenter?(center, openSettingsFor: notification)
            plog("proxy.forwarded", ["method": "openSettings", "id": id])
            return
        }
        plog("lib.openSettings", ["id": id])
    }

    private func armWatchdog<T>(_ once: Once<T>, value: T, id: String) {
        guard policy.watchdog > 0, !once.isDone else { return }
        let box = UncheckedBox(value)
        DispatchQueue.main.asyncAfter(deadline: .now() + policy.watchdog) {
            if !once.isDone {
                plog("proxy.watchdog", ["id": id])
                once.call(box.value, by: "watchdog")
            }
        }
    }
}

struct UncheckedBox<T>: @unchecked Sendable {
    let value: T
    init(_ value: T) { self.value = value }
}
