//
//  DialogError.swift
//  IosLibrary
//

import Foundation

/// Why a dialog request ended without an answer.
///
/// | Case | When |
/// |---|---|
/// | ``canceled`` | `IosDialogManager.cancel(_:)` closed the request |
/// | ``dismissedBySystem`` | The dialog went away without a button being pressed (dismissed from outside, or its scene was disconnected and the dialog freed) |
/// | ``notForeground`` | No view controller to present from was found |
/// | ``presentationFailed`` | The view controller to present from was still not settled after waiting once, or UIKit declined the presentation |
/// | ``invalidRequest`` | The ``RequestBox`` passed in is already used by another request |
///
/// The texts of `errorDescription` are fixed English sentences.
public enum DialogError: Error, Sendable, Equatable, LocalizedError {
    /// The request was cancelled through `IosDialogManager.cancel(_:)`.
    case canceled
    /// The dialog went away without one of its buttons being pressed.
    case dismissedBySystem
    /// No view controller in the foreground to present the dialog from.
    case notForeground
    /// The dialog could not be presented.
    case presentationFailed
    /// The request box is already used by another request.
    case invalidRequest

    /// A fixed English description of the case.
    public var errorDescription: String? {
        switch self {
        case .canceled: return "The dialog was canceled."
        case .dismissedBySystem: return "The dialog was dismissed without an answer."
        case .notForeground: return "No view controller in the foreground to present the dialog from."
        case .presentationFailed: return "Failed to present the dialog."
        case .invalidRequest: return "The request box is already used by another request."
        }
    }
}
