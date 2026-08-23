//
//  ClipboardTypeIdentifierValidating.swift
//  IosLibrary
//

import Foundation

/// Validates uniform type identifiers without exposing `UTType` (a `UniformTypeIdentifiers` /
/// Data-layer type) to the Application layer.
public protocol ClipboardTypeIdentifierValidating: Sendable {
    /// Validates an identifier used for `customData`, `multiRepresentation` keys, or `readData`.
    /// Accepts a resolvable standard UTI, or a syntactically valid custom (reverse-DNS) identifier
    /// that need not be registered by any installed app.
    /// - Throws: `ClipboardError.invalidTypeIdentifier` if neither applies.
    func validateGeneric(_ identifier: String) throws

    /// Validates an identifier used for `imageData`. Must resolve as a known UTI that conforms to
    /// `UTType.image`.
    /// - Throws: `ClipboardError.invalidTypeIdentifier` if not a known, image-conforming UTI.
    func validateImage(_ identifier: String) throws
}
