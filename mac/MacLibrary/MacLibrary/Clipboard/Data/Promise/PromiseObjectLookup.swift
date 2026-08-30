//
//  PromiseObjectLookup.swift
//  MacLibrary
//

import AppKit
import Foundation

/// Read-only view from a handle to the AppKit object registered for it.
///
/// The repository has to put a file promise provider on a pasteboard, but it must not own one:
/// every system object belongs to the coordinator (H-5). This protocol is the narrow seam
/// between them. Nothing here retains anything; a `nil` answer simply means the registration
/// is gone.
@MainActor
protocol PromiseObjectLookup: AnyObject {
    /// Lazy data provider for a handle, or `nil` when it is not registered.
    func lazyProvider(for handle: PasteboardPromiseHandle) -> (any NSPasteboardItemDataProvider)?
    /// File promise provider for a handle, or `nil` when it is not registered.
    func filePromiseProvider(for handle: FilePromiseHandle) -> NSFilePromiseProvider?
}
