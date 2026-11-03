//
//  ClipboardHandles.swift
//  IosLibraryCApi
//

import IosLibrary

/// What an `ntk_clipboard_read_result*` points to.
final class ClipboardReadResultHandle {
    struct Item {
        let types: [HandleBuffer]
        let text: HandleBuffer?
        let url: HandleBuffer?
        let imageType: HandleBuffer?
    }

    let items: [Item]

    init(_ result: ClipboardReadResult) {
        items = result.items.map {
            Item(types: $0.typeIdentifiers.map(ClipboardHandles.buffer), text: $0.text.map(ClipboardHandles.buffer),
                 url: $0.urlString.map(ClipboardHandles.buffer), imageType: $0.imageDataUTType.map(ClipboardHandles.buffer))
        }
    }
}

/// What an `ntk_clipboard_snapshot*` points to.
final class ClipboardSnapshotHandle {
    let hasStrings: Bool
    let hasURLs: Bool
    let hasImages: Bool
    let hasColors: Bool
    let numberOfItems: Int
    let types: [HandleBuffer]
    let itemTypes: [[HandleBuffer]]
    let matching: [Int]?

    init(_ snapshot: ClipboardSnapshot) {
        hasStrings = snapshot.hasStrings
        hasURLs = snapshot.hasURLs
        hasImages = snapshot.hasImages
        hasColors = snapshot.hasColors
        numberOfItems = snapshot.numberOfItems
        types = snapshot.typeIdentifiers.map(ClipboardHandles.buffer)
        itemTypes = snapshot.allTypeIdentifiers.map { $0.map(ClipboardHandles.buffer) }
        matching = snapshot.matchingItemIndexes
    }
}

/// The readers of the result handles. A `size_t` arrives as `Int`: an index above `Int.max` is negative here
/// and out of range like any other. NULL and a handle of another type read as nothing. Reads and frees are
/// not logged (part 1, 5.15), and the values themselves never are.
enum ClipboardHandles {
    fileprivate static func buffer(_ value: String) -> HandleBuffer {
        HandleBuffer(CApiString.outputUTF8(value))
    }

    // MARK: - ntk_clipboard_read_result

    static func makeReadResult(_ result: ClipboardReadResult) -> OpaquePointer {
        CApiLog.clipboard.debug("[makeReadResult] items: \(result.items.count, privacy: .public)")
        return Handle.retained(ClipboardReadResultHandle(result))
    }

    private static func item(_ handle: OpaquePointer?, _ index: Int) -> ClipboardReadResultHandle.Item? {
        guard let items = Handle.borrow(handle, as: ClipboardReadResultHandle.self)?.items, items.indices.contains(index) else {
            return nil
        }
        return items[index]
    }

    static func readResultItemCount(_ handle: OpaquePointer?) -> Int {
        Handle.borrow(handle, as: ClipboardReadResultHandle.self)?.items.count ?? 0
    }

    static func readResultItemTypeCount(_ handle: OpaquePointer?, _ item: Int) -> Int {
        self.item(handle, item)?.types.count ?? 0
    }

    static func readResultItemTypeAt(_ handle: OpaquePointer?, _ item: Int, _ index: Int,
                                     _ outSize: UnsafeMutablePointer<Int>?) -> UnsafePointer<CChar>? {
        Handle.text(of: element(self.item(handle, item)?.types, index), outSize)
    }

    static func readResultItemTextAt(_ handle: OpaquePointer?, _ item: Int, _ outSize: UnsafeMutablePointer<Int>?) -> UnsafePointer<CChar>? {
        Handle.text(of: self.item(handle, item)?.text, outSize)
    }

    static func readResultItemUrlAt(_ handle: OpaquePointer?, _ item: Int, _ outSize: UnsafeMutablePointer<Int>?) -> UnsafePointer<CChar>? {
        Handle.text(of: self.item(handle, item)?.url, outSize)
    }

    static func readResultItemImageTypeAt(_ handle: OpaquePointer?, _ item: Int, _ outSize: UnsafeMutablePointer<Int>?) -> UnsafePointer<CChar>? {
        Handle.text(of: self.item(handle, item)?.imageType, outSize)
    }

    // MARK: - ntk_clipboard_snapshot

    static func makeSnapshot(_ snapshot: ClipboardSnapshot) -> OpaquePointer {
        CApiLog.clipboard.debug("[makeSnapshot] items: \(snapshot.numberOfItems, privacy: .public)")
        return Handle.retained(ClipboardSnapshotHandle(snapshot))
    }

    private static func snapshot(_ handle: OpaquePointer?) -> ClipboardSnapshotHandle? {
        Handle.borrow(handle, as: ClipboardSnapshotHandle.self)
    }

    static func snapshotHasStrings(_ handle: OpaquePointer?) -> Int32 {
        snapshot(handle)?.hasStrings == true ? 1 : 0
    }

    static func snapshotHasUrls(_ handle: OpaquePointer?) -> Int32 {
        snapshot(handle)?.hasURLs == true ? 1 : 0
    }

    static func snapshotHasImages(_ handle: OpaquePointer?) -> Int32 {
        snapshot(handle)?.hasImages == true ? 1 : 0
    }

    static func snapshotHasColors(_ handle: OpaquePointer?) -> Int32 {
        snapshot(handle)?.hasColors == true ? 1 : 0
    }

    static func snapshotNumberOfItems(_ handle: OpaquePointer?) -> Int {
        snapshot(handle)?.numberOfItems ?? 0
    }

    static func snapshotTypeCount(_ handle: OpaquePointer?) -> Int {
        snapshot(handle)?.types.count ?? 0
    }

    static func snapshotTypeAt(_ handle: OpaquePointer?, _ index: Int, _ outSize: UnsafeMutablePointer<Int>?) -> UnsafePointer<CChar>? {
        Handle.text(of: element(snapshot(handle)?.types, index), outSize)
    }

    static func snapshotItemTypeCount(_ handle: OpaquePointer?, _ item: Int) -> Int {
        element(snapshot(handle)?.itemTypes, item)?.count ?? 0
    }

    static func snapshotItemTypeAt(_ handle: OpaquePointer?, _ item: Int, _ index: Int,
                                   _ outSize: UnsafeMutablePointer<Int>?) -> UnsafePointer<CChar>? {
        Handle.text(of: element(element(snapshot(handle)?.itemTypes, item), index), outSize)
    }

    static func snapshotHasMatching(_ handle: OpaquePointer?) -> Int32 {
        snapshot(handle)?.matching == nil ? 0 : 1
    }

    static func snapshotMatchingCount(_ handle: OpaquePointer?) -> Int {
        snapshot(handle)?.matching?.count ?? 0
    }

    /// -1 for NULL and out of range: 0 is the first item (P2-29).
    static func snapshotMatchingAt(_ handle: OpaquePointer?, _ index: Int) -> Int64 {
        element(snapshot(handle)?.matching, index).map(Int64.init) ?? -1
    }

    private static func element<Element>(_ array: [Element]?, _ index: Int) -> Element? {
        guard let array, array.indices.contains(index) else { return nil }
        return array[index]
    }
}
