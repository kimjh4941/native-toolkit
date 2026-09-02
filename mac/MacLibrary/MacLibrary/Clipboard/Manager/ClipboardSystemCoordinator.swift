//
//  ClipboardSystemCoordinator.swift
//  MacLibrary
//

import AppKit
import Foundation

/// The single owner of every system object the clipboard feature registers.
///
/// `NSPasteboardItemDataProvider` is held weakly by the pasteboard item, and the protocol
/// never reports that a provider is finished with, so something has to hold the strong
/// reference and decide when to let go. common.md requires that owner to be exactly one
/// manager layer class, and this is it: lazy data providers and paste loaders both live here.
/// The repository resolves handles through a read-only view and holds nothing (H-5).
@MainActor
final class ClipboardSystemCoordinator {

    private let TAG = "ClipboardSystemCoordinator"

    private var lazyProviders: [PasteboardPromiseHandle: LazyProviderRegistration] = [:]
    private var pasteLoaders: [ClipboardPasteHandle: ClipboardPasteLoader] = [:]

    init() {
        Log.d("ClipboardSystemCoordinator", "[init]")
    }

    // MARK: - Paste loaders

    /// Takes ownership of a paste loader for as long as its view exists.
    func registerPasteLoader(_ loader: ClipboardPasteLoader) -> ClipboardPasteHandle {
        Log.d(TAG, "[registerPasteLoader]")
        let handle = ClipboardPasteHandle()
        pasteLoaders[handle] = loader
        return handle
    }

    /// Cancels a paste in progress and drops the loader. Idempotent.
    ///
    /// Called from the container view's `deinit`, so it must tolerate being called for a
    /// handle that is already gone (R2-M10).
    func cancelPaste(_ handle: ClipboardPasteHandle) {
        Log.d(TAG, "[cancelPaste] handle: \(handle.id)")
        guard let loader = pasteLoaders[handle] else { return }
        loader.cancel()
        pasteLoaders[handle] = nil
    }

    var registeredPasteLoaderCount: Int { pasteLoaders.count }
}

// MARK: - Registrations

/// A registered lazy data provider and the types it can supply.
@MainActor
final class LazyProviderRegistration {
    let types: [String]
    let provider: LazyDataProvider

    init(types: [String], provider: LazyDataProvider) {
        self.types = types
        self.provider = provider
    }
}

// MARK: - ClipboardPromiseRegistry

extension ClipboardSystemCoordinator: ClipboardPromiseRegistry {

    // MARK: Lazy data providers

    func registerLazyProvider(types: [String],
                              provide: @escaping @Sendable (String) -> Data?) -> PasteboardPromiseHandle {
        Log.d(TAG, "[registerLazyProvider] types: \(ClipboardLog.types(types))")
        let handle = PasteboardPromiseHandle()
        let provider = LazyDataProvider(provide: provide, onFinished: { [weak self] in
            // The callback is nonisolated, so releasing hops back to the main actor.
            Task { @MainActor [weak self] in self?.releaseLazyProvider(handle) }
        })
        lazyProviders[handle] = LazyProviderRegistration(types: types, provider: provider)
        return handle
    }

    func releaseLazyProvider(_ handle: PasteboardPromiseHandle) {
        Log.d(TAG, "[releaseLazyProvider] handle: \(handle.id)")
        lazyProviders[handle] = nil
    }
}

// MARK: - PromiseObjectLookup

extension ClipboardSystemCoordinator: PromiseObjectLookup {

    func lazyProvider(for handle: PasteboardPromiseHandle) -> (any NSPasteboardItemDataProvider)? {
        Log.d(TAG, "[lazyProvider] handle: \(handle.id)")
        return lazyProviders[handle]?.provider
    }
}

// MARK: - Test and diagnostics access

extension ClipboardSystemCoordinator {
    var registeredLazyProviderCount: Int { lazyProviders.count }
    var lazyProviderHandlesForTests: [PasteboardPromiseHandle] { Array(lazyProviders.keys) }
    func lazyProviderTypes(for handle: PasteboardPromiseHandle) -> [String]? {
        lazyProviders[handle]?.types
    }
}
