//
//  ClipboardChangeMonitor.swift
//  MacLibrary
//

import AppKit
import Foundation

/// Polls a pasteboard's change count and reports when it moves.
///
/// macOS has no clipboard change notification, only a counter, so noticing a change means
/// looking. Polling is suspended while the app is inactive: another app owning the foreground
/// is exactly when the clipboard is most likely to change, and waking up to observe that would
/// burn power for an event the app cannot act on yet. On reactivation a single comparison
/// catches up whatever happened in between (RK-11).
@MainActor
final class ClipboardChangeMonitor {

    private let TAG = "ClipboardChangeMonitor"

    private let readChangeCount: @MainActor (PasteboardScope) throws -> Int
    private let tracker: ClipboardChangeTracker

    /// Distinguishes ticks belonging to the current subscription from ones scheduled by a
    /// previous `start`. A restart bumps this, so a tick already in flight is discarded
    /// instead of being delivered to the new subscriber (M-5).
    private var generation: UInt64 = 0

    private var pollTask: Task<Void, Never>?
    private var activeObservers: [any NSObjectProtocol] = []
    private var scope: PasteboardScope?
    private var interval: TimeInterval = 0
    private var onEvent: (@MainActor (ClipboardChangeEvent) -> Void)?

    init(readChangeCount: @escaping @MainActor (PasteboardScope) throws -> Int,
         tracker: ClipboardChangeTracker) {
        Log.d("ClipboardChangeMonitor", "[init]")
        self.readChangeCount = readChangeCount
        self.tracker = tracker
    }

    deinit {
        // Task is Sendable, so it can be cancelled from a nonisolated deinit; the notification
        // observers are removed by the center when it is torn down with the process.
        pollTask?.cancel()
    }

    /// Whether polling is currently scheduled. Diagnostics and tests.
    var isObserving: Bool { pollTask != nil }
    /// Current subscription generation. Tests use it to drive a tick directly.
    var generationForTests: UInt64 { generation }

    /// Starts, or restarts, observation.
    ///
    /// Restart is the only mode: there is deliberately no "already observing" error. A caller
    /// that starts twice wants the second configuration, and failing instead would leave them
    /// observing the first one without noticing (M-5).
    ///
    /// - Throws: ``ClipboardError/invalidConfiguration(_:)`` for an interval outside
    ///   `0 < interval <= 60`, or whatever resolving `scope` reports.
    func start(scope: PasteboardScope,
               interval: TimeInterval,
               onEvent: @escaping @MainActor (ClipboardChangeEvent) -> Void) throws {
        Log.d(TAG, "[start] scope: \(ClipboardLog.scope(scope)), interval: \(interval)")
        guard interval > 0, interval <= 60 else {
            throw ClipboardError.invalidConfiguration(
                "Observation interval must be greater than 0 and at most 60 seconds.")
        }
        // Resolve before touching any existing observation. A caller that mistypes a scope
        // must not lose the monitoring they already had (M-5, IT-09).
        let initialCount = try readChangeCount(scope)

        stop()
        generation &+= 1
        self.scope = scope
        self.interval = interval
        self.onEvent = onEvent
        tracker.hasChanged(scope: scope, changeCount: initialCount)

        observeApplicationActivation()
        schedulePolling()
    }

    /// Stops observation. Idempotent.
    func stop() {
        Log.d(TAG, "[stop] observing: \(pollTask != nil)")
        pollTask?.cancel()
        pollTask = nil
        for observer in activeObservers {
            NotificationCenter.default.removeObserver(observer)
        }
        activeObservers = []
        // Bumping here too means a tick already scheduled cannot deliver after stop.
        generation &+= 1
        scope = nil
        onEvent = nil
    }

    private func schedulePolling() {
        Log.d(TAG, "[schedulePolling] interval: \(interval)")
        let current = generation
        let interval = self.interval
        pollTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(interval))
                guard !Task.isCancelled, let self else { return }
                self.tick(generation: current)
            }
        }
    }

    /// One comparison. Internal so a test can drive it without waiting for the interval.
    func tick(generation: UInt64) {
        Log.d(TAG, "[tick] generation: \(generation)")
        guard generation == self.generation else {
            // Scheduled by a previous subscription. Delivering it would hand the new
            // subscriber an event about a pasteboard they never asked for (M-5, IT-11).
            Log.d(TAG, "[tick] discarding stale generation")
            return
        }
        guard let scope, let onEvent else { return }
        let count: Int
        do {
            count = try readChangeCount(scope)
        } catch {
            // The pasteboard disappeared. Stop rather than report an error on every tick.
            Log.e(TAG, "[tick] scope unreadable, stopping: \(ClipboardLog.scope(scope))")
            stop()
            return
        }
        guard tracker.hasChanged(scope: scope, changeCount: count) else { return }
        onEvent(ClipboardChangeEvent(scope: scope, changeCount: count))
    }

    private func observeApplicationActivation() {
        Log.d(TAG, "[observeApplicationActivation]")
        let center = NotificationCenter.default
        activeObservers.append(center.addObserver(
            forName: NSApplication.didResignActiveNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.suspendPolling() }
        })
        activeObservers.append(center.addObserver(
            forName: NSApplication.didBecomeActiveNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.resumePolling() }
        })
    }

    private func suspendPolling() {
        Log.d(TAG, "[suspendPolling]")
        pollTask?.cancel()
        pollTask = nil
    }

    private func resumePolling() {
        Log.d(TAG, "[resumePolling] scope: \(scope.map(ClipboardLog.scope) ?? "nil")")
        guard scope != nil, pollTask == nil else { return }
        // Catch up on whatever happened while the app was inactive before resuming the timer.
        tick(generation: generation)
        schedulePolling()
    }
}
