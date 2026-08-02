//
//  ClipboardFailureDetail.swift
//  IosLibrary
//

import Foundation

/// Diagnostic detail for a normalized system failure.
///
/// `debugMessage` is diagnostic-only: it is never surfaced in a public error message,
/// Bridge JSON, or log output. Only `domain` and `code` may be exposed as optional
/// diagnostic details.
public struct ClipboardFailureDetail: Equatable, Sendable {
    public let domain: String
    public let code: Int
    let debugMessage: String

    public init(domain: String, code: Int, debugMessage: String) {
        self.domain = domain
        self.code = code
        self.debugMessage = debugMessage
    }

    /// Builds a detail from an arbitrary system `Error`, normalizing it into a
    /// stable `(domain, code)` pair. Never retains the original `Error`.
    public init(systemError: Error) {
        let nsError = systemError as NSError
        self.domain = nsError.domain
        self.code = nsError.code
        self.debugMessage = nsError.localizedDescription
    }
}
