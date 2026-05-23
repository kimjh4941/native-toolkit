//
//  NotificationAuthorizationStatus.swift
//  MacLibrary
//
//  Created by Kim Jong Hyun on 2026/05/09.
//

/// The current notification authorization status granted by the user.
public enum NotificationAuthorizationStatus {
    /// The user has not yet been asked for permission.
    case notDetermined
    /// The user has denied permission.
    case denied
    /// The user has granted permission.
    case authorized
    /// Provisional authorization; notifications are delivered quietly.
    case provisional
    /// Authorization status is not applicable on this OS version.
    case unsupported
}
