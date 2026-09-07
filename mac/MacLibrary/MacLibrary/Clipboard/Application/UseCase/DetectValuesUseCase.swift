//
//  DetectValuesUseCase.swift
//  MacLibrary
//

import Foundation

/// OP-10. Reads the detected values themselves.
///
/// - Important: This reads pasteboard contents. The system notifies the user on a match and
///   can deny access, in which case the call throws (RK-03). Call it in response to a user
///   action, never speculatively.
@MainActor
public struct DetectValuesUseCase {

    private let TAG = "DetectValuesUseCase"

    private let repository: any ClipboardRepository

    /// Creates the use case with the ports it needs. Dependencies are injected so a test can substitute mocks.
    public init(repository: any ClipboardRepository) {
        self.repository = repository
    }

    /// Reads the matched values. Rejects an empty pattern set.
    public func callAsFunction(_ patterns: Set<ClipboardDetectionPattern>,
                               scope: PasteboardScope) async throws -> ClipboardDetectedValues {
        Log.d(TAG, "[callAsFunction] patterns: \(patterns.count), scope: \(ClipboardLog.scope(scope))")
        guard !patterns.isEmpty else { throw ClipboardError.emptyDetectionPatterns }
        return try await repository.detectValues(patterns, scope: scope)
    }
}
