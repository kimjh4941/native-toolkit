//
//  ClipboardHandles.swift
//  MacLibrary
//

import Foundation

/// Opaque identifier for a registered lazy data provider.
///
/// Handles are Domain value types so that Application ports never carry Presentation or
/// AppKit objects. The coordinator resolves a handle back to the platform object.
public struct PasteboardPromiseHandle: Sendable, Equatable, Hashable {
    public let id: UUID
    public init(id: UUID = UUID()) { self.id = id }
}

/// Opaque identifier for a registered file promise provider.
public struct FilePromiseHandle: Sendable, Equatable, Hashable {
    public let id: UUID
    public init(id: UUID = UUID()) { self.id = id }
}

/// Opaque identifier for a file promise receive session.
public struct FilePromiseReceiptHandle: Sendable, Equatable, Hashable {
    public let id: UUID
    public init(id: UUID = UUID()) { self.id = id }
}

/// Opaque identifier for a paste button's item loader.
///
/// The container view holds this and cancels the loader from `deinit`.
public struct ClipboardPasteHandle: Sendable, Equatable, Hashable {
    public let id: UUID
    public init(id: UUID = UUID()) { self.id = id }
}
