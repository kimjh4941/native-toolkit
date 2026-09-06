//
//  DetectPatternsUseCase.swift
//  MacLibrary
//

import Foundation

/// OP-09. Reports which of the requested patterns the pasteboard contains.
///
/// - Important: The header for the underlying API says it does not notify the user, but that
///   is not a contract this library can guarantee (RK-01 / RK-22).
@MainActor
public struct DetectPatternsUseCase {

    private let TAG = "DetectPatternsUseCase"

    private let repository: any ClipboardRepository

    /// Creates the use case with the ports it needs. Dependencies are injected so a test can substitute mocks.
    public init(repository: any ClipboardRepository) {
        self.repository = repository
    }

    /// - Throws: ``ClipboardError/emptyDetectionPatterns`` for an empty set, and
    ///   ``ClipboardError/detectionUnavailable(minimumOS:)`` below macOS 15.4.
    public func callAsFunction(_ patterns: Set<ClipboardDetectionPattern>,
                               scope: PasteboardScope) async throws -> Set<ClipboardDetectionPattern> {
        Log.d(TAG, "[callAsFunction] patterns: \(patterns.count), scope: \(ClipboardLog.scope(scope))")
        // An empty request would always answer "nothing found", which reads as a negative
        // result rather than as a caller mistake.
        guard !patterns.isEmpty else { throw ClipboardError.emptyDetectionPatterns }
        return try await repository.detectPatterns(patterns, scope: scope)
    }
}
