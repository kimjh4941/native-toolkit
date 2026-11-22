//
//  ClipboardRedaction.swift
//  IosLibrary
//

import Foundation

/// Redacts sensitive clipboard values before they are logged, from Swift or Objective-C.
///
/// The library's clipboard code logs through these helpers. They are public, and visible to
/// Objective-C, so that code outside the library that logs clipboard values (an app, or a
/// wrapper of its own) can redact them the same way. Each helper returns a short placeholder
/// that keeps only a size (and, for a path, its extension), never the value itself.
///
/// Redacted: copied/pasted values, JSON strings, Base64 strings, file paths/names, URLs,
/// system error messages. Never redacted (safe to log as-is): kind, length, count,
/// `PasteboardScope` kind, `localOnly`, `errorCode`, and failure detail `domain`/`code`.
/// A UTI is a value the caller passes in: the library logs it with `privacy: .private`.
@objc public final class ClipboardRedaction: NSObject {
    /// A placeholder for a text value: `<text:N>`, where N is its length in UTF-8 bytes.
    @objc public static func text(_ value: String) -> String {
        ClipboardRedactionCore.text(value)
    }

    /// A placeholder for binary data of `byteCount` bytes: `<data:N>`.
    @objc public static func dataByteCount(_ byteCount: Int) -> String {
        ClipboardRedactionCore.data(byteCount: byteCount)
    }

    /// A placeholder for a JSON string: `<json:N>`, where N is its length in UTF-8 bytes.
    @objc public static func json(_ value: String) -> String {
        ClipboardRedactionCore.json(value)
    }

    /// A placeholder for a file path: `<path:ext=E,len=N>`, with the path extension E and the
    /// length N of the path in UTF-8 bytes; the directories and the file name are left out.
    @objc public static func path(_ value: String) -> String {
        ClipboardRedactionCore.path(value)
    }
}
