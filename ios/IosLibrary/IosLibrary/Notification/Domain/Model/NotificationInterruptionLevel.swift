//
//  NotificationInterruptionLevel.swift
//  IosLibrary
//

import Foundation

/// The interruption level of a notification, controlling how it breaks through Focus modes.
public enum NotificationInterruptionLevel {
    /// Adds to the notification list without lighting the screen or playing a sound.
    case passive
    /// Lights the screen and plays a sound (default behavior).
    case active
    /// Breaks through scheduled delivery and Focus modes.
    case timeSensitive
    /// Breaks through all system controls. Requires a critical alerts entitlement.
    case critical
}
