//
//  ClipboardContent.swift
//  MacLibrary
//

import Foundation

/// One pasteboard item, expressed as raw bytes per uniform type identifier.
///
/// A single item can carry several representations of the same content, for example plain
/// text and RTF. Keys are UTI strings; values are the bytes for that representation.
public struct ClipboardItemData: Sendable, Equatable {
    /// Uniform type identifier to raw bytes.
    public let representations: [String: Data]

    public init(representations: [String: Data]) {
        self.representations = representations
    }

    /// Total size of every representation in this item.
    public var totalBytes: Int {
        representations.values.reduce(0) { $0 + $1.count }
    }
}

/// An ordered list of pasteboard items.
public struct ClipboardContent: Sendable, Equatable {
    public let items: [ClipboardItemData]

    public init(items: [ClipboardItemData]) {
        self.items = items
    }

    /// Total size of every representation across every item.
    public var totalBytes: Int {
        items.reduce(0) { $0 + $1.totalBytes }
    }
}

/// Options applied when taking ownership of a pasteboard for a copy.
public struct ClipboardCopyOptions: Sendable, Equatable {
    /// When `true` the contents are not offered to other devices via Universal Clipboard.
    ///
    /// - Note: The suppression intent is expressed with `NSPasteboard.ContentsOptions`.
    ///   Its practical effect has not been verified on real hardware yet.
    public let localOnly: Bool

    public init(localOnly: Bool) {
        self.localOnly = localOnly
    }

    /// `localOnly: true`, the safer default.
    public static let `default` = ClipboardCopyOptions(localOnly: true)
}

/// Everything read back from a pasteboard.
public struct ClipboardReadResult: Sendable, Equatable {
    public let items: [ClipboardItemData]
    public let changeCount: Int

    public init(items: [ClipboardItemData], changeCount: Int) {
        self.items = items
        self.changeCount = changeCount
    }
}

/// Type information about a pasteboard without reading any payload.
///
/// - Important: Avoiding a payload read does **not** guarantee the system will refrain from
///   notifying the user. Treat this as an optimisation, not a privacy contract.
public struct ClipboardSnapshot: Sendable, Equatable {
    public let changeCount: Int
    /// Uniform type identifiers of every item, in pasteboard order.
    public let itemTypes: [[String]]
    /// Indexes of the items that matched the requested filter, or every index when unfiltered.
    public let matchingItemIndexes: [Int]

    public init(changeCount: Int, itemTypes: [[String]], matchingItemIndexes: [Int]) {
        self.changeCount = changeCount
        self.itemTypes = itemTypes
        self.matchingItemIndexes = matchingItemIndexes
    }
}

/// Emitted when the observed pasteboard's change count moves.
///
/// - Note: macOS has no changed / removed distinction, so the event carries neither.
public struct ClipboardChangeEvent: Sendable, Equatable {
    public let scope: PasteboardScope
    public let changeCount: Int

    public init(scope: PasteboardScope, changeCount: Int) {
        self.scope = scope
        self.changeCount = changeCount
    }
}
