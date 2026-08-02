//
//  ClipboardTypeIdentifierValidator.swift
//  IosLibrary
//

import Foundation
import UniformTypeIdentifiers

/// `UTType`-backed implementation of `ClipboardTypeIdentifierValidating`.
///
/// `UTType(_:)` returns `nil` for a syntactically valid but unregistered custom identifier (e.g.
/// an app-defined reverse-DNS type nobody has declared), so `customData` / `multiRepresentation`
/// identifiers additionally accept any syntactically valid reverse-DNS identifier. `imageData`
/// always requires a known, image-conforming UTI since its bytes must be decodable as an image.
public struct ClipboardTypeIdentifierValidator: ClipboardTypeIdentifierValidating {
    public init() {}

    public func validateGeneric(_ identifier: String) throws {
        if UTType(identifier) != nil { return }
        guard Self.isValidCustomIdentifier(identifier) else {
            throw ClipboardError.invalidTypeIdentifier(identifier)
        }
    }

    public func validateImage(_ identifier: String) throws {
        guard let type = UTType(identifier), type.conforms(to: .image) else {
            throw ClipboardError.invalidTypeIdentifier(identifier)
        }
    }

    /// A syntactically valid reverse-DNS identifier: at least two dot-separated segments, each
    /// non-empty, starting with a letter or digit, and containing only letters, digits, `-`, `_`.
    static func isValidCustomIdentifier(_ identifier: String) -> Bool {
        let segments = identifier.split(separator: ".", omittingEmptySubsequences: false)
        guard segments.count >= 2 else { return false }
        for segment in segments {
            guard let first = segment.first, first.isLetter || first.isNumber else { return false }
            guard segment.allSatisfy({ $0.isLetter || $0.isNumber || $0 == "-" || $0 == "_" }) else {
                return false
            }
        }
        return true
    }
}
