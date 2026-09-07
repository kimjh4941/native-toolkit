//
//  ClearClipboardUseCase.swift
//  IosLibrary
//

import Foundation

/// Clears all items on the pasteboard (P-6).
@MainActor
public struct ClearClipboardUseCase {
    private let TAG = "ClearClipboardUseCase"
    private let repository: ClipboardRepository

    public init(repository: ClipboardRepository) {
        self.repository = repository
    }

    public func execute(scope: PasteboardScope) throws {
        Log.d(TAG, "[execute] scope: \(scope.redactedDescription)")
        try repository.clear(scope: scope)
    }
}
