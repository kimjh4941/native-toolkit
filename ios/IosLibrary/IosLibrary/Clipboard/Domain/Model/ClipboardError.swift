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
    /// The content to write, or one of its values, is empty (for example HTML with only white
    /// space, empty image data, or an empty value of a representation).
    case emptyContent
    /// The content to write has no items (an empty list of texts or of representations).
    case emptyItemList
    /// No pattern was given to detect.
    case emptyDetectionPatterns
    /// The URL is not a valid `http`, `https` or `file` URL. Carries the string passed in.
    case invalidURL(String)
    /// The uniform type identifier is invalid. Carries the identifier passed in.
    case invalidTypeIdentifier(String)
    /// The pasteboard name is invalid (empty or only white space). Carries the name passed in.
    case invalidPasteboardName(String)
    /// A color component is not finite or not within `0.0...1.0`.
    case invalidColor
    /// The image data could not be decoded as an image.
    case invalidImageData
    /// The expiration date of the copy options is not in the future.
    case invalidExpirationDate
    /// The request is invalid. Carries a fixed English reason (never an input value).
    case invalidRequest(String)
    /// The content exceeds a limit of ``ClipboardLimits``: `byteCount` is the size found and
    /// `limit` the limit exceeded (bytes, or pixels for the pixel count of an image).
    case contentTooLarge(byteCount: Int, limit: Int)
    /// The file at the path does not exist.
    case fileNotFound(path: String)
    /// The image file at the path could not be loaded.
    case imageLoadFailed(path: String)
    /// An image could not be encoded as PNG.
    case imageEncodingFailed
    /// The named or unique pasteboard does not exist, or cannot be created. Carries its name.
    case pasteboardUnavailable(name: String)
    /// The general pasteboard cannot be removed; only a named or unique one can.
    case cannotRemoveGeneralPasteboard
    /// No item on the pasteboard (or among the pasted items) offers the requested type.
    case noMatchingItem
    /// The system failed to load an item. Carries the system error's domain and code.
    case providerLoadFailed(ClipboardFailureDetail)
    /// The loaded item could not be converted to the requested type.
    case unexpectedType
    /// A loaded file could not be copied to the library's temporary directory. Carries the
    /// domain and code of the failure.
    case fileCopyFailed(ClipboardFailureDetail)
    /// The operation was cancelled (a cancelled load, or a cancelled calling task). Callers may
    /// treat it as a normal, ignorable outcome.
    case cancelled
    /// The operation did not finish within its timeout of ``ClipboardTimeouts``.
    case timedOut(operation: ClipboardOperationKind)
    /// The system failed to detect patterns or values. Carries the system error's domain and code.
    case detectionFailed(ClipboardFailureDetail)
    /// An error that could not be classified. Carries its domain and code.
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
