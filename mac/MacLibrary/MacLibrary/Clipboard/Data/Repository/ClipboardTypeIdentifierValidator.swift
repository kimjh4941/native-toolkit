//
//  ClipboardTypeIdentifierValidator.swift
//  MacLibrary
//

import Foundation
import UniformTypeIdentifiers

/// Validates uniform type identifiers against `UTType`.
///
/// The type lives in the data layer because `UTType` is a platform type that must not reach
/// the domain or application layers (RK-18). Callers see only `String`.
@MainActor
final class ClipboardTypeIdentifierValidator: ClipboardTypeIdentifierValidating {

    private let TAG = "ClipboardTypeIdentifierValidator"

    init() {}

    /// Whether the string is usable as a pasteboard type identifier.
    ///
    /// This is deliberately **not** `UTType(identifier) != nil`. `UTType` resolves only
    /// identifiers the system knows about, while the pasteboard accepts any well formed one.
    /// Measured on macOS 26.3, `NSPasteboardItem.setData(_:forType:)` accepts
    /// `com.mycompany.myformat` even though no app declares it, and the value round trips
    /// through a real pasteboard. Validating with `UTType` would therefore reject an app's own
    /// custom format, which is a legitimate thing to put on a pasteboard.
    ///
    /// The rule below is the one `setData` enforces, derived by measurement; the suite in
    /// `ClipboardTypeIdentifierValidatorTests` pins every probed case so a change in a future
    /// macOS fails a test rather than production.
    func isValid(_ identifier: String) -> Bool {
        Log.d(TAG, "[isValid] identifier: \(identifier)")
        let segments = identifier.split(separator: ".", omittingEmptySubsequences: false)
        // A single segment is rejected: "abc" fails, "a.b" is accepted.
        guard segments.count >= 2 else { return false }
        return segments.allSatisfy(Self.isValidSegment)
    }

    /// A segment must be non-empty ASCII alphanumerics and hyphens, starting and ending with an
    /// alphanumeric. Interior runs of hyphens are allowed: `a.b--c` is accepted, `a.b-` is not.
    private static func isValidSegment(_ segment: Substring) -> Bool {
        guard let first = segment.first, let last = segment.last else { return false }
        guard first.isASCIIAlphanumeric, last.isASCIIAlphanumeric else { return false }
        return segment.allSatisfy { $0.isASCIIAlphanumeric || $0 == "-" }
    }

    /// Whether `identifier` conforms to `other`.
    ///
    /// Type filters match by conformance rather than by equality, so a filter of `public.text`
    /// also selects `public.utf8-plain-text`. An identifier that does not resolve conforms to
    /// nothing, and therefore never matches.
    func conforms(_ identifier: String, to other: String) -> Bool {
        Log.d(TAG, "[conforms] identifier: \(identifier), other: \(other)")
        // A type always conforms to itself. The equality check comes first because an app's own
        // undeclared identifier has no `UTType`, and without this a filter naming that exact
        // type would never match the item it was written as.
        if identifier == other { return isValid(identifier) }
        guard let type = UTType(identifier), let target = UTType(other) else { return false }
        return type.conforms(to: target)
    }

    /// Whether `identifier` conforms to at least one of `others`.
    ///
    /// An empty filter list matches nothing. Callers reject an empty filter with
    /// ``ClipboardError/emptyTypeFilter`` before reaching this point; the behaviour here keeps
    /// the function total rather than duplicating that check.
    func conforms(_ identifier: String, toAnyOf others: [String]) -> Bool {
        Log.d(TAG, "[conforms] identifier: \(identifier), others: \(ClipboardLog.types(others))")
        return others.contains { conforms(identifier, to: $0) }
    }

    /// Whether the identifier is usable as a file promise type.
    ///
    /// A promised file has to resolve to a type that conforms to `public.data` or
    /// `public.directory`; anything else cannot be written to disk by the promise machinery.
    func isValidFileType(_ identifier: String) -> Bool {
        Log.d(TAG, "[isValidFileType] identifier: \(identifier)")
        guard let type = UTType(identifier) else { return false }
        return type.conforms(to: .data) || type.conforms(to: .directory)
    }
}

private extension Character {
    /// ASCII letters and digits only. `Character.isLetter` would accept non-ASCII scripts,
    /// which the pasteboard rejects.
    var isASCIIAlphanumeric: Bool {
        isASCII && (isLetter || isNumber)
    }
}
