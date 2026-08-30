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

    /// Returns `true` when the identifier can name a promised file.
    ///
    /// A promised file must resolve to a type conforming to `public.data` or
    /// `public.directory`. The check belongs to the port because the application layer decides
    /// ``ClipboardError/filePromiseTypeInvalid(_:)``, and it must do so without seeing `UTType`.
    func isValidFileType(_ identifier: String) -> Bool
}
