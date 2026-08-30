//
//  AppendContentUseCase.swift
//  MacLibrary
//

import Foundation

/// OP-02. Adds items to a pasteboard this app still owns.
///
/// - Important: Unlike the iOS clipboard, appending requires ownership. The repository
///   compares the change count and reports ``ClipboardError/ownershipLost(expected:actual:)``
///   rather than silently doing nothing (RK-23).
@MainActor
public struct AppendContentUseCase {

    private let TAG = "AppendContentUseCase"

    private let repository: any ClipboardRepository
    private let validator: ClipboardContentValidator

    /// Creates the use case with the ports it needs. Dependencies are injected so a test can substitute mocks.
    public init(repository: any ClipboardRepository, validator: ClipboardContentValidator) {
        self.repository = repository
        self.validator = validator
    }

    /// Validates the content, then appends it.
    public func callAsFunction(_ content: ClipboardContent,
                               ownership: PasteboardOwnership) throws -> PasteboardOwnership {
        Log.d(TAG, "[callAsFunction] content: \(ClipboardLog.content(content)), "
              + "scope: \(ClipboardLog.scope(ownership.scope)), expected: \(ownership.changeCount)")
        try validator.validate(content)
        return try repository.append(content, ownership: ownership)
    }
}
