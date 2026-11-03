//
//  NotificationTrigger.swift
//  IosLibrary
//

import Foundation

/// The condition that triggers a scheduled notification.
public enum NotificationTrigger: Sendable {
    /// Fires after a time interval (in seconds). Set `repeats` to true to repeat. See ``isValid``.
    case timeInterval(TimeInterval, repeats: Bool)
    /// Fires on a specific calendar date components match.
    case calendar(DateComponents, repeats: Bool)
    /// Fires when the device enters or exits a geographic region.
    /// Requires CoreLocation usage description in Info.plist.
    case location(identifier: String, latitude: Double, longitude: Double, radius: Double, notifyOnEntry: Bool, notifyOnExit: Bool)
}

extension NotificationTrigger {
    /// Whether the system accepts this trigger. `false` only for the time intervals that make the
    /// system raise an exception, which ends the process: not above 0, or below 60 when repeating.
    /// The library's repository reports such a trigger from `show`, `update` and `schedule` as
    /// ``NotificationError/invalidTrigger`` and adds nothing. Every other trigger is `true`, also
    /// one the system accepts but never fires (a calendar trigger without components).
    public var isValid: Bool {
        guard case .timeInterval(let interval, let repeats) = self else { return true }
        return interval > 0 && (!repeats || interval >= 60)
    }
}
