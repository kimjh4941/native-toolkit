//
//  DetectPatternsUseCase.swift
//  IosLibrary
//

import Foundation

/// Detects which patterns are present on the pasteboard, without reading matched values (P-9).
///
/// `detectedPatterns(for:)` has no cancellation token, so this UseCase races it against Task
/// cancellation and a timeout via `ClipboardAsyncRaceCoordinator`; the caller is resumed
/// immediately in either case, and the underlying system call's eventual result is discarded.
@MainActor
public struct DetectPatternsUseCase {
    private let TAG = "DetectPatternsUseCase"
    private let repository: ClipboardRepository
    private let timeouts: ClipboardTimeouts

    public init(repository: ClipboardRepository, timeouts: ClipboardTimeouts = .default) {
        self.repository = repository
        self.timeouts = timeouts
    }

    public func execute(
        _ patterns: Set<ClipboardDetectionPattern>,
        scope: PasteboardScope
    ) async throws -> Set<ClipboardDetectionPattern> {
        Log.d(TAG, "[execute] scope: \(scope), patternCount: \(patterns.count)")
        guard !patterns.isEmpty else { throw ClipboardError.emptyDetectionPatterns }
        let repository = self.repository
        return try await ClipboardAsyncRaceCoordinator.run(
            timeout: timeouts.detection,
            operationKind: .detection
        ) {
            try await repository.detectPatterns(patterns, scope: scope)
        }
    }
}
