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
