//
//  NotificationEventHubTests.swift
//  IosLibraryTests
//
//  UT-23 (design 13.1): the event hub's rules (8.4.2, S-P10). Each hub here has its own
//  "installed" source: `NotificationDelegateRealCenterTests` installs the real proxy for the
//  whole test process, so the process flag cannot tell anything here.
//

import Foundation
import OSLog
import Synchronization
import Testing
@testable import IosLibrary

@MainActor
struct NotificationEventHubTests {

    private func makeHub(capacity: Int = 32, installed: Bool = true) -> NotificationEventHub<Int> {
        NotificationEventHub(name: "test", capacity: capacity, isDelegateInstalled: { installed })
    }

    // MARK: Keeping

    /// Events that arrive with no listener go to the first listener, in order, inside the call.
    @Test func keptEventsGoToTheFirstListenerInsideTheCall() throws {
        let hub = makeHub()
        hub.deliver(1)
        hub.deliver(2)
        hub.deliver(3)
        #expect(hub.keptCount == 3)

        var received: [Int] = []
        let insideTheCall = Flag(true)
        var receivedInsideTheCall: [Bool] = []
        try hub.addListener { event, _ in
            received.append(event)
            receivedInsideTheCall.append(insideTheCall.value)
        }
        insideTheCall.value = false

        #expect(received == [1, 2, 3])
        #expect(receivedInsideTheCall == [true, true, true])
        #expect(hub.keptCount == 0)
    }

    /// At most 32 are kept; beyond that the oldest are dropped.
    @Test func atMost32AreKeptAndTheOldestAreDropped() throws {
        let hub = makeHub()
        for event in 1...40 { hub.deliver(event) }
        #expect(hub.keptCount == 32)

        var received: [Int] = []
        try hub.addListener { event, _ in received.append(event) }
        #expect(received == Array(9...40))
    }

    /// SR-23: the first drop of a hub is logged at `.info`, later ones at `.debug`, which
    /// `OSLogStore` does not return. The hub's name is unique to this test.
    @Test func onlyTheFirstDropIsLoggedAtTheInfoLevel() throws {
        let start = Date().addingTimeInterval(-1)
        let name = "ut23-drop-\(UUID().uuidString)"
        let hub = NotificationEventHub<Int>(name: name, capacity: 1, isDelegateInstalled: { true })
        for event in 1...4 { hub.deliver(event) }
        #expect(hub.keptCount == 1)

        let store = try OSLogStore(scope: .currentProcessIdentifier)
        let drops = try store.getEntries(at: store.position(date: start))
            .compactMap { $0 as? OSLogEntryLog }
            .filter { $0.category == "NotificationEventHub" && $0.composedMessage.hasPrefix("[keep] hub: \(name), no listener: dropped") }
        #expect(drops.count == 1, "three drops; only the first is at a level OSLogStore returns")
        #expect(drops.first?.level == .info)
        #expect(drops.first?.composedMessage.contains("later drops are logged at the debug level") == true)
    }

    /// Duplicates are kept (the system never hands a response twice; two taps are two events).
    @Test func duplicatesAreKept() throws {
        let hub = makeHub()
        hub.deliver(7)
        hub.deliver(7)
        var received: [Int] = []
        try hub.addListener { event, _ in received.append(event) }
        #expect(received == [7, 7])
    }

    /// Only the first listener receives the kept events; the next one receives none of them.
    @Test func aSecondListenerGetsNoKeptEvent() throws {
        let hub = makeHub()
        hub.deliver(1)
        var first: [Int] = []
        var second: [Int] = []
        try hub.addListener { event, _ in first.append(event) }
        try hub.addListener { event, _ in second.append(event) }
        #expect(first == [1])
        #expect(second.isEmpty)
    }

    /// The kept events are taken out before they are handed over: a listener added inside the
    /// first listener does not receive them again (design 13.1 UT-23 "足す前に保ちを外さない").
    @Test func aListenerAddedInsideTheFirstDoesNotGetTheKeptEventsAgain() throws {
        let hub = makeHub()
        hub.deliver(1)
        hub.deliver(2)
        var first: [Int] = []
        var inner: [Int] = []
        var added = false
        try hub.addListener { event, _ in
            first.append(event)
            if !added {
                added = true
                _ = try? hub.addListener { event, _ in inner.append(event) }
            }
        }
        #expect(first == [1, 2])
        #expect(inner.isEmpty)

        hub.deliver(3)
        #expect(first == [1, 2, 3])
        #expect(inner == [3])
    }

    /// A listener that removes itself while it receives the kept events: the rest go to the
    /// oldest remaining listener (here one it added on the way).
    @Test func theRestGoToTheOldestRemainingListener() throws {
        let hub = makeHub()
        for event in 1...4 { hub.deliver(event) }
        var first: [Int] = []
        var inner: [Int] = []
        try hub.addListener { event, registration in
            first.append(event)
            if event == 2 {
                _ = try? hub.addListener { event, _ in inner.append(event) }
                registration.remove()
            }
        }
        #expect(first == [1, 2])
        #expect(inner == [3, 4])
        #expect(hub.keptCount == 0)
    }

