// macOS C ABI 1a-9 probe: the C entries (@c @implementation, no Objective-C, D-10). Only _ntk_* are
// exported (NtkProbeMacCApi.exp, D-11).
import Foundation

// Common.h
@c @implementation public func ntk_version() -> UInt32 { UInt32(NTK_VERSION) }
@c @implementation public func ntk_string_data(_ s: OpaquePointer?) -> UnsafePointer<CChar>? {
    Handle.borrow(s, as: NTKString.self).map { UnsafeRawPointer($0.storage).assumingMemoryBound(to: CChar.self) }
}
@c @implementation public func ntk_string_size(_ s: OpaquePointer?) -> Int { Handle.borrow(s, as: NTKString.self)?.count ?? 0 }
@c @implementation public func ntk_string_free(_ s: OpaquePointer?) { Handle.free(s) }

// Probe.h
@c @implementation
public func ntk_probe_thread_info(_ outIsMain: UnsafeMutablePointer<Int32>?, _ outThreadId: UnsafeMutablePointer<UInt64>?,
                                  _ outHasNSApp: UnsafeMutablePointer<Int32>?) -> ntk_probe_error {
    ProbeReceiver.threadInfo(outIsMain, outThreadId, outHasNSApp)
}

@c @implementation
public func ntk_probe_echo_async(_ value: Int32, _ delayMs: UInt32, _ callback: ntk_probe_echo_fn?,
                                 _ userData: UnsafeMutableRawPointer?, _ release: ntk_release_fn?) -> ntk_probe_error {
    ProbeReceiver.echo(value, delayMs, callback, userData, release)
}

@c @implementation public func ntk_probe_describe() -> OpaquePointer? { ProbeReceiver.describe() }
@c @implementation public func ntk_probe_redact_path(_ path: UnsafePointer<CChar>?) -> OpaquePointer? { ProbeReceiver.redact(path) }

// Dialog.h
@c @implementation
public func ntk_dialog_show_alert_async(_ title: UnsafePointer<CChar>?, _ message: UnsafePointer<CChar>?,
                                        _ positiveText: UnsafePointer<CChar>?, _ negativeText: UnsafePointer<CChar>?,
                                        _ autoCloseMs: UInt32, _ callback: ntk_dialog_done_fn?, _ userData: UnsafeMutableRawPointer?,
                                        _ release: ntk_release_fn?, _ outRequestId: UnsafeMutablePointer<UInt64>?) -> ntk_dialog_error {
    DialogReceiver.showAlert(title, message, positiveText, negativeText, autoCloseMs, callback, userData, release, outRequestId,
                             entry: .runLoopBlock)
}

@c @implementation
public func ntk_probe_dialog_show_alert_gcd_async(_ title: UnsafePointer<CChar>?, _ message: UnsafePointer<CChar>?,
                                                  _ positiveText: UnsafePointer<CChar>?, _ negativeText: UnsafePointer<CChar>?,
                                                  _ autoCloseMs: UInt32, _ callback: ntk_dialog_done_fn?,
                                                  _ userData: UnsafeMutableRawPointer?, _ release: ntk_release_fn?,
                                                  _ outRequestId: UnsafeMutablePointer<UInt64>?) -> ntk_dialog_error {
    DialogReceiver.showAlert(title, message, positiveText, negativeText, autoCloseMs, callback, userData, release, outRequestId,
                             entry: .mainQueue)
}

// Share.h
@c @implementation
public func ntk_share_show_async(_ text: UnsafePointer<CChar>?, _ autoCloseMs: UInt32, _ callback: ntk_share_done_fn?,
                                 _ userData: UnsafeMutableRawPointer?, _ release: ntk_release_fn?) -> ntk_share_error {
    ShareReceiver.show(text, autoCloseMs, callback, userData, release)
}

// Notification.h
@c @implementation public func ntk_notification_install() -> ntk_notification_error { NotificationReceiver.install() }

// ProbeNotification.h
@c @implementation
public func ntk_probe_notification_add_listener(_ callback: ntk_probe_notification_event_fn?, _ userData: UnsafeMutableRawPointer?,
                                                _ release: ntk_release_fn?,
                                                _ outListener: UnsafeMutablePointer<OpaquePointer?>?) -> ntk_notification_error {
    NotificationReceiver.addListener(callback, userData, release, outListener)
}

@c @implementation
public func ntk_probe_notification_listener_remove(_ listener: OpaquePointer?) { NotificationReceiver.removeListener(listener) }

@c @implementation
public func ntk_probe_notification_get_launch_response(_ outIdentifier: UnsafeMutablePointer<OpaquePointer?>?,
                                                       _ outAction: UnsafeMutablePointer<OpaquePointer?>?) -> ntk_notification_error {
    NotificationReceiver.launchResponse(outIdentifier, outAction)
}

@c @implementation
public func ntk_probe_notification_request_permission(_ callback: ntk_probe_notification_done_fn?, _ userData: UnsafeMutableRawPointer?,
                                                      _ release: ntk_release_fn?) -> ntk_notification_error {
    NotificationReceiver.requestPermission(callback, userData, release)
}

@c @implementation
public func ntk_probe_notification_get_authorization_status(_ callback: ntk_probe_notification_done_fn?, _ userData: UnsafeMutableRawPointer?,
                                                            _ release: ntk_release_fn?) -> ntk_notification_error {
    NotificationReceiver.authorizationStatus(callback, userData, release)
}

@c @implementation
public func ntk_probe_notification_schedule_marked(_ seconds: UInt32, _ identifier: UnsafePointer<CChar>?, _ title: UnsafePointer<CChar>?,
                                                   _ callback: ntk_probe_notification_done_fn?, _ userData: UnsafeMutableRawPointer?,
                                                   _ release: ntk_release_fn?) -> ntk_notification_error {
    NotificationReceiver.scheduleMarked(seconds, identifier, title, callback, userData, release)
}

@c @implementation
public func ntk_probe_notification_install_at(_ when: Int32) -> ntk_notification_error { NotificationReceiver.installAt(when) }

@c @implementation public func ntk_probe_notification_describe() -> OpaquePointer? { NotificationReceiver.describe() }
