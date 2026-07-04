//
//  ShareError.swift
//  IosLibrary
//

import Foundation

/// Errors that can occur during a share operation.
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
    /// No root view controller was available to present the sheet.
    case noRootViewController
    /// The share sheet failed to present or completed with a system error.
    /// - Parameter error: The underlying system error.
    case presentationFailed(Error)
    /// An unknown error occurred.
    /// - Parameter error: The underlying system error.
    case unknown(Error)
}

extension ShareError: LocalizedError {
    public var errorDescription: String? {
        switch self {
        case .noValidItems:
            return "No shareable items were provided."
        case .invalidURL(let value):
            return "Invalid URL: \(value)."
        case .imageLoadFailed(let path):
            return "Failed to load image at path: \(path)."
        case .fileNotFound(let path):
            return "File not found at path: \(path)."
        case .noRootViewController:
            return "No root view controller available to present the share sheet."
        case .presentationFailed(let error):
            return "Failed to present the share sheet: \(error.localizedDescription)."
        case .unknown(let error):
            return "An unknown error occurred: \(error.localizedDescription)."
        }
    }
}
