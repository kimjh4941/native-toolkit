//
//  LogRedaction.swift
//  IosLibrary
//

import Foundation

/// Log-safe forms of values that must not reach the log as they are.
///
/// The library logs through `os.Logger` with a privacy level per interpolation. A secret value
/// (a password, the text of a dialog input field, a notification reply, the content of a
/// notification or of a share, the clipboard text) is never interpolated, not even as
/// `.private`: only what these helpers return is, which says whether the value is there and how
/// long it is. Errors are logged by their case name, because the associated values of some
/// errors are URLs or file paths.
///
/// Everything these helpers return may be logged with `privacy: .public`.
enum LogRedaction {
    /// `<redacted, length=N>` (N is the UTF-8 byte count), or `nil` when there is no value.
    static func redact(_ value: String?) -> String {
        guard let value else { return "nil" }
        return "<redacted, length=\(value.utf8.count)>"
    }

    /// `length=N` (N is the UTF-8 byte count), or `nil` when there is no value.
    static func length(_ value: String?) -> String {
        guard let value else { return "nil" }
        return "length=\(value.utf8.count)"
    }

    /// The name of an enum value's case, without its associated values (`imageLoadFailed`
    /// for `.imageLoadFailed(path: "/private/...")`).
    ///
    /// When the value is not an enum, or is a case without associated values whose type has
    /// its own description (which could show values), only the type name is returned.
    static func caseName(_ value: Any) -> String {
        let mirror = Mirror(reflecting: value)
        guard mirror.displayStyle == .enum else { return String(describing: type(of: value)) }
        if let label = mirror.children.first?.label { return label }
        if value is CustomStringConvertible || value is CustomDebugStringConvertible {
            return String(describing: type(of: value))
        }
        return String(describing: value)
    }

    /// `<Type>.<case>` for an error that is an enum (the library's errors), otherwise the
    /// `NSError` domain and code. Never the localized description, which can hold input values.
    ///
    /// When the case's only associated value is itself an error (for example
    /// `addRequestFailed(Error)`) or a ``FailureDetail`` (for example
    /// `ShareError.activityFailed(FailureDetail)`), its domain and code are added:
    /// `<Type>.<case>(domain=…, code=…)`. Other associated values (URLs, paths) are never shown.
    static func describe(_ error: any Error) -> String {
        let mirror = Mirror(reflecting: error)
        guard mirror.displayStyle == .enum else {
            return domainAndCode(of: error)
        }
        let name = "\(String(describing: type(of: error))).\(caseName(error))"
        if mirror.children.count == 1, let inner = mirror.children.first?.value as? any Error {
            return "\(name)(\(domainAndCode(of: inner)))"
        }
        if mirror.children.count == 1, let detail = mirror.children.first?.value as? FailureDetail {
            return "\(name)(domain=\(detail.domain), code=\(detail.code))"
        }
        return name
    }

    private static func domainAndCode(of error: any Error) -> String {
        let nsError = error as NSError
        return "domain=\(nsError.domain), code=\(nsError.code)"
    }
}
