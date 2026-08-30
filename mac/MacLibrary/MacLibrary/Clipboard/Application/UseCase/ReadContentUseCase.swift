//
//  ReadContentUseCase.swift
//  MacLibrary
//

import Foundation

/// OP-03. Reads every item and every representation.
///
/// - Important: The result can contain more representations than were written. The pasteboard
///   derives convertible types, so a written `public.rtf` also reads back as plain text
///   (RK-24).
@MainActor
public struct ReadContentUseCase {

    private let TAG = "ReadContentUseCase"

    private let repository: any ClipboardRepository

    /// Creates the use case with the ports it needs. Dependencies are injected so a test can substitute mocks.
    public init(repository: any ClipboardRepository) {
        self.repository = repository
    }

    /// Reads every item and representation.
    public func callAsFunction(scope: PasteboardScope) throws -> ClipboardReadResult {
        Log.d(TAG, "[callAsFunction] scope: \(ClipboardLog.scope(scope))")
        return try repository.read(scope: scope)
    }
}
