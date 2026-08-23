//
//  ClipboardChangeTrackerTests.swift
//  IosLibraryTests
//

import Testing
@testable import IosLibrary

struct ClipboardChangeTrackerTests {
    @Test func hasChangedIsTrueWhenDifferentFalseWhenSame() {
        var tracker = ClipboardChangeTracker(baseline: 0)
        #expect(tracker.hasChanged(current: 0) == false)
        #expect(tracker.hasChanged(current: 1) == true)
    }

    @Test func hasChangedAdvancesBaselineSoRepeatedCallsAreFalse() {
        var tracker = ClipboardChangeTracker(baseline: 0)
        #expect(tracker.hasChanged(current: 5) == true)
        #expect(tracker.hasChanged(current: 5) == false)
    }

    @Test func markReportedPreventsDoubleReporting() {
        var tracker = ClipboardChangeTracker(baseline: 0)
        tracker.markReported(current: 3)
        #expect(tracker.hasChanged(current: 3) == false)
    }

    @Test func resyncIgnoresChangesWhileStopped() {
        var tracker = ClipboardChangeTracker(baseline: 0)
        tracker.resync(to: 10)
        #expect(tracker.hasChanged(current: 10) == false)
    }
}
