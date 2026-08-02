//
//  GetSnapshotUseCase.swift
//  IosLibrary
//

import Foundation

/// Reads clipboard metadata using only system APIs documented to avoid user
/// notifications/prompts (P-5).
@MainActor
public struct GetSnapshotUseCase {
    private let TAG = "GetSnapshotUseCase"
    private let repository: ClipboardRepository

    public init(repository: ClipboardRepository) {
        self.repository = repository
    }

    public func execute(matchingTypes: [String]?, scope: PasteboardScope) throws -> ClipboardSnapshot {
        Log.d(TAG, "[execute] scope: \(scope), matchingTypesCount: \(matchingTypes?.count ?? 0)")
        return try repository.snapshot(matchingTypes: matchingTypes, scope: scope)
    }
}
