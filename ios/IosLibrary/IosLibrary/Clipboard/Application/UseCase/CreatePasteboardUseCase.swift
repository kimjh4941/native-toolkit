//
//  CreatePasteboardUseCase.swift
//  IosLibrary
//

import Foundation

/// Creates (or resolves an existing) named pasteboard, or a new unique-named pasteboard (P-7).
@MainActor
public struct CreatePasteboardUseCase {
    private let TAG = "CreatePasteboardUseCase"
    private let repository: ClipboardRepository

    public init(repository: ClipboardRepository) {
        self.repository = repository
    }

    public func execute(_ request: PasteboardCreationRequest) throws -> PasteboardScope {
        Log.d(TAG, "[execute] request: \(request)")
        if case .named(let name) = request {
            guard !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                throw ClipboardError.invalidPasteboardName(name)
            }
        }
        return try repository.createPasteboard(request)
    }
}
