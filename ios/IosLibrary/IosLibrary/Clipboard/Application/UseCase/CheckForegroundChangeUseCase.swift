//
//  CheckForegroundChangeUseCase.swift
//  IosLibrary
//

import Foundation

/// Detects clipboard changes by comparing `changeCount` on foreground return, reconciled with
/// `changedNotification` delivery via `ClipboardChangeTracker` (P-15).
///
/// One tracker is kept per `PasteboardScope` so that observing multiple scopes does not cross
/// contaminate their baselines.
@MainActor
public final class CheckForegroundChangeUseCase {
    private let TAG = "CheckForegroundChangeUseCase"
    private let repository: ClipboardRepository
    private var trackers: [PasteboardScope: ClipboardChangeTracker] = [:]

    public init(repository: ClipboardRepository) {
        self.repository = repository
    }

    /// Resynchronizes the tracked baseline for `scope`. Call when observation starts (or resumes)
    /// so a stop/start cycle never compares against a stale baseline.
    public func resync(scope: PasteboardScope) {
        Log.d(TAG, "[resync] scope: \(scope.redactedDescription)")
        let current = (try? repository.changeCount(scope: scope)) ?? 0
        trackers[scope] = ClipboardChangeTracker(baseline: current)
    }

    /// Marks the tracked baseline for `scope` as already reported. Call when
    /// `changedNotification` fires, so the next `execute` does not re-report the same change.
    public func markReported(scope: PasteboardScope) {
        Log.d(TAG, "[markReported] scope: \(scope.redactedDescription)")
        let current = (try? repository.changeCount(scope: scope)) ?? 0
        var tracker = trackers[scope] ?? ClipboardChangeTracker(baseline: current)
        tracker.markReported(current: current)
        trackers[scope] = tracker
    }

    /// Returns whether `scope`'s clipboard changed since the last check. Always advances the
    /// tracked baseline.
    public func execute(scope: PasteboardScope) -> Bool {
        Log.d(TAG, "[execute] scope: \(scope.redactedDescription)")
        guard let current = try? repository.changeCount(scope: scope) else { return false }
        var tracker = trackers[scope] ?? ClipboardChangeTracker(baseline: current)
        let changed = tracker.hasChanged(current: current)
        trackers[scope] = tracker
        return changed
    }
}
