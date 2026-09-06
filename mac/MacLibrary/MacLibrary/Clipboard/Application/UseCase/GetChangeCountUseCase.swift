//
//  GetChangeCountUseCase.swift
//  MacLibrary
//

import Foundation

/// Reads a pasteboard's current change count.
///
/// Not a public operation of its own: it exists because the change monitor needs the value
/// and may not reach the repository directly. `common.md` forbids Manager to Repository calls
/// precisely so that a path like this cannot grow logic that no test can reach.
@MainActor
public struct GetChangeCountUseCase {

    private let TAG = "GetChangeCountUseCase"

    private let repository: any ClipboardRepository

    /// Creates the use case with the ports it needs. Dependencies are injected so a test can
    /// substitute mocks.
    public init(repository: any ClipboardRepository) {
        self.repository = repository
    }

    /// - Throws: Whatever resolving `scope` reports. A pasteboard that no longer exists is an
    ///   error here; callers decide what that means for them.
    public func callAsFunction(scope: PasteboardScope) throws -> Int {
        Log.d(TAG, "[callAsFunction] scope: \(ClipboardLog.scope(scope))")
        return try repository.changeCount(scope: scope)
    }
}
