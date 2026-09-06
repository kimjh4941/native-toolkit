//
//  ClipboardChangeMonitorTests.swift
//  MacLibraryTests
//

import Testing
import Foundation
@testable import MacLibrary

@Suite("ClipboardChangeMonitor")
@MainActor
struct ClipboardChangeMonitorTests {

    /// Stands in for the repository's change count, so a test can move the counter by hand.
    private final class Counter {
        var value = 0
        var failingScopes: Set<PasteboardScope> = []
        var readCount = 0
    }

    private func makeMonitor() -> (ClipboardChangeMonitor, Counter, ClipboardChangeTracker) {
        let counter = Counter()
        let tracker = ClipboardChangeTracker()
        let monitor = ClipboardChangeMonitor(
            readChangeCount: { scope in
                counter.readCount += 1
                if counter.failingScopes.contains(scope) {
                    throw ClipboardError.invalidPasteboardName(scope.name ?? "")
                }
                return counter.value
            },
            tracker: tracker)
        return (monitor, counter, tracker)
    }

    // MARK: - IT-09

    @Test("IT-09: a restart that cannot resolve its scope leaves the existing observation running")
    func failedRestartKeepsExistingObservation() throws {
        let (monitor, counter, _) = makeMonitor()
        try monitor.start(scope: .general, interval: 0.05) { _ in }
        #expect(monitor.isObserving)

        counter.failingScopes = [.named("bad")]
        #expect(throws: ClipboardError.invalidPasteboardName("bad")) {
            try monitor.start(scope: .named("bad"), interval: 0.05) { _ in }
        }

        // Resolving first is what makes this possible: a mistyped scope must not cost the
        // caller the monitoring they already had (M-5).
        #expect(monitor.isObserving)
    }

    // MARK: - IT-10

    @Test("IT-10: a change is reported exactly once")
    func reportsChangeOnce() throws {
        let (monitor, counter, _) = makeMonitor()
        var events: [ClipboardChangeEvent] = []
        try monitor.start(scope: .general, interval: 60) { events.append($0) }

        counter.value = 1
        monitor.tick(generation: monitor.generationForTests)
        monitor.tick(generation: monitor.generationForTests)

        #expect(events.count == 1)
        #expect(events.first?.changeCount == 1)
    }

    @Test("IT-10: no change means no event")
    func unchangedProducesNoEvent() throws {
        let (monitor, _, _) = makeMonitor()
        var events: [ClipboardChangeEvent] = []
        try monitor.start(scope: .general, interval: 60) { events.append($0) }

        monitor.tick(generation: monitor.generationForTests)

        // The initial count is recorded at start, so the first tick has nothing new to say.
        #expect(events.isEmpty)
    }

    @Test("IT-10: stopping ends delivery")
    func stopEndsDelivery() throws {
        let (monitor, counter, _) = makeMonitor()
        var events: [ClipboardChangeEvent] = []
        try monitor.start(scope: .general, interval: 60) { events.append($0) }
        let generation = monitor.generationForTests

        monitor.stop()
        counter.value = 5
        monitor.tick(generation: generation)

        #expect(events.isEmpty)
        #expect(!monitor.isObserving)
    }

    @Test("stopping twice is a no-op")
    func stopIsIdempotent() throws {
        let (monitor, _, _) = makeMonitor()
        try monitor.start(scope: .general, interval: 60) { _ in }
        monitor.stop()
        monitor.stop()
        #expect(!monitor.isObserving)
    }

    // MARK: - IT-11 / CT-07

    @Test("IT-11: a tick from a previous subscription is discarded")
    func staleGenerationIsDiscarded() throws {
        let (monitor, counter, _) = makeMonitor()
        var events: [ClipboardChangeEvent] = []
        try monitor.start(scope: .general, interval: 60) { _ in
            Issue.record("the first subscriber must not be called after a restart")
        }
        let oldGeneration = monitor.generationForTests

        try monitor.start(scope: .general, interval: 60) { events.append($0) }
        counter.value = 3
        monitor.tick(generation: oldGeneration)

        #expect(events.isEmpty)
    }

    @Test("CT-07: restarting does not deliver an event twice")
    func restartDoesNotDuplicate() throws {
        let (monitor, counter, _) = makeMonitor()
        var events: [ClipboardChangeEvent] = []
        let handler: @MainActor (ClipboardChangeEvent) -> Void = { events.append($0) }

        try monitor.start(scope: .general, interval: 60, onEvent: handler)
        counter.value = 1
        // A restart re-reads and records the current count, so the change is already accounted
        // for by the time the new subscription starts ticking.
        try monitor.start(scope: .general, interval: 60, onEvent: handler)
        monitor.tick(generation: monitor.generationForTests)

        #expect(events.isEmpty)
    }

    @Test("CT-07: repeated starts leave exactly one poller")
    func repeatedStartsLeaveOnePoller() throws {
        let (monitor, _, _) = makeMonitor()
        for _ in 0..<3 {
            try monitor.start(scope: .general, interval: 60) { _ in }
        }
        #expect(monitor.isObserving)
        monitor.stop()
        #expect(!monitor.isObserving)
    }

    // MARK: - Interval validation

    @Test("an interval outside the allowed range is rejected", arguments: [0.0, -1.0, 61.0])
    func rejectsInvalidInterval(interval: TimeInterval) {
        let (monitor, _, _) = makeMonitor()
        #expect(throws: ClipboardError.invalidConfiguration(
            "Observation interval must be greater than 0 and at most 60 seconds.")) {
            try monitor.start(scope: .general, interval: interval) { _ in }
        }
        #expect(!monitor.isObserving)
    }

    @Test("the boundary interval is accepted")
    func acceptsBoundaryInterval() throws {
        let (monitor, _, _) = makeMonitor()
        try monitor.start(scope: .general, interval: 60) { _ in }
        #expect(monitor.isObserving)
    }

    // MARK: - Failure handling

    @Test("a pasteboard that disappears stops the observation")
    func unreadableScopeStopsObservation() throws {
        let (monitor, counter, _) = makeMonitor()
        var events: [ClipboardChangeEvent] = []
        try monitor.start(scope: .named("temp"), interval: 60) { events.append($0) }

        counter.failingScopes = [.named("temp")]
        monitor.tick(generation: monitor.generationForTests)

        // Reporting an error on every tick would be noise; the pasteboard is simply gone.
        #expect(!monitor.isObserving)
        #expect(events.isEmpty)
    }

    // MARK: - Tracker sharing

    @Test("the monitor and the foreground check share one tracker")
    func trackerIsShared() throws {
        let (monitor, counter, tracker) = makeMonitor()
        var events: [ClipboardChangeEvent] = []
        try monitor.start(scope: .general, interval: 60) { events.append($0) }

        counter.value = 2
        // Standing in for a foreground check that already observed this change.
        tracker.hasChanged(scope: .general, changeCount: 2)
        monitor.tick(generation: monitor.generationForTests)

        #expect(events.isEmpty)
    }
}
