//
//  ClipboardPromiseRegistry.swift
//  MacLibrary
//

import Foundation

/// Owns every system delegate the clipboard feature registers.
///
/// `NSPasteboardItemDataProvider` is held weakly by the pasteboard item, and the protocol has
/// no completion notification, so something has to hold the strong reference and decide when
/// to let go. One coordinator in the manager layer does that for lazy data providers and
/// paste loaders. This port is how the application layer asks for those registrations without
/// seeing any AppKit type.
@MainActor
public protocol ClipboardPromiseRegistry {

    // MARK: Lazy data providers

    /// Registers a provider that supplies bytes on demand.
    func registerLazyProvider(types: [String],
                              provide: @escaping @Sendable (String) -> Data?) -> PasteboardPromiseHandle

    /// Releases a lazy provider. Idempotent.
    func releaseLazyProvider(_ handle: PasteboardPromiseHandle)
}
