//
//  ClipboardChangeTracker.swift
//  MacLibrary
//

import Foundation

/// Remembers the last change count seen for each scope.
///
/// macOS reports clipboard activity only as a monotonically increasing counter, so detecting a
/// change means comparing against the previous value. Keeping that memory here rather than in
/// the monitor lets both the polling observer and the one-shot foreground check share it.
@MainActor
public final class ClipboardChangeTracker {

    private let TAG = "ClipboardChangeTracker"

    private var lastSeen: [PasteboardScope: Int] = [:]

    /// Creates the use case with the ports it needs. Dependencies are injected so a test can substitute mocks.
    public init() {}

    /// Records `changeCount` and reports whether it differs from the previous value.
    ///
    /// The first observation of a scope counts as a change: the caller has not seen this
    /// pasteboard before, so its contents are new to them.
    @discardableResult
    public func hasChanged(scope: PasteboardScope, changeCount: Int) -> Bool {
        Log.d(TAG, "[hasChanged] scope: \(ClipboardLog.scope(scope)), changeCount: \(changeCount)")
        let previous = lastSeen[scope]
        lastSeen[scope] = changeCount
        return previous != changeCount
    }

    /// Forgets a scope, so the next observation counts as a change again.
    public func reset(scope: PasteboardScope) {
        Log.d(TAG, "[reset] scope: \(ClipboardLog.scope(scope))")
        lastSeen[scope] = nil
    }

    /// Forgets every scope.
    public func resetAll() {
        Log.d(TAG, "[resetAll]")
        lastSeen.removeAll()
    }
}
