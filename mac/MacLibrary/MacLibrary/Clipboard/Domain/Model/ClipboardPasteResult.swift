//
//  ClipboardPasteResult.swift
//  MacLibrary
//

import Foundation

/// One successfully loaded pasted item.
public struct ClipboardPasteItem: Sendable, Equatable {
    /// Index of the source provider, so results keep the caller's input order.
    public let providerIndex: Int
    public let data: ClipboardItemData
    public init(providerIndex: Int, data: ClipboardItemData) {
        self.providerIndex = providerIndex
        self.data = data
    }
}

/// One provider that failed to load.
public struct ClipboardPasteFailure: Sendable, Equatable {
    public let providerIndex: Int
    public let error: ClipboardError
    public init(providerIndex: Int, error: ClipboardError) {
        self.providerIndex = providerIndex
        self.error = error
    }
}

/// Outcome of loading the items behind a paste button.
///
/// Providers load concurrently but both arrays are normalised to `providerIndex` order, so
/// the caller sees input order rather than completion order.
public struct ClipboardPasteResult: Sendable, Equatable {
    public let items: [ClipboardPasteItem]
    public let failures: [ClipboardPasteFailure]

    public init(items: [ClipboardPasteItem], failures: [ClipboardPasteFailure]) {
        self.items = items.sorted { $0.providerIndex < $1.providerIndex }
        self.failures = failures.sorted { $0.providerIndex < $1.providerIndex }
    }

    /// Some providers loaded and some failed.
    public var isPartial: Bool { !items.isEmpty && !failures.isEmpty }
    /// Every provider failed.
    public var isCompleteFailure: Bool { items.isEmpty && !failures.isEmpty }
    /// There was nothing to paste.
    public var isEmpty: Bool { items.isEmpty && failures.isEmpty }
}
