//
//  ClipboardError.swift
//  IosLibrary
//

import Foundation

/// Domain errors for clipboard operations.
///
/// Public messages (`errorDescription`) are fixed, English, per-case strings that never embed
/// input values (URL, path, pasteboard name, or invalid reason). System failures are normalized
/// into `ClipboardFailureDetail` before being attached; the original `Error` is never retained.
public enum ClipboardError: Error, Equatable {
    case emptyContent
    case emptyItemList
    case emptyDetectionPatterns
    case invalidURL(String)
    case invalidTypeIdentifier(String)
    case invalidPasteboardName(String)
    case invalidColor
    case invalidImageData
    case invalidExpirationDate
    case invalidRequest(String)
    case contentTooLarge(byteCount: Int, limit: Int)
    case fileNotFound(path: String)
    case imageLoadFailed(path: String)
    case imageEncodingFailed
    case pasteboardUnavailable(name: String)
    case cannotRemoveGeneralPasteboard
    case noMatchingItem
    case providerLoadFailed(ClipboardFailureDetail)
    case unexpectedType
    case fileCopyFailed(ClipboardFailureDetail)
    case cancelled
    case timedOut(operation: ClipboardOperationKind)
    case detectionFailed(ClipboardFailureDetail)
    case unknown(ClipboardFailureDetail)

    /// Stable error code used when a system error cannot be classified as `ClipboardError`.
    public static let unknownErrorCode = "CLIPBOARD_UNKNOWN"
    /// Fixed message used when a system error cannot be classified as `ClipboardError`.
    public static let unknownMessage = "An unknown error occurred."
}

extension ClipboardError: LocalizedError {
    /// Stable, cross-platform error code. Shared with the Android `CLIPBOARD_*` codes where the
    /// underlying meaning is common; iOS-specific cases use iOS-only codes.
    public var errorCode: String {
        switch self {
        case .emptyContent: return "CLIPBOARD_EMPTY_CONTENT"
        case .emptyItemList: return "CLIPBOARD_EMPTY_ITEMS"
        case .emptyDetectionPatterns: return "CLIPBOARD_EMPTY_PATTERNS"
        case .invalidURL: return "CLIPBOARD_INVALID_URL"
        case .invalidTypeIdentifier: return "CLIPBOARD_INVALID_TYPE"
        case .invalidPasteboardName: return "CLIPBOARD_INVALID_NAME"
        case .invalidColor: return "CLIPBOARD_INVALID_COLOR"
        case .invalidImageData: return "CLIPBOARD_INVALID_IMAGE_DATA"
        case .invalidExpirationDate: return "CLIPBOARD_INVALID_EXPIRATION"
        case .invalidRequest: return "CLIPBOARD_INVALID_REQUEST"
        case .contentTooLarge: return "CLIPBOARD_CONTENT_TOO_LARGE"
        case .fileNotFound: return "CLIPBOARD_FILE_NOT_FOUND"
        case .imageLoadFailed: return "CLIPBOARD_IMAGE_LOAD_FAILED"
        case .imageEncodingFailed: return "CLIPBOARD_IMAGE_ENCODE_FAILED"
        case .pasteboardUnavailable: return "CLIPBOARD_UNAVAILABLE"
        case .cannotRemoveGeneralPasteboard: return "CLIPBOARD_CANNOT_REMOVE_GENERAL"
        case .noMatchingItem: return "CLIPBOARD_NO_MATCHING_ITEM"
        case .providerLoadFailed: return "CLIPBOARD_LOAD_FAILED"
        case .unexpectedType: return "CLIPBOARD_UNEXPECTED_TYPE"
        case .fileCopyFailed: return "CLIPBOARD_FILE_COPY_FAILED"
        case .cancelled: return "CLIPBOARD_CANCELLED"
        case .timedOut: return "CLIPBOARD_TIMED_OUT"
        case .detectionFailed: return "CLIPBOARD_DETECTION_FAILED"
        case .unknown: return Self.unknownErrorCode
        }
    }

    /// Fixed, English, per-case message. Never embeds the associated input value.
    public var errorDescription: String? {
        switch self {
        case .emptyContent:
            return "Clipboard content is empty. Please provide text or HTML."
        case .emptyItemList:
            return "No items provided for clipboard copy."
        case .emptyDetectionPatterns:
            return "No detection patterns were specified."
        case .invalidURL:
            return "The URL is invalid."
        case .invalidTypeIdentifier:
            return "The uniform type identifier is invalid."
        case .invalidPasteboardName:
            return "The pasteboard name is invalid."
        case .invalidColor:
            return "Color components must be finite and within 0.0...1.0."
        case .invalidImageData:
            return "The provided image data could not be decoded."
        case .invalidExpirationDate:
            return "expirationDate must be in the future."
        case .invalidRequest:
            return "The request is invalid."
        case .contentTooLarge:
            return "The clipboard content exceeds the configured size limit."
        case .fileNotFound:
            return "The requested file was not found."
        case .imageLoadFailed:
            return "Failed to load the image."
        case .imageEncodingFailed:
            return "Failed to encode the pasted image."
        case .pasteboardUnavailable:
            return "The requested pasteboard is unavailable."
        case .cannotRemoveGeneralPasteboard:
            return "The general pasteboard cannot be removed."
        case .noMatchingItem:
            return "No clipboard item matches the requested type."
        case .providerLoadFailed:
            return "Failed to load the clipboard item."
        case .unexpectedType:
            return "The clipboard item could not be converted to the requested type."
        case .fileCopyFailed:
            return "Failed to copy the pasted file."
        case .cancelled:
            return "The clipboard load was cancelled."
        case .timedOut:
            return "The clipboard operation timed out."
        case .detectionFailed:
            return "Pattern detection failed."
        case .unknown:
            return Self.unknownMessage
        }
    }

    /// Optional, non-sensitive diagnostic detail (domain + numeric code only). Never includes
    /// `debugMessage`, and never present for cases that do not carry a `ClipboardFailureDetail`.
    public var diagnosticDetail: ClipboardFailureDetail? {
        switch self {
        case .providerLoadFailed(let detail), .fileCopyFailed(let detail),
             .detectionFailed(let detail), .unknown(let detail):
            return detail
        default:
            return nil
        }
    }
}
