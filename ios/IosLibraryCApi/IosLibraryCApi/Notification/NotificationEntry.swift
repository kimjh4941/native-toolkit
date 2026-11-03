//
//  NotificationEntry.swift
//  IosLibraryCApi
//

// The entry points of Notification.h (C ABI design part 1, 5.3). Only @c @implementation functions;
// what they do is in NotificationReceiver.swift.

@c @implementation
public func ntk_notification_install() -> ntk_notification_error {
    NotificationReceiver.install()
}
