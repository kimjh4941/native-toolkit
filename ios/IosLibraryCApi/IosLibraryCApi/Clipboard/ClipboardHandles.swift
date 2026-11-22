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

/// What an `ntk_clipboard_loaded_item*` points to. Only what `kind` names is there.
final class ClipboardLoadedItemHandle {
    let kind: ntk_clipboard_item_kind
    let text: HandleBuffer?
    let url: HandleBuffer?
    let imageData: HandleBuffer?
    let imageType: HandleBuffer?
    let filePath: HandleBuffer?

    init(_ item: ClipboardLoadedItem) {
        switch item {
        case .text(let value):
            (kind, text, url, imageData, imageType, filePath) = (ntk_clipboard_item_kind(NTK_CLIPBOARD_ITEM_TEXT), ClipboardHandles.buffer(value), nil, nil, nil, nil)
        case .url(let value):
            (kind, text, url, imageData, imageType, filePath) = (ntk_clipboard_item_kind(NTK_CLIPBOARD_ITEM_URL), nil, ClipboardHandles.buffer(value), nil, nil, nil)
        case .imageData(let data, let utType):
            (kind, text, url, imageData, imageType, filePath) = (ntk_clipboard_item_kind(NTK_CLIPBOARD_ITEM_IMAGE), nil, nil, HandleBuffer(data), ClipboardHandles.buffer(utType), nil)
        case .file(let fileURL):
            (kind, text, url, imageData, imageType, filePath) = (ntk_clipboard_item_kind(NTK_CLIPBOARD_ITEM_FILE), nil, nil, nil, nil, ClipboardHandles.buffer(fileURL.path))
        @unknown default:
            CApiLog.clipboard.error("[ClipboardLoadedItemHandle.init] an item this version does not know")
            (kind, text, url, imageData, imageType, filePath) = (-1, nil, nil, nil, nil, nil)
        }
    }
}

/// What an `ntk_clipboard_change*` points to.
final class ClipboardChangeHandle {
    let kind: ntk_clipboard_change_event_kind
    let scopeKind: ntk_clipboard_scope_kind
    let scopeName: HandleBuffer?
    let typesAdded: [HandleBuffer]
    let typesRemoved: [HandleBuffer]

    init(_ change: ClipboardChange) {
        kind = change.kind
        scopeKind = change.scopeKind
        scopeName = change.scopeName.map(ClipboardHandles.buffer)
        typesAdded = change.typesAdded.map(ClipboardHandles.buffer)
        typesRemoved = change.typesRemoved.map(ClipboardHandles.buffer)
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

    // MARK: - ntk_clipboard_loaded_item

    static func makeLoadedItem(_ item: ClipboardLoadedItem) -> OpaquePointer {
        CApiLog.clipboard.debug("[makeLoadedItem] item: provided")
        return Handle.retained(ClipboardLoadedItemHandle(item))
    }

    private static func loaded(_ handle: OpaquePointer?) -> ClipboardLoadedItemHandle? {
        Handle.borrow(handle, as: ClipboardLoadedItemHandle.self)
    }

    /// -1 for NULL: 0 is TEXT (P2-29).
    static func loadedItemKind(_ handle: OpaquePointer?) -> ntk_clipboard_item_kind {
        loaded(handle)?.kind ?? -1
    }

    static func loadedItemText(_ handle: OpaquePointer?, _ outSize: UnsafeMutablePointer<Int>?) -> UnsafePointer<CChar>? {
        Handle.text(of: loaded(handle)?.text, outSize)
    }

    static func loadedItemUrl(_ handle: OpaquePointer?, _ outSize: UnsafeMutablePointer<Int>?) -> UnsafePointer<CChar>? {
        Handle.text(of: loaded(handle)?.url, outSize)
    }

    static func loadedItemImageData(_ handle: OpaquePointer?, _ outSize: UnsafeMutablePointer<Int>?) -> UnsafePointer<UInt8>? {
        let buffer = loaded(handle)?.imageData
        outSize?.pointee = buffer?.count ?? 0
        return buffer.map { UnsafePointer($0.storage) }
    }

    static func loadedItemImageType(_ handle: OpaquePointer?, _ outSize: UnsafeMutablePointer<Int>?) -> UnsafePointer<CChar>? {
        Handle.text(of: loaded(handle)?.imageType, outSize)
    }

    static func loadedItemFilePath(_ handle: OpaquePointer?, _ outSize: UnsafeMutablePointer<Int>?) -> UnsafePointer<CChar>? {
        Handle.text(of: loaded(handle)?.filePath, outSize)
    }

    // MARK: - ntk_clipboard_change

    static func makeChange(_ change: ClipboardChange) -> OpaquePointer {
        CApiLog.clipboard.debug("[makeChange] change: provided")
        return Handle.retained(ClipboardChangeHandle(change))
    }

    private static func change(_ handle: OpaquePointer?) -> ClipboardChangeHandle? {
        Handle.borrow(handle, as: ClipboardChangeHandle.self)
    }

    /// -1 for NULL (P2-29).
    static func changeKind(_ handle: OpaquePointer?) -> ntk_clipboard_change_event_kind {
        change(handle)?.kind ?? -1
    }

    /// -1 for NULL (P2-29).
    static func changeScopeKind(_ handle: OpaquePointer?) -> ntk_clipboard_scope_kind {
        change(handle)?.scopeKind ?? -1
    }

    static func changeScopeName(_ handle: OpaquePointer?, _ outSize: UnsafeMutablePointer<Int>?) -> UnsafePointer<CChar>? {
        Handle.text(of: change(handle)?.scopeName, outSize)
    }

    static func changeTypesAddedCount(_ handle: OpaquePointer?) -> Int {
        change(handle)?.typesAdded.count ?? 0
    }

    static func changeTypesAddedAt(_ handle: OpaquePointer?, _ index: Int, _ outSize: UnsafeMutablePointer<Int>?) -> UnsafePointer<CChar>? {
        Handle.text(of: element(change(handle)?.typesAdded, index), outSize)
    }

    static func changeTypesRemovedCount(_ handle: OpaquePointer?) -> Int {
        change(handle)?.typesRemoved.count ?? 0
    }

    static func changeTypesRemovedAt(_ handle: OpaquePointer?, _ index: Int, _ outSize: UnsafeMutablePointer<Int>?) -> UnsafePointer<CChar>? {
        Handle.text(of: element(change(handle)?.typesRemoved, index), outSize)
    }

    private static func element<Element>(_ array: [Element]?, _ index: Int) -> Element? {
        guard let array, array.indices.contains(index) else { return nil }
        return array[index]
    }
}
