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

extension ClipboardLoadRequest {
    /// The kind of the request (`text`, `url`, `image`, `file`), without the type identifier.
    var logKind: String {
        switch self {
        case .text: return "text"
        case .url: return "url"
        case .image: return "image"
        case .file: return "file"
        }
    }

    /// The type identifier of a `.file` request (caller-supplied: log it `.private`), `-` otherwise.
    var logTypeIdentifier: String {
        if case .file(let utType) = self { return utType }
        return "-"
    }
}

extension Result where Success == ClipboardLoadedItem, Failure == ClipboardError {
    /// `success(<kind>)` or `failure(<errorCode>)`: never the loaded value, its type identifier or
    /// its file URL.
    var logKind: String {
        switch self {
        case .success(.text): return "success(text)"
        case .success(.url): return "success(url)"
        case .success(.imageData): return "success(imageData)"
        case .success(.file): return "success(file)"
        case .failure(let error): return "failure(\(error.errorCode))"
        }
    }
}
