// Stage 1a throwaway: prototype of `ntk_notification_install` (D-4, D-6). Synchronous, main
// thread only, never waits for the main thread. The error numbers are placeholders.
import Foundation
import UserNotifications

let NTK_OK: Int32 = 0
/// Placeholder: called off the main thread. Returned at once; nothing is queued.
let NTK_ERR_NOT_MAIN_THREAD: Int32 = 16
/// Placeholder: the proxy was installed before and someone replaced it (policy `.refuse`).
let NTK_ERR_REPLACED: Int32 = 17

final class Installer: @unchecked Sendable {
    enum OnReplaced { case reinstall, refuse }

    static let shared = Installer()
    /// The library keeps the only strong reference; the center holds its delegate weakly.
    let proxy = ForwardingDelegate()
    var onReplaced = OnReplaced.reinstall
    private var installedOnce = false

    /// Must run on the main thread.
    func installOnMain() -> Int32 {
        let center = UNUserNotificationCenter.current()
        let current = center.delegate
        if let current, (current as AnyObject) === proxy {
            plog("install.noop")
            return NTK_OK
        }
        if installedOnce {
            plog("install.replacedDetected", ["current": current.map { String(describing: type(of: $0)) } ?? "nil"])
            if onReplaced == .refuse { return NTK_ERR_REPLACED }
        }
        proxy.previous = current
        center.delegate = proxy
        installedOnce = true
        plog("install.set", ["previous": current.map { String(describing: type(of: $0)) } ?? "nil"])
        return NTK_OK
    }
}

@_cdecl("ntk_notification_install")
public func ntk_notification_install() -> Int32 {
    let onMainThread = pthread_main_np() != 0
    plog("install.enter", ["pthread_main": "\(onMainThread)", "isMainThread": "\(Thread.isMainThread)"])
    guard onMainThread else {
        plog("install.reject", ["code": "\(NTK_ERR_NOT_MAIN_THREAD)"])
        return NTK_ERR_NOT_MAIN_THREAD
    }
    let code = Installer.shared.installOnMain()
    let isProxy = (UNUserNotificationCenter.current().delegate as AnyObject?) === Installer.shared.proxy
    plog("install.return", ["code": "\(code)", "delegateIsProxy": "\(isProxy)"])
    return code
}
