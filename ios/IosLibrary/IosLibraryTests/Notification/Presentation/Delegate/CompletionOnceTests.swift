//
//  CompletionOnceTests.swift
//  IosLibraryTests
//

import Foundation
import Synchronization
import Testing
@testable import IosLibrary

/// UT-21: the system completion passes through at most once, from any thread (part 1, 5.12.4).
struct CompletionOnceTests {

    /// Lets a test see whether a closure (and what it captured) is still alive.
    private final class Sentinel: Sendable {}

    @Test func theFirstCallPassesThrough() {
        let recorder = CompletionRecorder<Int>()
        let once = CompletionOnce(method: "test", recorder.handler)

        once.call(7)

        #expect(recorder.all.map { $0.value } == [7])
        #expect(once.callCount == 1)
    }

    @Test func laterCallsAreDropped() {
        let recorder = CompletionRecorder<Int>()
        let once = CompletionOnce(method: "test", recorder.handler)

        once.call(1)
        once.call(2)
        once.call(3)

        #expect(recorder.all.map { $0.value } == [1])
        #expect(once.callCount == 3)
    }

    @Test func aCallFromABackgroundQueueDoesNotTrapAndRunsThere() async {
        let recorder = CompletionRecorder<Int>()
        let once = CompletionOnce(method: "test", recorder.handler)

        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            DispatchQueue.global().async {
                once.call(1)
                continuation.resume()
            }
        }

        #expect(recorder.count == 1)
        #expect(recorder.all.first?.isMainThread == false)
    }

    /// 8 threads × 25 calls race; exactly one passes (also run with the Thread Sanitizer).
    @Test func racingCallsPassOnce() async {
        for _ in 0..<20 {
            let recorder = CompletionRecorder<Int>()
            let once = CompletionOnce(method: "test", recorder.handler)
            await withTaskGroup(of: Void.self) { group in
                for thread in 0..<8 {
                    group.addTask {
                        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
                            Thread {
                                for index in 0..<25 { once.call(thread * 100 + index) }
                                continuation.resume()
                            }.start()
                        }
                    }
                }
            }
            #expect(recorder.count == 1)
            #expect(once.callCount == 200)
        }
    }

    /// The completion is released once it has been called, even while the wrapper is kept (a
    /// previous delegate that holds the closure after calling it).
    @Test func theCompletionIsReleasedAfterTheCall() {
        weak var weakSentinel: Sentinel?
        let once: CompletionOnce<Int>
        do {
            let sentinel = Sentinel()
            weakSentinel = sentinel
            once = CompletionOnce(method: "test") { _ in _ = sentinel }
        }
        #expect(weakSentinel != nil)

        once.call(1)

        #expect(weakSentinel == nil)
    }

    /// Freed without a call (the previous delegate dropped the closure): nothing is called, and
    /// the completion goes with it.
    @Test func aWrapperFreedWithoutACallCallsNothing() {
        let recorder = CompletionRecorder<Int>()
        weak var weakSentinel: Sentinel?
        weak var weakOnce: CompletionOnce<Int>?
        do {
            let sentinel = Sentinel()
            weakSentinel = sentinel
            let handler = recorder.handler
            let once = CompletionOnce(method: "test") { value in
                _ = sentinel
                handler(value)
            }
            weakOnce = once
        }

        #expect(weakOnce == nil)
        #expect(weakSentinel == nil)
        #expect(recorder.count == 0)
    }
}
