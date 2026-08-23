//
//  ClipboardItemLoader.swift
//  IosLibrary
//

import Foundation

/// Loads a single item from the pasteboard's `NSItemProvider`s asynchronously.
///
/// `NSItemProvider` itself never appears in this Port; only Domain types do.
@MainActor
public protocol ClipboardItemLoader: AnyObject, Sendable {
    /// Loads the first matching item. `completion` is invoked exactly once on the main actor,
    /// across every path: success, provider error, unexpected type, no matching provider,
    /// cancellation, and timeout.
    @discardableResult
    func load(
        _ request: ClipboardLoadRequest,
        scope: PasteboardScope,
        completion: @escaping (Result<ClipboardLoadedItem, ClipboardError>) -> Void
    ) -> any ClipboardLoadToken

    /// Cancels every pending load. Each pending request receives `.cancelled` exactly once.
    func cancelAll()
}

/// A handle that can cancel a single in-flight `ClipboardItemLoader.load` request.
@MainActor
public protocol ClipboardLoadToken: AnyObject, Sendable {
    func cancel()
}
