//
//  DetectValuesUseCase.swift
//  IosLibrary
//

import Foundation
import os

private let logger = Logger(subsystem: "com.jonghyunkim.nativetoolkit.IosLibrary", category: "DetectValuesUseCase")

/// Detects patterns on the pasteboard and reads their matched values (P-10).
///
/// See `DetectPatternsUseCase` for the cancellation/timeout contract shared with this UseCase.
@MainActor
public struct DetectValuesUseCase {
    private let repository: ClipboardRepository
    private let timeouts: ClipboardTimeouts

    public init(repository: ClipboardRepository, timeouts: ClipboardTimeouts = .default) {
        self.repository = repository
        self.timeouts = timeouts
    }

    public func execute(
        _ patterns: Set<ClipboardDetectionPattern>,
        scope: PasteboardScope
    ) async throws -> ClipboardDetectedValues {
        logger.log(level: .libraryDebug, "[execute] scope: \(scope.redactedDescription, privacy: .public), patternCount: \(patterns.count, privacy: .public)")
        guard !patterns.isEmpty else { throw ClipboardError.emptyDetectionPatterns }
        let repository = self.repository
        return try await ClipboardAsyncRaceCoordinator.run(
            timeout: timeouts.detection,
            operationKind: .detection
        ) {
            try await repository.detectValues(patterns, scope: scope)
        }
    }
}
