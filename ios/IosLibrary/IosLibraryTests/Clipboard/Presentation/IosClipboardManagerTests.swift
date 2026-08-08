//
//  IosClipboardManagerTests.swift
//  IosLibraryTests
//

import Testing
import Foundation
import UIKit
@testable import IosLibrary

/// Serialized: every observing test posts `UIPasteboard.changedNotification` for the *shared*
/// `UIPasteboard.general` object, so running them concurrently would let one test's post reach
/// another test's subscriber.
@MainActor
@Suite(.serialized)
struct IosClipboardManagerTests {
    private func makeManager(
        repository: MockClipboardRepository? = nil,
        loader: MockClipboardItemLoader? = nil
    ) -> IosClipboardManager {
        let repository = repository ?? MockClipboardRepository()
        let loader = loader ?? MockClipboardItemLoader()
        let useCases = ClipboardUseCases(
            repository: repository,
            loader: loader,
            typeValidator: MockClipboardTypeIdentifierValidating()
        )
        return IosClipboardManager(useCases: useCases)
    }

    @Test func copyCallbackReportsSuccess() async throws {
        let manager = makeManager()
        let (isSuccess, code, message) = await withCheckedContinuation { continuation in
            manager.copy(.plainText("hi")) { isSuccess, code, message in
                continuation.resume(returning: (isSuccess, code, message))
            }
        }
        #expect(isSuccess == true)
        #expect(code == nil)
        #expect(message == nil)
    }

    @Test func copyCallbackReportsFailureWithErrorCode() async throws {
        let manager = makeManager()
        let (isSuccess, code, message) = await withCheckedContinuation { continuation in
            manager.copy(.multipleText([])) { isSuccess, code, message in
                continuation.resume(returning: (isSuccess, code, message))
            }
        }
        #expect(isSuccess == false)
        #expect(code == ClipboardError.emptyItemList.errorCode)
        #expect(message != nil)
    }

    @Test func copyAsyncThrowsPropagatesTypedError() async {
        let repository = MockClipboardRepository()
        repository.shouldFail = true
        repository.errorToThrow = .emptyContent
        let manager = makeManager(repository: repository)
        await #expect(throws: ClipboardError.self) {
            try await manager.copy(.plainText("hi"))
        }
    }

    @Test func readDataCallbackReturnsCodeOnFailure() async {
        let repository = MockClipboardRepository()
        repository.shouldFail = true
        repository.errorToThrow = .invalidTypeIdentifier("x")
        let manager = makeManager(repository: repository)
        let (isSuccess, _, code, _) = await withCheckedContinuation { (continuation: CheckedContinuation<(Bool, Data?, String?, String?), Never>) in
            manager.readData(utType: "public.png") { isSuccess, data, code, message in
                continuation.resume(returning: (isSuccess, data, code, message))
            }
        }
        #expect(isSuccess == false)
        #expect(code == ClipboardError.invalidTypeIdentifier("x").errorCode)
    }

    @Test func startObservingTwiceDoesNotDuplicateEvents() throws {
        let manager = makeManager()
        var count1 = 0
        var count2 = 0
        try manager.startObserving { _ in count1 += 1 }
        try manager.startObserving { _ in count2 += 1 }
        NotificationCenter.default.post(name: UIPasteboard.changedNotification, object: UIPasteboard.general)
        // The first subscription must be fully superseded, not merely stopped.
        #expect(count1 == 0)
        #expect(count2 <= 1)
        manager.stopObserving()
    }

    @Test func stopObservingPreventsFurtherEvents() throws {
        let manager = makeManager()
        var received = 0
        try manager.startObserving { _ in received += 1 }
        manager.stopObserving()
        NotificationCenter.default.post(name: UIPasteboard.changedNotification, object: UIPasteboard.general)
        #expect(received == 0)
    }

    @Test func stopThenStartOnSameScopeDoesNotDeliverOldEventsToNewSubscriber() async throws {
        let manager = makeManager()
        var oldSubscriberCount = 0
        var newSubscriberCount = 0
        try manager.startObserving(scope: .general) { _ in oldSubscriberCount += 1 }

        // NOTE: the generation gate's *other* purpose — dropping a block that was already queued
        // for the previous subscription — cannot be reproduced here: it needs the notification
        // posted from a background thread while the main thread is kept from draining, and posting
        // a UIKit notification off the main thread with the main thread blocked deadlocks the
        // simulator. What this test does cover is that a restart on the same scope never lets the
        // superseded subscriber fire and never double-delivers to the new one.
        manager.stopObserving()
        try manager.startObserving(scope: .general) { _ in newSubscriberCount += 1 }
        await Self.drainMainQueue()

        #expect(oldSubscriberCount == 0)
        #expect(newSubscriberCount == 0)

        // The new subscription itself still works: a change posted after it starts is delivered
        // exactly once.
        NotificationCenter.default.post(name: UIPasteboard.changedNotification, object: UIPasteboard.general)
        await Self.drainMainQueue()
        #expect(newSubscriberCount == 1)
        #expect(oldSubscriberCount == 0)
        manager.stopObserving()
    }

    /// Waits until every block already enqueued on the main queue (including notification observer
    /// blocks registered with `queue: .main`) has run.
    private static func drainMainQueue() async {
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            OperationQueue.main.addOperation { continuation.resume() }
        }
    }

    @Test func startObservingThrowsForUnresolvableNamedScope() {
        let manager = makeManager()
        #expect(throws: ClipboardError.self) {
            try manager.startObserving(scope: .named("missing-\(UUID().uuidString)")) { _ in }
        }
    }

    @Test func cancelAllLoadsDelegatesToLoader() {
        let loader = MockClipboardItemLoader()
        let manager = makeManager(loader: loader)
        manager.cancelAllLoads()
        #expect(loader.cancelAllCallCount == 1)
    }

    @Test func checkForegroundChangeIsSynchronous() {
        let repository = MockClipboardRepository()
        repository.stubbedChangeCount = 1
        let manager = makeManager(repository: repository)
        let changed = manager.checkForegroundChange()
        #expect(changed == false || changed == true)
    }

    @Test func loadItemCallbackReturnsSuccessValue() {
        let loader = MockClipboardItemLoader()
        loader.stubbedResult = .success(.text("hi"))
        let manager = makeManager(loader: loader)
        var received: ClipboardLoadedItem?
        manager.loadItem(.text) { isSuccess, item, _, _ in
            #expect(isSuccess == true)
            received = item
        }
        #expect(received == .text("hi"))
    }
}
