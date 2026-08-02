//
//  PasteboardCreationRequest.swift
//  IosLibrary
//

import Foundation

/// A request to create a pasteboard.
///
/// Separated from `PasteboardScope` because `withUniqueName()` takes no argument and its
/// generated name is an output, not an input.
public enum PasteboardCreationRequest: Equatable, Sendable {
    /// Creates (or resolves an existing) named pasteboard.
    case named(String)
    /// Creates a pasteboard with a system-generated unique name.
    case unique
}
