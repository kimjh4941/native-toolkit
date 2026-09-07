//
//  GetAccessBehaviorUseCase.swift
//  MacLibrary
//

import Foundation

/// OP-12. Reports how the system currently treats pasteboard reads by this app.
@MainActor
public struct GetAccessBehaviorUseCase {

    private let TAG = "GetAccessBehaviorUseCase"

    private let repository: any ClipboardRepository

    /// Creates the use case with the ports it needs. Dependencies are injected so a test can substitute mocks.
    public init(repository: any ClipboardRepository) {
        self.repository = repository
    }

    /// - Returns: ``ClipboardAccessBehavior/unavailable`` below macOS 15.4, where the property
    ///   does not exist. That is reported as a value rather than an error because not knowing
    ///   the behaviour is a normal state on those versions (M-2).
    public func callAsFunction(scope: PasteboardScope) throws -> ClipboardAccessBehavior {
        Log.d(TAG, "[callAsFunction] scope: \(ClipboardLog.scope(scope))")
        return try repository.accessBehavior(scope: scope)
    }
}
