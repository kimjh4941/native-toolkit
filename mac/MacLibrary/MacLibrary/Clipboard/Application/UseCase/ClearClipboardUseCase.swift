//
//  ClearClipboardUseCase.swift
//  MacLibrary
//

import Foundation

/// OP-06. Empties a pasteboard.
@MainActor
public struct ClearClipboardUseCase {

    private let TAG = "ClearClipboardUseCase"

    private let repository: any ClipboardRepository

    /// Creates the use case with the ports it needs. Dependencies are injected so a test can substitute mocks.
    public init(repository: any ClipboardRepository) {
        self.repository = repository
    }

    /// - Returns: The change count after clearing.
    public func callAsFunction(scope: PasteboardScope) throws -> Int {
        Log.d(TAG, "[callAsFunction] scope: \(ClipboardLog.scope(scope))")
        return try repository.clear(scope: scope)
    }
}
