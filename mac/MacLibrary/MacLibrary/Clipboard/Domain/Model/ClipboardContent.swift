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

    /// Creates a value from its parts.
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
    /// Pasteboard items, in order.
    public let items: [ClipboardItemData]

    /// Creates a value from its parts.
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
    ///   Measured on 2026-09-03: with `false` the contents reached a paired iPhone in about a
    ///   second; with `true` they did not arrive and the other device kept its own clipboard.
    ///   That is one pairing -- macOS 26.3 and iOS 18.7.2 over Handoff -- so read it as
    ///   evidence of suppression there, not as a guarantee for every device and OS.
    public let localOnly: Bool

    /// Creates a value from its parts.
    public init(localOnly: Bool) {
        self.localOnly = localOnly
    }

    /// `localOnly: true`, the safer default.
    public static let `default` = ClipboardCopyOptions(localOnly: true)
}

/// Everything read back from a pasteboard.
public struct ClipboardReadResult: Sendable, Equatable {
    /// Pasteboard items, in order.
    public let items: [ClipboardItemData]
    /// Change count observed when the value was produced.
    public let changeCount: Int

    /// Creates a value from its parts.
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
    /// Change count observed when the value was produced.
    public let changeCount: Int
    /// Uniform type identifiers of every item, in pasteboard order.
    public let itemTypes: [[String]]
    /// Indexes of the items that matched the requested filter, or every index when unfiltered.
    public let matchingItemIndexes: [Int]

    /// Creates a value from its parts.
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
    /// Pasteboard the event came from.
    public let scope: PasteboardScope
    /// Change count observed when the value was produced.
    public let changeCount: Int

    /// Creates a value from its parts.
    public init(scope: PasteboardScope, changeCount: Int) {
        self.scope = scope
        self.changeCount = changeCount
    }
}
