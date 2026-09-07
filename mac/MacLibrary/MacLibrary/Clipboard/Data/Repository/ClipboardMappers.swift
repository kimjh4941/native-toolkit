//
//  ClipboardMappers.swift
//  MacLibrary
//

import AppKit
import Foundation

/// Converts between domain clipboard values and `NSPasteboardItem`.
///
/// Keeping both directions in one place is what stops `NSPasteboard` types from leaking past
/// the data layer (H-5).
@MainActor
enum ClipboardMappers {

    private static let TAG = "ClipboardMappers"

    /// Builds pasteboard items for a write.
    ///
    /// A fresh `NSPasteboardItem` is created on every call. Items are owned by the pasteboard
    /// once written and cannot be reused for a later write (RK-14).
    ///
    /// - Throws: ``ClipboardError/invalidTypeIdentifier(_:)`` when `setData(_:forType:)`
    ///   rejects a uniform type identifier. `NSPasteboardItem` reports a malformed identifier
    ///   by returning `false` rather than by raising, so the rejection is surfaced here.
    static func makeItems(from content: ClipboardContent) throws -> [NSPasteboardItem] {
        Log.d(TAG, "[makeItems] content: \(ClipboardLog.content(content))")
        return try content.items.map { item in
            let pasteboardItem = NSPasteboardItem()
            // Sorted so that a write produces the same representation order every time, which
            // keeps tests and logs deterministic. Pasteboard readers address types by name.
            for identifier in item.representations.keys.sorted() {
                guard let data = item.representations[identifier] else { continue }
                let accepted = pasteboardItem.setData(data, forType: NSPasteboard.PasteboardType(identifier))
                guard accepted else {
                    throw ClipboardError.invalidTypeIdentifier(identifier)
                }
            }
            return pasteboardItem
        }
    }

    /// Reads every representation of every item.
    ///
    /// Only the `pasteboardItems` path is used. The convenience readers collapse multiple
    /// items into one newline joined string, which loses the item boundaries this API exposes
    /// (RK-15).
    ///
    /// A type that reports no data is omitted rather than treated as an error: the pasteboard
    /// advertises promised types whose provider may decline to deliver.
    static func makeItemData(from items: [NSPasteboardItem]) -> [ClipboardItemData] {
        Log.d(TAG, "[makeItemData] items: \(items.count)")
        return items.map { item in
            var representations: [String: Data] = [:]
            for type in item.types {
                guard let data = item.data(forType: type) else { continue }
                representations[type.rawValue] = data
            }
            return ClipboardItemData(representations: representations)
        }
    }

    /// Uniform type identifiers advertised by each item, in pasteboard order.
    ///
    /// No payload is read, which is what lets the snapshot operation describe a pasteboard
    /// without pulling its contents.
    static func makeItemTypes(from items: [NSPasteboardItem]) -> [[String]] {
        Log.d(TAG, "[makeItemTypes] items: \(items.count)")
        return items.map { $0.types.map(\.rawValue) }
    }
}
