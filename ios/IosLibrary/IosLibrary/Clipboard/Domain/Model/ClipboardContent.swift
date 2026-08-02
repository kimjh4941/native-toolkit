//
//  ClipboardContent.swift
//  IosLibrary
//

import Foundation

/// Content to write to the clipboard via `copy` or `append`.
public enum ClipboardContent: Equatable, Sendable {
    /// Plain text. Blank text is allowed.
    case plainText(String)
    /// HTML text with a plain-text fallback, written as a single item with two representations.
    case htmlText(plain: String, html: String)
    /// A URL string (`http`/`https`/`file` scheme).
    case url(String)
    /// An image loaded from a file path.
    case imageFile(path: String)
    /// Raw image data with an explicit, known image uniform type identifier.
    case imageData(Data, utType: String)
    /// An RGBA color. Each component must be finite and within `0.0...1.0`.
    case color(red: Double, green: Double, blue: Double, alpha: Double)
    /// Arbitrary data under an application-defined uniform type identifier.
    case customData(Data, utType: String)
    /// Multiple plain-text items of the same form.
    case multipleText([String])
    /// A single item exposing multiple representations, keyed by uniform type identifier.
    case multiRepresentation([String: Data])
}
