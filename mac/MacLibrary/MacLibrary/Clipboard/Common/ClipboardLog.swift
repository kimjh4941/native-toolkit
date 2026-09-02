//
//  ClipboardLog.swift
//  MacLibrary
//

import Foundation

/// Redaction helpers for clipboard logging.
///
/// Clipboard payloads routinely contain passwords, tokens and personal data, so the logging
/// rule that every method logs its parameters has to be satisfied without echoing the
/// contents. These helpers describe shape and size instead of value.
public enum ClipboardLog {

    /// Describes a string by length only.
    public static func text(_ value: String?) -> String {
        guard let value else { return "text(nil)" }
        return "text(len:\(value.count))"
    }

    /// Describes bytes by size only.
    public static func data(_ value: Data?) -> String {
        guard let value else { return "data(nil)" }
        return "data(bytes:\(value.count))"
    }

    /// Describes a URL by scheme and host only. Path and query are never logged.
    public static func url(_ value: URL?) -> String {
        guard let value else { return "url(nil)" }
        let scheme = value.scheme ?? "?"
        if value.isFileURL {
            // File paths can be sensitive; keep only the last component.
            return "url(file:\(value.lastPathComponent))"
        }
        return "url(\(scheme)://\(value.host() ?? "?"))"
    }

    /// Describes a file system path by its last component only.
    public static func path(_ value: String?) -> String {
        guard let value else { return "path(nil)" }
        return "path(\((value as NSString).lastPathComponent))"
    }

    /// Describes a pasteboard scope. Named pasteboards are reduced to a short hash so that
    /// log lines can still be correlated without leaking the name.
    public static func scope(_ value: PasteboardScope) -> String {
        switch value {
        case .general:
            return "scope(general)"
        case .named(let name):
            return "scope(named:\(shortHash(name)))"
        case .unique(let name):
            return "scope(unique:\(shortHash(name)))"
        }
    }

    /// Describes clipboard content by item and representation counts plus total size.
    public static func content(_ value: ClipboardContent) -> String {
        let reps = value.items.reduce(0) { $0 + $1.representations.count }
        return "content(items:\(value.items.count), reps:\(reps), bytes:\(value.totalBytes))"
    }

    /// Uniform type identifiers are not sensitive and are logged verbatim.
    public static func types(_ value: [String]) -> String {
        "types(\(value.joined(separator: ",")))"
    }

    /// Describes a JSON payload by length only.
    ///
    /// Bridge JSON carries the clipboard payload itself, base64 encoded, so logging it
    /// verbatim would copy passwords, tokens and documents into whatever collects logs.
    public static func json(_ value: String?) -> String {
        guard let value else { return "json(nil)" }
        return "json(len:\(value.count))"
    }

    /// Describes a scope JSON string without revealing a named pasteboard.
    ///
    /// A pasteboard name is chosen by the caller and can identify a workflow or a document, so
    /// only `general` is logged verbatim. Anything else becomes a short hash, which is still
    /// enough to correlate log lines.
    public static func scopeJson(_ value: String?) -> String {
        guard let value else { return "scope(nil)" }
        if value.contains("\"general\"") { return "scope(general)" }
        return "scope(\(shortHash(value)))"
    }

    /// Describes a creation request. A requested name is reduced to the same short hash a
    /// resolved scope uses, so the two can be correlated without either leaking the name.
    ///
    /// Interpolating the request itself printed `named("secret")` verbatim at five call sites
    /// (R-S2-H1). `Log` publishes at `privacy: .public`, so the name reached whatever collects
    /// the logs.
    public static func request(_ value: PasteboardCreationRequest) -> String {
        switch value {
        case .named(let name):
            return "request(named:\(shortHash(name)))"
        case .unique:
            return "request(unique)"
        }
    }

    private static func shortHash(_ value: String) -> String {
        var hasher = Hasher()
        hasher.combine(value)
        return String(format: "%08x", UInt32(truncatingIfNeeded: hasher.finalize()))
    }
}
