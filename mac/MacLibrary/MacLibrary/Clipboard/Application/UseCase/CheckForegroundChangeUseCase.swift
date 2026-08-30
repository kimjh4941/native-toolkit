//
//  CheckForegroundChangeUseCase.swift
//  MacLibrary
//

import Foundation

/// OP-15. One-shot check for whether the pasteboard changed since the last look.
///
/// Intended for the moment an app returns to the foreground, where polling has been stopped
/// and a single comparison is enough.
@MainActor
public struct CheckForegroundChangeUseCase {

    private let TAG = "CheckForegroundChangeUseCase"

    private let repository: any ClipboardRepository
    private let tracker: ClipboardChangeTracker

    /// Creates the use case with the ports it needs. Dependencies are injected so a test can substitute mocks.
    public init(repository: any ClipboardRepository, tracker: ClipboardChangeTracker) {
        self.repository = repository
        self.tracker = tracker
    }

    /// - Returns: `true` on the first check of a scope, since the caller has not seen that
    ///   pasteboard before.
    public func callAsFunction(scope: PasteboardScope) throws -> Bool {
        Log.d(TAG, "[callAsFunction] scope: \(ClipboardLog.scope(scope))")
        let current = try repository.changeCount(scope: scope)
        return tracker.hasChanged(scope: scope, changeCount: current)
    }
}
