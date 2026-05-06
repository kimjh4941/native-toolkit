//
//  NotificationSound.swift
//  IosLibrary
//

import Foundation

/// The sound played when a notification is delivered.
public enum NotificationSound {
    /// The default notification sound.
    case `default`
    /// The default critical alert sound.
    case defaultCritical
    /// A custom sound identified by file name (without extension).
    /// - Parameter name: The file name of the custom sound.
    case named(String)
}
