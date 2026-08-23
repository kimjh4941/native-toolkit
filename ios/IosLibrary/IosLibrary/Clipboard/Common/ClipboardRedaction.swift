//
//  ClipboardRedaction.swift
//  IosLibrary
//

import Foundation

/// Objective-C-visible facade for redacting sensitive clipboard values before logging.
///
/// Used both from Swift (`ClipboardLog`) and from the Unity Bridge's Objective-C `.m` files
/// (via `#import <IosLibrary/IosLibrary-Swift.h>`), since a plain `internal` Swift type cannot be
/// called from another module or from Objective-C.
///
/// Redacted: copied/pasted values, request JSON bodies, Base64 strings, file paths/names, URLs,
/// system error messages. Never redacted (safe to log as-is): kind, length, count, UTI,
/// `PasteboardScope` kind, `localOnly`, `errorCode`, and failure detail `domain`/`code`.
@objc public final class ClipboardRedaction: NSObject {
    @objc public static func text(_ value: String) -> String {
        ClipboardRedactionCore.text(value)
    }

    @objc public static func dataByteCount(_ byteCount: Int) -> String {
        ClipboardRedactionCore.data(byteCount: byteCount)
    }

    @objc public static func json(_ value: String) -> String {
        ClipboardRedactionCore.json(value)
    }

    @objc public static func path(_ value: String) -> String {
        ClipboardRedactionCore.path(value)
    }
}
