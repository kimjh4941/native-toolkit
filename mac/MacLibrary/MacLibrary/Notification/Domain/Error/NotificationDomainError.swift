//
//  NotificationDomainError.swift
//  MacLibrary
//
//  Created by Kim Jong Hyun on 2026/05/09.
//

/// Domain errors that can occur during notification operations.
///
/// Use `errorCode` and `errorMessage` to convert to the public bridge return format
/// `(isSuccess: Bool, errorCode: Int, errorMessage: String?)`.
///
/// - Note: Success is represented as `errorCode == 0` and `errorMessage == nil`.
public enum NotificationDomainError: Error {
    /// The current OS version does not meet the minimum requirement.
    case unsupportedOS(minimum: String)
    /// The user has denied notification permission.
    case permissionDenied
    /// Requesting notification permission failed.
    case permissionRequestFailed(underlying: Error)
    /// The notification content is invalid.
    case invalidContent(reason: String)
    /// The notification trigger is invalid.
    case invalidTrigger(reason: String)
    /// The notification category is invalid.
    case invalidCategory(reason: String)
    /// No pending notification was found for the given identifier.
    case notificationNotFound(identifier: String)
    /// Adding a notification request failed.
    case addFailed(underlying: Error)
    /// Removing a notification failed.
    case removeFailed(underlying: Error)
    /// Querying notifications failed.
    case queryFailed(underlying: Error)
    /// Setting the badge count failed.
    case setBadgeFailed(underlying: Error)
    /// Opening notification settings failed.
    case openSettingsFailed(underlying: Error)
    /// An unknown error occurred.
    case unknown(underlying: Error)

    /// Numeric error code used in the C Bridge return contract.
    public var errorCode: Int {
        switch self {
        case .unsupportedOS:           return 1001
        case .permissionDenied:        return 1002
        case .permissionRequestFailed: return 1003
        case .invalidContent:          return 1101
        case .invalidTrigger:          return 1102
        case .invalidCategory:         return 1103
        case .notificationNotFound:    return 1104
        case .addFailed:               return 1201
        case .removeFailed:            return 1202
        case .queryFailed:             return 1203
        case .setBadgeFailed:          return 1204
        case .openSettingsFailed:      return 1205
        case .unknown:                 return 1999
        }
    }

    /// Human-readable error message used in the C Bridge return contract.
    public var errorMessage: String {
        switch self {
        case .unsupportedOS(let minimum):
            return "Unsupported OS. Requires \(minimum) or later."
        case .permissionDenied:
            return "Notification permission denied."
        case .permissionRequestFailed:
            return "Failed to request notification permission."
        case .invalidContent(let reason):
            return "Invalid notification content: \(reason)"
        case .invalidTrigger(let reason):
            return "Invalid notification trigger: \(reason)"
        case .invalidCategory(let reason):
            return "Invalid notification category: \(reason)"
        case .notificationNotFound(let identifier):
            return "Notification not found: \(identifier)"
        case .addFailed:
            return "Failed to add notification request."
        case .removeFailed:
            return "Failed to remove notification."
        case .queryFailed:
            return "Failed to query notifications."
        case .setBadgeFailed:
            return "Failed to set badge count."
        case .openSettingsFailed:
            return "Failed to open notification settings."
        case .unknown:
            return "Unknown notification error."
        }
    }
}
