//
//  NotificationCategoryQueueTests.swift
//  IosLibraryTests
//
//  UT-28 (design 13.1, 8.5.6, S-P14, S-P28): the one queue of the category changes. A stand-in
//  center (`FakeCategoryCenter`) logs every read and write-back, and suspends in each read, so that
//  two changes running at the same time would read the same old set.
//

import Foundation
import Synchronization
import Testing
import UserNotifications
@testable import IosLibrary

/// Counts calls and remembers their order; any thread.
private final class Recorder: Sendable {
    private let entries = Mutex<[String]>([])
    private let threads = Mutex<[Bool]>([])

    func record(_ entry: String) {
        let isMain = Thread.isMainThread
        entries.withLock { $0.append(entry) }
        threads.withLock { $0.append(isMain) }
    }

    var all: [String] { entries.withLock { $0 } }
    var onMain: [Bool] { threads.withLock { $0 } }
}

/// Waits (up to `seconds`) until `condition` holds.
private func waitUntil(_ seconds: Double = 5, _ condition: @Sendable () -> Bool) async throws {
    let deadline = Date().addingTimeInterval(seconds)
    while !condition() && Date() < deadline {
        try await Task.sleep(nanoseconds: 2_000_000)
    }
}

private func category(_ identifier: String, actions: [String] = []) -> NotificationCategory {
    NotificationCategory(identifier: identifier, actions: actions.map { NotificationAction(identifier: $0, title: $0) })
}

@Suite(.serialized)
struct NotificationCategoryQueueTests {

    // MARK: - The queue

    /// One change: read, write-back, read again, then the completion.
    @Test func aChangeCompletesAfterItIsAppliedAndReadBack() async throws {
        let center = FakeCategoryCenter()
        let queue = NotificationCategoryQueue(center: center)

        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            queue.enqueue(.register(category("a"))) {
                center.note("completion")
                continuation.resume()
            }
        }

