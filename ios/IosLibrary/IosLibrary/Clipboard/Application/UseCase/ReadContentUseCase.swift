//
//  ReadContentUseCase.swift
//  IosLibrary
//

import Foundation

/// Reads the clipboard's items synchronously (P-3). An empty clipboard is not an error.
@MainActor
public struct ReadContentUseCase {
    private let TAG = "ReadContentUseCase"
    private let repository: ClipboardRepository

    public init(repository: ClipboardRepository) {
        self.repository = repository
    }

    public func execute(scope: PasteboardScope) throws -> ClipboardReadResult {
        Log.d(TAG, "[execute] scope: \(scope)")
        return try repository.read(scope: scope)
    }
}
