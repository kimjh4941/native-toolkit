//
//  DetectMetadataUseCase.swift
//  MacLibrary
//

import Foundation

/// OP-11. Reads the limited metadata the system exposes without the contents.
@MainActor
public struct DetectMetadataUseCase {

    private let TAG = "DetectMetadataUseCase"

    private let repository: any ClipboardRepository

    /// Creates the use case with the ports it needs. Dependencies are injected so a test can substitute mocks.
    public init(repository: any ClipboardRepository) {
        self.repository = repository
    }

    /// Reads the metadata the system can report.
    public func callAsFunction(scope: PasteboardScope) async throws -> ClipboardDetectedMetadata {
        Log.d(TAG, "[callAsFunction] scope: \(ClipboardLog.scope(scope))")
        return try await repository.detectMetadata(scope: scope)
    }
}
