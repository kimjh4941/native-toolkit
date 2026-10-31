//
//  LoadItemUseCase.swift
//  IosLibrary
//

import Foundation
import os

private let logger = Logger(subsystem: "com.jonghyunkim.nativetoolkit.IosLibrary", category: "LoadItemUseCase")

/// Loads a single item from the pasteboard's `NSItemProvider`s asynchronously (P-11).
@MainActor
public struct LoadItemUseCase {
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
        logger.log(level: .libraryDebug, "[execute] scope: \(scope.redactedDescription, privacy: .public)")
        return loader.load(request, scope: scope, completion: completion)
    }
}
