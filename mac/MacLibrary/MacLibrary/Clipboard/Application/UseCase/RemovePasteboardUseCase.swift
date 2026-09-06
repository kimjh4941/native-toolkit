//
//  RemovePasteboardUseCase.swift
//  MacLibrary
//

import Foundation

/// OP-08. Releases a pasteboard's server side resources.
@MainActor
public struct RemovePasteboardUseCase {

    private let TAG = "RemovePasteboardUseCase"

    private let repository: any ClipboardRepository

    /// Creates the use case with the ports it needs. Dependencies are injected so a test can substitute mocks.
    public init(repository: any ClipboardRepository) {
        self.repository = repository
    }

    /// - Throws: ``ClipboardError/cannotReleaseStandardPasteboard(name:)`` for the general
    ///   pasteboard and the other standard names. Releasing one would break other apps, so the
    ///   refusal is unconditional (RK-07).
    public func callAsFunction(_ scope: PasteboardScope) throws {
        Log.d(TAG, "[callAsFunction] scope: \(ClipboardLog.scope(scope))")
        try repository.removePasteboard(scope)
    }
}
