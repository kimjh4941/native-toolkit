//
//  GetSnapshotUseCase.swift
//  IosLibrary
//

import Foundation
import os

private let logger = Logger(subsystem: "com.jonghyunkim.nativetoolkit.IosLibrary", category: "GetSnapshotUseCase")

/// Reads clipboard metadata using only system APIs documented to avoid user
/// notifications/prompts (P-5).
@MainActor
public struct GetSnapshotUseCase {
    private let repository: ClipboardRepository

    public init(repository: ClipboardRepository) {
        self.repository = repository
    }

    public func execute(matchingTypes: [String]?, scope: PasteboardScope) throws -> ClipboardSnapshot {
        logger.log(level: .libraryDebug, "[execute] scope: \(scope.redactedDescription, privacy: .public), matchingTypesCount: \(matchingTypes?.count ?? 0, privacy: .public)")
        return try repository.snapshot(matchingTypes: matchingTypes, scope: scope)
    }
}
