//
//  PasteButtonFactory.swift
//  MacLibrary
//

import AppKit
import Foundation
import SwiftUI
import UniformTypeIdentifiers

/// Builds a system paste button wired to a loader.
///
/// - Important: The macOS `PasteButton` does **not** validate or invalidate itself the way its
///   iOS counterpart does. It stays enabled whether or not the pasteboard holds an accepted
///   type, and the load simply reports that nothing matched (RK-16).
@MainActor
enum PasteButtonFactory {

    private static let TAG = "PasteButtonFactory"

    /// Adapts an `NSItemProvider` to the loader's source protocol.
    ///
    /// `NSItemProvider` is not `Sendable`, so the adapter is the boundary: the loader never
    /// sees the AppKit type, and this wrapper confines it to the main actor.
    struct ItemProviderSource: ClipboardPasteLoader.Source, @unchecked Sendable {
        let provider: NSItemProvider

        func conforms(to identifier: String) async -> Bool {
            provider.hasItemConformingToTypeIdentifier(identifier)
        }

        func loadData(for identifier: String) async throws -> Data {
            try await withCheckedThrowingContinuation { continuation in
                // Only the data representation is used. `loadFileRepresentation` hands back a
                // temporary URL whose lifetime ends when the callback returns, which would
                // force a copy under a deadline for no benefit.
                _ = provider.loadDataRepresentation(forTypeIdentifier: identifier) { data, error in
                    if let data {
                        continuation.resume(returning: data)
                    } else {
                        continuation.resume(
                            throwing: error ?? ClipboardError.pasteLoadFailed("no data"))
                    }
                }
            }
        }
    }

    /// Creates the button and the view that owns its lifetime.
    ///
    /// - Returns: The container view. Releasing it cancels any load in progress.
    /// - Throws: ``ClipboardError/invalidTypeIdentifier(_:)`` for an empty or malformed
    ///   accepted type, and ``ClipboardError/invalidConfiguration(_:)`` for a timeout outside
    ///   `0 < timeout <= 300`.
    static func makePasteButton(acceptedTypes: [String],
                                timeout: TimeInterval,
                                validator: any ClipboardTypeIdentifierValidating,
                                register: (ClipboardPasteLoader) -> ClipboardPasteHandle,
                                cancel: @escaping @MainActor (ClipboardPasteHandle) -> Void,
                                onPaste: @escaping @MainActor (ClipboardPasteResult) -> Void)
    throws -> NSView {
        Log.d(TAG, "[makePasteButton] acceptedTypes: \(ClipboardLog.types(acceptedTypes)), "
              + "timeout: \(timeout)")
        let loader = try ClipboardPasteLoader(acceptedTypes: acceptedTypes,
                                              timeout: timeout,
                                              validator: validator,
                                              onPaste: onPaste)
        let handle = register(loader)
        let contentTypes = acceptedTypes.compactMap { UTType($0) }
        let button = PasteButton(supportedContentTypes: contentTypes) { providers in
            loader.load(from: providers.map { ItemProviderSource(provider: $0) })
        }
        return ClipboardPasteContainerView(handle: handle,
                                           content: NSHostingView(rootView: button),
                                           onCancel: cancel)
    }
}
