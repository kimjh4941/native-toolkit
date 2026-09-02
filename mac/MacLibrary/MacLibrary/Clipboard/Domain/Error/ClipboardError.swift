//
//  ClipboardError.swift
//  MacLibrary
//

import Foundation

/// Errors raised by the clipboard feature.
///
/// Use ``errorCode`` and ``errorMessage`` to convert to the C bridge return contract
/// `(isSuccess: Bool, errorCode: Int, errorMessage: String?)`. Success is represented as
/// `errorCode == 0` and `errorMessage == nil`.
///
/// Failures at the bridge boundary (JSON parsing, missing required arguments) use
/// `BridgeError` (1301 / 1302) instead and are never represented here.
///
/// - Note: Cancellation is deliberately narrow. `ClipboardError/cancelled` covers only the
///   detection APIs.
public enum ClipboardError: Error, Equatable {
    /// No items were supplied to a copy or append.
    case emptyContent
    /// The item at `itemIndex` carries no representations.
    case emptyRepresentations(itemIndex: Int)
    /// An empty pattern set was passed to a detection API.
    case emptyDetectionPatterns
    /// The string is not a usable uniform type identifier.
    case invalidTypeIdentifier(String)
    /// The pasteboard name is empty or otherwise unusable.
    case invalidPasteboardName(String)
    /// A representation, or the whole payload, exceeds the hard limit.
    case contentTooLarge(bytes: Int, limit: Int)
    /// The pasteboard could not be read (for example `pasteboardItems` returned nil).
    case pasteboardUnavailable(name: String)
    /// `releaseGlobally()` was requested for the general or another standard pasteboard.
    case cannotReleaseStandardPasteboard(name: String)
    /// `writeObjects(_:)` rejected a copy.
    case writeRejected
    /// `writeObjects(_:)` rejected an append.
    case appendRejected
    /// The pasteboard changed owner since the ownership token was issued, so append is
    /// no longer possible.
    case ownershipLost(expected: Int, actual: Int)
    /// An empty type filter was supplied. Pass `nil` to disable filtering instead.
    case emptyTypeFilter
    /// Pasteboard detection is unavailable below the given macOS version.
    case detectionUnavailable(minimumOS: String)
    /// The user denied access to the pasteboard contents during detection.
    case detectionDenied
    /// Detection failed for a reason other than denial.
    case detectionFailed(String)
    /// Loading one pasted item provider failed.
    case pasteLoadFailed(String)
    /// Loading pasted items exceeded the timeout.
    case pasteLoadTimedOut(seconds: Int)
    /// A configuration value violates its documented constraints.
    case invalidConfiguration(String)
    /// A detection API was cancelled.
    case cancelled
    /// Any other failure.
    case unknown(String)

    /// Numeric code used by the C bridge return contract.
    public var errorCode: Int {
        switch self {
        case .emptyContent:                    return 1501
        case .emptyRepresentations:            return 1502
        case .emptyDetectionPatterns:          return 1503
        case .invalidTypeIdentifier:           return 1504
        case .invalidPasteboardName:           return 1505
        case .contentTooLarge:                 return 1506
        case .pasteboardUnavailable:           return 1507
        case .cannotReleaseStandardPasteboard: return 1508
        case .writeRejected:                   return 1509
        case .appendRejected:                  return 1510
        case .ownershipLost:                   return 1511
        case .emptyTypeFilter:                 return 1512
        case .detectionUnavailable:            return 1513
        case .detectionDenied:                 return 1514
        case .detectionFailed:                 return 1515
        case .pasteLoadFailed:                 return 1521
        case .pasteLoadTimedOut:               return 1522
        case .invalidConfiguration:            return 1523
        case .cancelled:                       return 1524
        case .unknown:                         return 1599
        }
    }

    /// Human readable message used by the C bridge return contract.
    public var errorMessage: String {
        switch self {
        case .emptyContent:
            return "No clipboard content was provided."
        case .emptyRepresentations(let index):
            return "Clipboard item at index \(index) has no representations."
        case .emptyDetectionPatterns:
            return "No detection patterns were specified."
        case .invalidTypeIdentifier(let value):
            return "Invalid uniform type identifier: \(value)."
        case .invalidPasteboardName(let value):
            return "Invalid pasteboard name: \(value)."
        case .contentTooLarge(let bytes, let limit):
            return "Clipboard content is too large: \(bytes) bytes (limit \(limit))."
        case .pasteboardUnavailable(let name):
            return "Pasteboard is unavailable: \(name)."
        case .cannotReleaseStandardPasteboard(let name):
            return "Standard pasteboard cannot be released: \(name)."
        case .writeRejected:
            return "The pasteboard rejected the write operation."
        case .appendRejected:
            return "The pasteboard rejected the append operation."
        case .ownershipLost(let expected, let actual):
            return "Pasteboard ownership was lost (expected change count \(expected), "
                + "found \(actual)). Append is only possible while this app owns the pasteboard."
        case .emptyTypeFilter:
            return "The type filter must not be empty. Pass nil to disable filtering."
        case .detectionUnavailable(let minimumOS):
            return "Pasteboard detection requires macOS \(minimumOS) or later."
        case .detectionDenied:
            return "The user denied access to the pasteboard contents."
        case .detectionFailed(let reason):
            return "Pasteboard detection failed: \(reason)."
        case .pasteLoadFailed(let reason):
            return "Failed to load pasted item: \(reason)."
        case .pasteLoadTimedOut(let seconds):
            return "Loading pasted items timed out after \(seconds) seconds."
        case .invalidConfiguration(let reason):
            return "Invalid configuration: \(reason)."
        case .cancelled:
            return "The clipboard operation was cancelled."
        case .unknown(let reason):
            return "An unknown clipboard error occurred: \(reason)."
        }
    }
}

extension ClipboardError: LocalizedError {
    /// `LocalizedError` conformance; returns ``errorMessage``.
    public var errorDescription: String? { errorMessage }
}
