//
//  ShareError.swift
//  IosLibrary
//

import Foundation

/// Errors that can occur during a share operation.
///
/// Every case is stable: none carries an arbitrary system `Error`. A failed share activity
/// carries the `NSError` domain and code of what the system reported (``FailureDetail``).
///
/// | Case | When |
/// |---|---|
/// | ``noValidItems`` | `ShareContent.items` is empty |
/// | ``invalidURL(_:)``, ``imageLoadFailed(path:)``, ``fileNotFound(path:)`` | An item could not be converted |
/// | ``noRootViewController`` | `PresenterSelection.firstActiveScene` found no view controller to present from |
/// | ``notForeground`` | `PresenterSelection.foreground` or `viewController(_:)` found no view controller in the foreground |
/// | ``presentationFailed`` | The view controller to present from was not settled (after the one wait of `.foreground` and `.viewController(_:)`), or UIKit declined the presentation |
/// | ``dismissedBySystem`` | The share sheet went away without reporting a result (dismissed from outside, or its scene was disconnected and the sheet freed) |
/// | ``activityFailed(_:)`` | The sheet ended with an error from the chosen activity |
///
/// The descriptions are fixed English sentences. Those of ``invalidURL(_:)``,
/// ``imageLoadFailed(path:)`` and ``fileNotFound(path:)`` contain the URL or the path that was
/// passed in, as they always did; the library never writes them to its log.
public enum ShareError: Error, Sendable, Equatable {
    /// No shareable items were provided (empty).
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
    /// No root view controller was available to present the sheet (`PresenterSelection.firstActiveScene`).
    case noRootViewController
    /// No view controller in the foreground to present the sheet from (`PresenterSelection.foreground`
    /// or `PresenterSelection.viewController(_:)`).
    case notForeground
    /// The sheet was not presented: the view controller to present from was not settled, or UIKit
    /// declined the presentation.
    case presentationFailed
    /// The presented sheet went away without reporting a result (dismissed from outside the
    /// library, or its scene was disconnected and the sheet freed).
    case dismissedBySystem
    /// The sheet ended with an error from the chosen activity.
    /// - Parameter detail: The `NSError` domain and code of that error.
    case activityFailed(FailureDetail)
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
        case .notForeground:
            return "The app has no view controller in the foreground to present the share sheet."
        case .presentationFailed:
            return "Failed to present the share sheet."
        case .dismissedBySystem:
            return "The share sheet was dismissed without a result."
        case .activityFailed:
            return "The share activity failed."
        }
    }
}
