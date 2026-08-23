//
//  ClipboardLog.swift
//  IosLibrary
//

import Foundation

/// Thin library-internal wrapper around `ClipboardRedaction`, for call sites within
/// `IosLibrary` that want the redaction helpers without spelling out the `@objc` facade name.
enum ClipboardLog {
    static func redactedText(_ value: String) -> String { ClipboardRedaction.text(value) }
    static func redactedData(byteCount: Int) -> String { ClipboardRedaction.dataByteCount(byteCount) }
    static func redactedJSON(_ value: String) -> String { ClipboardRedaction.json(value) }
    static func redactedPath(_ value: String) -> String { ClipboardRedaction.path(value) }

    /// Non-sensitive diagnostic string: domain + code only. Never includes `debugMessage`.
    static func describe(_ detail: ClipboardFailureDetail) -> String {
        "domain=\(detail.domain), code=\(detail.code)"
    }
}

extension PasteboardScope {
    /// Log-safe description. Reveals only the scope kind (and the name's length for named/unique
    /// scopes) — never the pasteboard name itself, which may identify an App Group or otherwise
    /// leak caller-chosen identifiers into logs.
    var redactedDescription: String {
        switch self {
        case .general: return "general"
        case .named(let name): return "named(nameLength:\(name.utf8.count))"
        case .unique(let name): return "unique(nameLength:\(name.utf8.count))"
        }
    }
}

extension PasteboardCreationRequest {
    /// Log-safe description. See `PasteboardScope.redactedDescription`.
    var redactedDescription: String {
        switch self {
        case .named(let name): return "named(nameLength:\(name.utf8.count))"
        case .unique: return "unique"
        }
    }
}
