// Hand-off 2 probe: Notification.h and ProbeNotification.h entry points.
import Foundation

@c @implementation
public func ntk_notification_install() -> ntk_notification_error { NotificationReceiver.install() }

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
public func ntk_probe_notification_schedule_marked(_ seconds: UInt32, _ identifier: UnsafePointer<CChar>?, _ title: UnsafePointer<CChar>?,
                                                   _ callback: ntk_probe_notification_done_fn?, _ userData: UnsafeMutableRawPointer?,
                                                   _ release: ntk_release_fn?) -> ntk_notification_error {
    NotificationReceiver.scheduleMarked(seconds, identifier, title, callback, userData, release)
}
