//
//  ShareItem.swift
//  IosLibrary
//

import Foundation

/// A single item to be shared through the system share sheet.
public enum ShareItem {
    /// Plain text.
    case text(String)
    /// A web or file URL, held as a raw string. Validated/parsed in the Data layer
    /// (invalid strings surface as `ShareError.invalidURL`).
    case url(String)
    /// An image located at a local file path.
    case imageFile(path: String)
    /// An arbitrary file located at a local file path.
    case file(path: String)
}
