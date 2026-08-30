//
//  ClipboardChangeTrackerTests.swift
//  MacLibraryTests
//

import Testing
import Foundation
@testable import MacLibrary

@Suite("ClipboardChangeTracker")
@MainActor
struct ClipboardChangeTrackerTests {

    @Test("the first observation counts as a change")
    func firstObservationIsAChange() {
        let tracker = ClipboardChangeTracker()
        // The caller has never seen this pasteboard, so its contents are new to them.
        #expect(tracker.hasChanged(scope: .general, changeCount: 7))
    }

    @Test("the same change count twice is not a change")
    func sameValueIsNotAChange() {
        let tracker = ClipboardChangeTracker()
        _ = tracker.hasChanged(scope: .general, changeCount: 7)
        #expect(!tracker.hasChanged(scope: .general, changeCount: 7))
    }

    @Test("an increment is a change")
    func incrementIsAChange() {
        let tracker = ClipboardChangeTracker()
        _ = tracker.hasChanged(scope: .general, changeCount: 7)
        #expect(tracker.hasChanged(scope: .general, changeCount: 8))
        #expect(!tracker.hasChanged(scope: .general, changeCount: 8))
    }

    @Test("scopes are tracked independently")
    func scopesAreIndependent() {
        let tracker = ClipboardChangeTracker()
        _ = tracker.hasChanged(scope: .general, changeCount: 1)
        // A different pasteboard has its own history, even at the same count.
        #expect(tracker.hasChanged(scope: .named("a"), changeCount: 1))
        #expect(!tracker.hasChanged(scope: .general, changeCount: 1))
    }

    @Test("resetting a scope makes the next observation a change again")
    func resetForgetsOneScope() {
        let tracker = ClipboardChangeTracker()
        _ = tracker.hasChanged(scope: .general, changeCount: 1)
        _ = tracker.hasChanged(scope: .named("a"), changeCount: 1)

        tracker.reset(scope: .general)

        #expect(tracker.hasChanged(scope: .general, changeCount: 1))
        #expect(!tracker.hasChanged(scope: .named("a"), changeCount: 1))
    }

    @Test("resetting everything forgets every scope")
    func resetAllForgetsEverything() {
        let tracker = ClipboardChangeTracker()
        _ = tracker.hasChanged(scope: .general, changeCount: 1)
        _ = tracker.hasChanged(scope: .named("a"), changeCount: 1)

        tracker.resetAll()

        #expect(tracker.hasChanged(scope: .general, changeCount: 1))
        #expect(tracker.hasChanged(scope: .named("a"), changeCount: 1))
    }
}
