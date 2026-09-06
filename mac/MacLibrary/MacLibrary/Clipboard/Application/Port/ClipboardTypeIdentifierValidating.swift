//
//  ClipboardTypeIdentifierValidating.swift
//  MacLibrary
//

import Foundation

/// Validates uniform type identifier strings before they reach `NSPasteboardItem`.
///
/// `NSPasteboardItem` silently returns `false` for a malformed UTI, so identifiers are
/// checked up front and reported as ``ClipboardError/invalidTypeIdentifier(_:)``.
@MainActor
public protocol ClipboardTypeIdentifierValidating {
    /// Returns `true` when the string is usable as a pasteboard type identifier.
    func isValid(_ identifier: String) -> Bool
}
