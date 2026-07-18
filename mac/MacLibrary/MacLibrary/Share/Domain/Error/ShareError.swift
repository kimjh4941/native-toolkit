//
//  ShareError.swift
//  MacLibrary
//

import Foundation

/// Errors that can occur during a share operation.
///
/// Use `errorCode` and `errorMessage` to convert to the public bridge return format
/// `(isSuccess: Bool, completed: Bool, serviceName: String?, errorMessage: String?)`.
public enum ShareError: Error {
    /// No shareable items were provided (empty or all invalid).
    case noValidItems
    /// A shared URL string could not be parsed.
    /// - Parameter value: The invalid URL string.
    case invalidURL(String)
    /// The image at the given path could not be loaded.
    /// - Parameter path: The file path that failed to load.
    case imageLoadFailed(path: String)
    /// The file at the given path does not exist.
    /// - Parameter path: The missing file path.
    case fileNotFound(path: String)
    /// No key window / view was available to anchor the sharing picker.
    case noAnchorView
    /// The requested named service is unknown or cannot share the items.
    /// - Parameter name: The requested service name.
    case serviceUnavailable(name: String)
    /// Another share operation (picker or direct service) is already in progress on the
    /// same presenter instance.
    case alreadyInProgress
    /// The share failed or completed with a system error.
    /// - Parameter error: The underlying system error.
    case presentationFailed(Error)
    /// An unknown error occurred.
    /// - Parameter error: The underlying system error.
    case unknown(Error)

    /// Numeric error code used in the C Bridge return contract (diagnostics / future use).
    public var errorCode: Int {
        switch self {
        case .noValidItems:         return 1401
        case .invalidURL:           return 1402
        case .imageLoadFailed:      return 1403
        case .fileNotFound:         return 1404
        case .noAnchorView:         return 1405
        case .serviceUnavailable:   return 1406
        case .presentationFailed:   return 1407
        case .alreadyInProgress:    return 1408
        case .unknown:              return 1499
        }
    }

    /// Human-readable error message used in the C Bridge return contract.
    public var errorMessage: String {
        switch self {
        case .noValidItems:
            return "No shareable items were provided."
        case .invalidURL(let value):
            return "Invalid URL: \(value)."
        case .imageLoadFailed(let path):
            return "Failed to load image at path: \(path)."
        case .fileNotFound(let path):
            return "File not found at path: \(path)."
        case .noAnchorView:
            return "No key window available to anchor the sharing picker."
        case .serviceUnavailable(let name):
            return "Sharing service unavailable: \(name)."
        case .alreadyInProgress:
            return "A share operation is already in progress."
        case .presentationFailed(let error):
            return "Failed to share: \(error.localizedDescription)."
        case .unknown(let error):
            return "An unknown share error occurred: \(error.localizedDescription)."
        }
    }
}

extension ShareError: LocalizedError {
    public var errorDescription: String? { errorMessage }
}
