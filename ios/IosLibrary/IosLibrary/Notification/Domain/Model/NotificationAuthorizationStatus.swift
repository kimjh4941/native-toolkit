//
//  NotificationAuthorizationStatus.swift
//  IosLibrary
//

import Foundation

/// Platform-agnostic notification authorization status.
public enum NotificationAuthorizationStatus: String, Sendable {
    case notDetermined
    case denied
    case authorized
    case provisional
    case ephemeral
    case unknown
}
