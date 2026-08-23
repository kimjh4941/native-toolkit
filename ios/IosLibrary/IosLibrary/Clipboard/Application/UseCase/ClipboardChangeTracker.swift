//
//  ClipboardChangeTracker.swift
//  IosLibrary
//

import Foundation

/// Pure state machine that reconciles `UIPasteboard.changeCount` polling with
/// `changedNotification` delivery, so the same change is never reported twice.
///
/// Synchronization rules:
/// 1. `resync(to:)` on `startObserving` so a stop/start cycle never compares against a stale baseline.
/// 2. `markReported(current:)` when `changedNotification` fires, advancing the baseline so the
///    next foreground comparison does not re-report the same change.
/// 3. `hasChanged(current:)` always advances the baseline after comparing.
public struct ClipboardChangeTracker: Sendable {
    private var baseline: Int

    public init(baseline: Int) {
        self.baseline = baseline
    }

    /// Resynchronizes the baseline (call when starting/resuming observation).
    public mutating func resync(to current: Int) {
        baseline = current
    }

    /// Advances the baseline because a notification already reported this change.
    public mutating func markReported(current: Int) {
        baseline = current
    }

    /// Returns whether `current` differs from the tracked baseline. Always advances the baseline.
    public mutating func hasChanged(current: Int) -> Bool {
        defer { baseline = current }
        return current != baseline
    }
}
