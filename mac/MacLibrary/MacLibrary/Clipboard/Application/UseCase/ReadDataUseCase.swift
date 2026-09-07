//
//  ReadDataUseCase.swift
//  MacLibrary
//

import Foundation

/// OP-04. Reads the bytes for one uniform type identifier.
@MainActor
public struct ReadDataUseCase {

    private let TAG = "ReadDataUseCase"

    private let repository: any ClipboardRepository

    /// Creates the use case with the ports it needs. Dependencies are injected so a test can substitute mocks.
    public init(repository: any ClipboardRepository) {
        self.repository = repository
    }

    /// - Returns: `nil` when the pasteboard carries no such type. A missing type is an ordinary
    ///   outcome, not a failure (M-1).
    public func callAsFunction(utType: String, scope: PasteboardScope) throws -> Data? {
        Log.d(TAG, "[callAsFunction] utType: \(utType), scope: \(ClipboardLog.scope(scope))")
        return try repository.readData(utType: utType, scope: scope)
    }
}
