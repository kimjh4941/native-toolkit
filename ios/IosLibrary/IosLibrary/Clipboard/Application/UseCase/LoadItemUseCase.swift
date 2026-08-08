//
//  LoadItemUseCase.swift
//  IosLibrary
//

import Foundation

/// Loads a single item from the pasteboard's `NSItemProvider`s asynchronously (P-11).
@MainActor
public struct LoadItemUseCase {
    private let TAG = "LoadItemUseCase"
    private let loader: ClipboardItemLoader

    public init(loader: ClipboardItemLoader) {
        self.loader = loader
    }

    @discardableResult
    public func execute(
        _ request: ClipboardLoadRequest,
        scope: PasteboardScope,
        completion: @escaping (Result<ClipboardLoadedItem, ClipboardError>) -> Void
    ) -> any ClipboardLoadToken {
        Log.d(TAG, "[execute] scope: \(scope.redactedDescription)")
        return loader.load(request, scope: scope, completion: completion)
    }
}
