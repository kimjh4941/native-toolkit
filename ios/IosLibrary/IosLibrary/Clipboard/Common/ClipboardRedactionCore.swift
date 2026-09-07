//
//  ClipboardRedactionCore.swift
//  IosLibrary
//

import Foundation

/// Redaction implementation. Never emits the original value; only kind/length/metadata.
enum ClipboardRedactionCore {
    static func text(_ value: String) -> String {
        "<text:\(value.utf8.count)>"
    }

    static func data(byteCount: Int) -> String {
        "<data:\(byteCount)>"
    }

    static func json(_ value: String) -> String {
        "<json:\(value.utf8.count)>"
    }

    static func path(_ value: String) -> String {
        let ext = (value as NSString).pathExtension
        return "<path:ext=\(ext),len=\(value.utf8.count)>"
    }
}
