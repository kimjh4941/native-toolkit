//
//  PromiseObjectLookup.swift
//  MacLibrary
//

import AppKit

/// Read-only view of the system objects the coordinator owns.
///
/// The repository has to hand AppKit the very provider instance the coordinator is holding,
/// but it must not own it: one manager layer class keeps every strong reference (H-5).
@MainActor
protocol PromiseObjectLookup: AnyObject {
    /// The registered lazy data provider for a handle, or `nil` once it has been released.
    func lazyProvider(for handle: PasteboardPromiseHandle) -> (any NSPasteboardItemDataProvider)?
}
