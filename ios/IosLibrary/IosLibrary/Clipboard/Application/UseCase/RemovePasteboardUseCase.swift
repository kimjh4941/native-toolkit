//
//  RemovePasteboardUseCase.swift
//  IosLibrary
//

import Foundation

/// Invalidates a named pasteboard (P-8). Removing `.general` is rejected: the system silently
/// ignores such a request, which would otherwise hide caller mistakes.
@MainActor
public struct RemovePasteboardUseCase {
    private let TAG = "RemovePasteboardUseCase"
    private let repository: ClipboardRepository

    public init(repository: ClipboardRepository) {
        self.repository = repository
    }

    public func execute(_ scope: PasteboardScope) throws {
        Log.d(TAG, "[execute] scope: \(scope.redactedDescription)")
        guard scope != .general else {
            throw ClipboardError.cannotRemoveGeneralPasteboard
        }
        try repository.removePasteboard(scope)
    }
}
