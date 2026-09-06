//
//  ClipboardPasteResult.swift
//  MacLibrary
//

import Foundation

/// One successfully loaded pasted item.
public struct ClipboardPasteItem: Sendable, Equatable {
    /// Index of the source provider, so results keep the caller's input order.
    public let providerIndex: Int
    /// The representation that was loaded.
    public let data: ClipboardItemData
    /// Creates a result, normalising both arrays into input order.
    public init(providerIndex: Int, data: ClipboardItemData) {
        self.providerIndex = providerIndex
        self.data = data
    }
}

/// One provider that failed to load.
public struct ClipboardPasteFailure: Sendable, Equatable {
    /// Index of the source provider, preserving the caller's input order.
    public let providerIndex: Int
    /// Why this provider could not be loaded.
    public let error: ClipboardError
    /// Creates a result, normalising both arrays into input order.
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
    /// Successfully loaded items, in input order.
    public let items: [ClipboardPasteItem]
    /// Providers that failed or timed out, in input order.
    public let failures: [ClipboardPasteFailure]

    /// Creates a result, normalising both arrays into input order.
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