    /// With no listener left, the rest are kept again, in front of newer events.
    @Test func withNoListenerLeftTheRestAreKeptAgainInFront() throws {
        let hub = makeHub()
        for event in 1...3 { hub.deliver(event) }
        var first: [Int] = []
        try hub.addListener { event, registration in
            first.append(event)
            registration.remove()
        }
        #expect(first == [1])
        #expect(hub.keptCount == 2)

        hub.deliver(4)
        var next: [Int] = []
        try hub.addListener { event, _ in next.append(event) }
        #expect(next == [2, 3, 4])
    }

    /// An event that arrives on the way, while no listener is left, stays behind the rest of the
    /// kept events (in front of newer ones, design 8.4.2).
    @Test func anEventThatArrivesOnTheWayStaysBehindTheRest() throws {
        let hub = makeHub()
        for event in 1...3 { hub.deliver(event) }
        var first: [Int] = []
        try hub.addListener { event, registration in
            first.append(event)
            registration.remove()
            hub.deliver(9)
        }
        #expect(first == [1])
        var next: [Int] = []
        try hub.addListener { event, _ in next.append(event) }
        #expect(next == [2, 3, 9])
    }

    // MARK: Delivering

    /// Every listener receives each event once, oldest first.
    @Test func everyListenerReceivesEachEventOnce() throws {
        let hub = makeHub()
        var calls: [String] = []
        try hub.addListener { event, _ in calls.append("a\(event)") }
        try hub.addListener { event, _ in calls.append("b\(event)") }
        hub.deliver(1)
        hub.deliver(2)
        #expect(calls == ["a1", "b1", "a2", "b2"])
        #expect(hub.keptCount == 0)
    }

    /// A listener removed by an earlier one during the same delivery is not called.
    @Test func aListenerRemovedDuringTheDeliveryIsNotCalled() throws {
        let hub = makeHub()
        var second: NotificationEventRegistration?
        var calls: [String] = []
        try hub.addListener { event, _ in
            calls.append("a\(event)")
            second?.remove()
        }
        second = try hub.addListener { event, _ in calls.append("b\(event)") }
        hub.deliver(1)
        #expect(calls == ["a1"])
    }

    /// A listener added during a delivery gets the next event, not the current one.
    @Test func aListenerAddedDuringTheDeliveryGetsTheNextEvent() throws {
        let hub = makeHub()
        var inner: [Int] = []
        var added = false
        try hub.addListener { _, _ in
            if !added {
                added = true
                _ = try? hub.addListener { event, _ in inner.append(event) }
            }
        }
        hub.deliver(1)
        hub.deliver(2)
        #expect(inner == [2])
    }

    // MARK: Removing

    /// `remove()` takes the listener out at once; a second call does nothing. With every listener
    /// removed, events are kept again.
    @Test func removeTakesTheListenerOutAndASecondCallDoesNothing() throws {
        let hub = makeHub()
        var first: [Int] = []
        var other: [Int] = []
        let registration = try hub.addListener { event, _ in first.append(event) }
        let otherRegistration = try hub.addListener { event, _ in other.append(event) }
        hub.deliver(1)
        registration.remove()
        registration.remove()
        #expect(hub.listenerCount == 1)
        hub.deliver(2)
        #expect(first == [1])
        #expect(other == [1, 2])

        otherRegistration.remove()
        #expect(hub.listenerCount == 0)
        hub.deliver(3)
        #expect(hub.keptCount == 1)
    }

    // MARK: Not installed (P1-6)

    @Test func withoutTheDelegateAddingThrowsAndAddsNothing() {
        let hub = makeHub(installed: false)
        hub.deliver(1)
        var received: [Int] = []
        #expect(throws: NotificationError.self) {
            try hub.addListener { event, _ in received.append(event) }
        }
        do {
            try hub.addListener { _, _ in }
            Issue.record("addListener did not throw")
        } catch {
            guard case .delegateNotInstalled = error else {
                Issue.record("unexpected error \(error)")
                return
            }
        }
        #expect(received.isEmpty)
        #expect(hub.listenerCount == 0)
        #expect(hub.keptCount == 1, "the kept event stays for a later listener")
    }

    /// The source is read on every call (installing later makes adding work).
    @Test func theInstalledSourceIsReadOnEveryCall() throws {
        let installed = Atomic<Bool>(false)
        let hub = NotificationEventHub<Int>(name: "test", isDelegateInstalled: { installed.load(ordering: .relaxed) })
        #expect(throws: NotificationError.self) { try hub.addListener { _, _ in } }
        installed.store(true, ordering: .relaxed)
        try hub.addListener { _, _ in }
        #expect(hub.listenerCount == 1)
    }
}

/// A flag changed after a closure captured it.
@MainActor
private final class Flag {
    var value: Bool
    init(_ value: Bool) { self.value = value }
}
