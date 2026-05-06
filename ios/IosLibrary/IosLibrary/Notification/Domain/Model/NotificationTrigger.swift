//
//  NotificationTrigger.swift
//  IosLibrary
//

import Foundation

/// The condition that triggers a scheduled notification.
public enum NotificationTrigger {
    /// Fires after a time interval (in seconds). Set `repeats` to true to repeat.
    case timeInterval(TimeInterval, repeats: Bool)
    /// Fires on a specific calendar date components match.
    case calendar(DateComponents, repeats: Bool)
    /// Fires when the device enters or exits a geographic region.
    /// Requires CoreLocation usage description in Info.plist.
    case location(identifier: String, latitude: Double, longitude: Double, radius: Double, notifyOnEntry: Bool, notifyOnExit: Bool)
}