        #expect(center.log == ["read", "write +a", "read", "completion"])
        #expect(center.identifiers == ["a"])
    }

    /// Changes from one thread take effect in the order of the calls; a removal right after a
    /// registration is not undone by it.
    @Test func changesFromOneThreadKeepTheirOrder() async throws {
        let center = FakeCategoryCenter()
        let queue = NotificationCategoryQueue(center: center)
        let done = Recorder()

        queue.enqueue(.register(category("a"))) { done.record("1") }
        queue.enqueue(.register(category("b"))) { done.record("2") }
        queue.enqueue(.remove(identifier: "a")) { done.record("3") }
        queue.enqueue(.register(category("c"))) { done.record("4") }
        try await waitUntil { done.all.count == 4 }

        #expect(center.writes == ["+a", "+b", "-a", "+c"])
        #expect(done.all == ["1", "2", "3", "4"])
        #expect(center.identifiers == ["b", "c"])
    }

    /// 8 threads at the same time: no change is lost (each reads the set the previous one wrote).
    @Test func concurrentChangesFromEightThreadsAreAllKept() async throws {
        let center = FakeCategoryCenter()
        let queue = NotificationCategoryQueue(center: center)
        let done = Recorder()

        DispatchQueue.concurrentPerform(iterations: 8) { thread in
            for index in 0..<25 {
                let identifier = "t\(thread)-\(index)"
                queue.enqueue(.register(category(identifier))) { done.record(identifier) }
                if index.isMultiple(of: 2) {
                    queue.enqueue(.remove(identifier: identifier)) { done.record("-" + identifier) }
                }
            }
        }
        let changeCount = 8 * 25 + 8 * 13
        try await waitUntil { done.all.count == changeCount }

        #expect(done.all.count == changeCount)
        let expected = Set((0..<8).flatMap { thread in
            (0..<25).filter { !$0.isMultiple(of: 2) }.map { "t\(thread)-\($0)" }
        })
        #expect(center.identifiers == expected)
        // Every change is one read, one write-back and one read again, never interleaved.
        let pattern = center.log.filter { $0 != "completion" }
        let entryCount = changeCount * 3
        #expect(pattern.count == entryCount)
        for start in stride(from: 0, to: pattern.count, by: 3) {
            #expect(pattern[start] == "read" && pattern[start + 1].hasPrefix("write") && pattern[start + 2] == "read")
        }
    }

    /// A change enqueued while another is between its read and its write-back waits for it, and
    /// starts no second drain.
    @Test func aChangeEnqueuedDuringAnotherWaitsAndStartsNoSecondDrain() async throws {
        let center = FakeCategoryCenter()
        let queue = NotificationCategoryQueue(center: center)
        let done = Recorder()

        center.holdNextRead()
        queue.enqueue(.register(category("a"))) { done.record("a") }
        try await waitUntil { center.isHoldingARead }
        #expect(center.isHoldingARead)
        queue.enqueue(.remove(identifier: "a")) { done.record("-a") }
        queue.enqueue(.register(category("b"))) { done.record("b") }
        #expect(queue.drainStartCount == 1)
        #expect(center.reads == 0)

        center.releaseRead()
        try await waitUntil { done.all.count == 3 }

        #expect(done.all == ["a", "-a", "b"])
        #expect(center.writes == ["+a", "-a", "+b"])
        #expect(queue.drainStartCount == 1)
    }

    /// A change enqueued right before the drain looks at the queue for the next one is taken by
    /// that drain; one enqueued right after the drain ended starts a new one. Neither is left.
    @Test func aChangeEnqueuedAtTheEndOfADrainIsNeverLeft() async throws {
        let center = FakeCategoryCenter()
        let done = Recorder()
        let queueBox = Mutex<NotificationCategoryQueue?>(nil)
        let step = Mutex(0)
        let queue = NotificationCategoryQueue(center: center) { point in
            let count = step.withLock { value -> Int in
                value += 1
                return value
            }
            guard let queue = queueBox.withLock({ $0 }) else { return }
            // The 2nd point is the look for the next change after the first one was applied.
            if point == .beforeTakingNext, count == 2 {
                queue.enqueue(.register(category("before"))) { done.record("before") }
            }
            // The first end of a drain.
            if point == .afterEnding, !done.all.contains("after-enqueued") {
                done.record("after-enqueued")
                queue.enqueue(.register(category("after"))) { done.record("after") }
            }
        }
        queueBox.withLock { $0 = queue }

        queue.enqueue(.register(category("first"))) { done.record("first") }
        try await waitUntil { done.all.contains("after") }

        #expect(done.all.filter { $0 != "after-enqueued" } == ["first", "before", "after"])
        #expect(center.identifiers == ["first", "before", "after"])
        // "before" was taken by the first drain; "after" started the second.
        #expect(queue.drainStartCount == 2)
    }

    /// One change at a time from another thread, each enqueued while the drain goes on to look at
    /// the queue for the next one: the hook lets a spinning thread go once the previous change
    /// completed, then lets the drain go on after a pause of 0 to 3 µs, so that the enqueue meets
    /// every point of the look. None is left (the look at an empty queue and lowering the flag are
    /// one lock region). A change left in the queue would never complete, because the next one is
    /// enqueued only after it.
    @Test func aChangeRacingTheEndOfADrainIsNeverLeft() async throws {
        let center = FakeCategoryCenter()
        let released = Atomic<Int>(0)
        let issued = Atomic<Int>(0)
        let completed = Atomic<Int>(0)
        let stalled = Atomic<Int>(-1)
        let finished = Atomic<Bool>(false)
        let rounds = 5_000
        let queue = NotificationCategoryQueue(center: center) { point in
            // Lets the thread go once per change: only when every change it enqueued has completed.
            guard point == .beforeTakingNext,
                  completed.load(ordering: .sequentiallyConsistent) == issued.load(ordering: .sequentiallyConsistent) else { return }
            released.add(1, ordering: .sequentiallyConsistent)
            let pause = UInt64.random(in: 0...3_000)
            let start = DispatchTime.now().uptimeNanoseconds
            while DispatchTime.now().uptimeNanoseconds - start < pause {}
        }

        let worker = Thread {
            for index in 0..<rounds {
                let deadline = DispatchTime.now().uptimeNanoseconds + 2_000_000_000
                while released.load(ordering: .sequentiallyConsistent) <= index {
                    if DispatchTime.now().uptimeNanoseconds > deadline {
                        stalled.store(index, ordering: .sequentiallyConsistent)
                        finished.store(true, ordering: .sequentiallyConsistent)
                        return
                    }
                }
                issued.add(1, ordering: .sequentiallyConsistent)
                queue.enqueue(.register(category("r\(index % 4)"))) {
                    completed.add(1, ordering: .sequentiallyConsistent)
                }
            }
            finished.store(true, ordering: .sequentiallyConsistent)
        }
        worker.start()
        // The seed starts the first drain; the drain then lets the thread go once per change.
        queue.enqueue(.register(category("seed"))) {}
        try await waitUntil(120) { finished.load(ordering: .sequentiallyConsistent) }
        try await waitUntil { completed.load(ordering: .sequentiallyConsistent) == issued.load(ordering: .sequentiallyConsistent) }

        #expect(stalled.load(ordering: .sequentiallyConsistent) == -1, "a change was left in the queue")
        #expect(completed.load(ordering: .sequentiallyConsistent) == rounds)
    }

    /// Registering a category again replaces the one with the same identifier.
    @Test func registeringAgainReplacesTheCategory() async {
        let center = FakeCategoryCenter()
        let queue = NotificationCategoryQueue(center: center)
        for actions in [["one"], ["one", "two"]] {
            await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
                queue.enqueue(.register(category("a", actions: actions))) { continuation.resume() }
            }
        }
        let stored = center.categories(withIdentifier: "a")
        #expect(stored.count == 1)
        #expect(stored.first?.actions.map(\.identifier) == ["one", "two"])
    }

    /// The read-back confirms a registration by the written category, not by its identifier only:
    /// an unapplied replacement (the old category still stored) is not read back.
    @Test func theReadBackComparesTheWrittenCategory() {
        let written = NotificationCategoryQueue.makeUNCategory(from: NotificationCategory(
            identifier: "a", actions: [NotificationAction(identifier: "one", title: "One"), NotificationAction(identifier: "two", title: "Two")],
            textInputActions: [TextInputNotificationAction(identifier: "reply", title: "Reply", buttonTitle: "Send", textInputPlaceholder: "Message")], options: [.customDismissAction]))
        func stored(_ actions: [String], options: UNNotificationCategoryOptions = [.customDismissAction], identifier: String = "a") -> UNNotificationCategory {
            UNNotificationCategory(identifier: identifier, actions: actions.map { UNNotificationAction(identifier: $0, title: $0) },
                                   intentIdentifiers: [], options: options)
        }

        // The category written, also as a copy made again (what a read gives back).
        #expect(NotificationCategoryQueue.isReadBack(written, identifier: "a", in: [written]))
        #expect(NotificationCategoryQueue.isReadBack(written, identifier: "a", in: [stored(["one", "two", "reply"]), stored([], identifier: "b")]))
        // The old category of the identifier, or another order or other options: not applied.
        #expect(!NotificationCategoryQueue.isReadBack(written, identifier: "a", in: [stored(["one"])]))
        #expect(!NotificationCategoryQueue.isReadBack(written, identifier: "a", in: [stored(["two", "one", "reply"])]))
        #expect(!NotificationCategoryQueue.isReadBack(written, identifier: "a", in: [stored(["one", "two", "reply"], options: [])]))
        #expect(!NotificationCategoryQueue.isReadBack(written, identifier: "a", in: [stored(["one", "two", "reply"], identifier: "b")]))
        #expect(!NotificationCategoryQueue.isReadBack(written, identifier: "a", in: []))
        // A removal: applied when no category has the identifier.
        #expect(NotificationCategoryQueue.isReadBack(nil, identifier: "a", in: [stored([], identifier: "b")]))
        #expect(!NotificationCategoryQueue.isReadBack(nil, identifier: "a", in: [stored(["one"])]))
    }

    // MARK: - The repository

    /// Every repository the public `init()` makes uses the one queue of the process (SR-18).
    @Test func everyRepositoryUsesTheQueueOfTheProcess() {
        let first = NotificationRepositoryImpl()
        let second = NotificationRepositoryImpl()
        #expect(first.categoryQueue === NotificationCategoryQueue.shared)
        #expect(second.categoryQueue === first.categoryQueue)
    }

    /// The repository's `async` operations and `enqueueCategoryChange` go through its queue, in
    /// order.
    @Test func theRepositoryQueuesItsChanges() async throws {
        let center = FakeCategoryCenter()
        let repository = NotificationRepositoryImpl(requestCenter: FakeRequestCenter(),
                                                    categoryQueue: NotificationCategoryQueue(center: center))
        let done = Recorder()

        await repository.registerCategory(category("a"))
        repository.enqueueCategoryChange(.register(category("b"))) { done.record("b") }
        repository.enqueueCategoryChange(.remove(identifier: "a")) { done.record("-a") }
        await repository.removeCategory(identifier: "b")

        #expect(done.all == ["b", "-a"])
        #expect(center.writes == ["+a", "+b", "-a", "-b"])
    }

    /// A repository of your own gets the default `enqueueCategoryChange`: it calls the `async`
    /// requirements, then the completion (the order is not kept; design S-P28).
    @Test func theDefaultEnqueueCallsTheAsyncRequirements() async throws {
        let repository = MockNotificationRepository()
        let done = Recorder()

        repository.enqueueCategoryChange(.register(category("a"))) { done.record("registered") }
        repository.enqueueCategoryChange(.remove(identifier: "a")) { done.record("removed") }
        try await waitUntil { done.all.count == 2 }

        #expect(repository.registerCategoryCallCount == 1)
        #expect(repository.removeCategoryCallCount == 1)
        #expect(Set(done.all) == ["registered", "removed"])
    }

    // MARK: - The manager

    private func makeManager(_ center: FakeCategoryCenter) -> IosNotificationManager {
        let repository = NotificationRepositoryImpl(requestCenter: FakeRequestCenter(),
                                                    categoryQueue: NotificationCategoryQueue(center: center))
        return IosNotificationManager(repository: repository,
                                      delegateStatus: NotificationDelegateStatus(isInstalled: { true }, launchResponse: { nil }))
    }

    /// The callback forms: queued inside the call (in the order of the calls), the completion on
    /// the main thread, once, after the change, never inside the call.
    @Test func theCallbackFormsCompleteOnMainAfterTheChange() async throws {
        let center = FakeCategoryCenter()
        let manager = makeManager(center)
        let done = Recorder()

        let calledInside = await MainActor.run { () -> Bool in
            manager.registerCategory(category("a")) {
                center.note("completion a")
                done.record("a")
            }
            manager.removeCategory(identifier: "a") {
                center.note("completion -a")
                done.record("-a")
            }
            manager.registerCategory(category("b"))
            return !done.all.isEmpty
        }
        try await waitUntil { done.all.count == 2 && center.writes.count == 3 }

        #expect(!calledInside)
        #expect(done.all == ["a", "-a"])
        #expect(done.onMain == [true, true])
        #expect(center.writes == ["+a", "-a", "+b"])
        let log = center.log
        let completionA = try #require(log.firstIndex(of: "completion a"))
        let writeA = try #require(log.firstIndex(of: "write +a"))
        #expect(writeA < completionA)
        try await Task.sleep(nanoseconds: 100_000_000)
        #expect(done.all.count == 2)
    }

    /// The `async` forms return after the change, in the order they are awaited.
    @Test func theAsyncFormsReturnAfterTheChange() async {
        let center = FakeCategoryCenter()
        let manager = makeManager(center)

        await manager.registerCategory(category("a"))
        #expect(center.writes == ["+a"])
        await manager.removeCategory(identifier: "a")
        #expect(center.writes == ["+a", "-a"])
    }

    /// The C ABI form (design 8.9, SR3-1): the callback forms called one after another inside a
    /// main-queue block take effect in that order.
    @Test func callsInsideAMainQueueBlockKeepTheirOrder() async throws {
        let center = FakeCategoryCenter()
        let manager = makeManager(center)
        let done = Recorder()

        DispatchQueue.main.async {
            for index in 0..<8 {
                manager.registerCategory(category("c\(index)")) { done.record("+c\(index)") }
            }
            for index in 0..<8 {
                manager.removeCategory(identifier: "c\(index)") { done.record("-c\(index)") }
            }
        }
        try await waitUntil { done.all.count == 16 }

        let expected = (0..<8).map { "+c\($0)" } + (0..<8).map { "-c\($0)" }
        #expect(center.writes == expected)
        #expect(done.all == expected)
    }

    /// 8 main-actor tasks started in a row, each registering with the `async` form, then 8 that
    /// remove: applied in the order the tasks were started, 300 times (SR3-1: the `async` forms
    /// are `nonisolated(nonsending)` and queue before their first suspension).
    @Test func mainActorTasksStartedInARowKeepTheirOrder() async throws {
        let expected = (0..<8).map { "+c\($0)" } + (0..<8).map { "-c\($0)" }
        var mismatches = 0
        for _ in 0..<300 {
            let center = FakeCategoryCenter()
            let manager = makeManager(center)
            let tasks = await MainActor.run { () -> [Task<Void, Never>] in
                var tasks: [Task<Void, Never>] = []
                for index in 0..<8 {
                    tasks.append(Task { @MainActor in await manager.registerCategory(category("c\(index)")) })
                }
                for index in 0..<8 {
                    tasks.append(Task { @MainActor in await manager.removeCategory(identifier: "c\(index)") })
                }
                return tasks
            }
            for task in tasks { await task.value }
            if center.writes != expected { mismatches += 1 }
        }
        #expect(mismatches == 0)
    }
}
