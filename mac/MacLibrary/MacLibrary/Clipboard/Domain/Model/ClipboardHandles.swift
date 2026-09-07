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
    /// Opaque identity. Callers should treat it as a token, not a value.
    public let id: UUID
    /// Creates a handle. A fresh identity is generated unless one is supplied.
    public init(id: UUID = UUID()) { self.id = id }
}

/// Opaque identifier for a paste button's item loader.
///
/// The container view holds this and cancels the loader from `deinit`.
public struct ClipboardPasteHandle: Sendable, Equatable, Hashable {
    /// Opaque identity. Callers should treat it as a token, not a value.
    public let id: UUID
    /// Creates a handle. A fresh identity is generated unless one is supplied.
    public init(id: UUID = UUID()) { self.id = id }
}
