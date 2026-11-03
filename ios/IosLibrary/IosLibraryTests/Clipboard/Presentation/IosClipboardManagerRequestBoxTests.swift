//
//  IosClipboardManagerRequestBoxTests.swift
//  IosLibraryTests
//
//  UT-30 (Swift API design 13.1, stage 1b C4): `loadItem(_:scope:requestBox:completion:)` and
//  `cancelLoad(_:)`. Also run with the Thread Sanitizer.
//

import Foundation
import Synchronization
import Testing
import UIKit
@testable import IosLibrary

/// A loader that keeps every load pending until the test delivers it, and that reports
/// `.cancelled` to a load whose token is cancelled, as `ClipboardItemLoaderImpl` does.
@MainActor
final class PendingClipboardLoader: ClipboardItemLoader {
    @MainActor
    final class Token: ClipboardLoadToken {
        private weak var loader: PendingClipboardLoader?
        let id: Int

        init(loader: PendingClipboardLoader, id: Int) {
            self.loader = loader
            self.id = id
        }

        func cancel() { loader?.cancel(id: id) }
    }

    /// When set, `load` reports this result inside the call (a loader may).
    var resultInsideTheCall: Result<ClipboardLoadedItem, ClipboardError>?
    private(set) var loadCallCount = 0
    private(set) var lastRequest: ClipboardLoadRequest?
    private(set) var lastScope: PasteboardScope?
    /// `Thread.isMainThread` of every token `cancel()`, in call order.
    private(set) var tokenCancels: [Bool] = []
    private(set) var cancelAllCallCount = 0
    private var pending: [Int: (Result<ClipboardLoadedItem, ClipboardError>) -> Void] = [:]
    private var nextID = 0

    var pendingCount: Int { pending.count }
    var lastID: Int { nextID - 1 }

    func load(
        _ request: ClipboardLoadRequest,
        scope: PasteboardScope,
        completion: @escaping (Result<ClipboardLoadedItem, ClipboardError>) -> Void
    ) -> any ClipboardLoadToken {
        loadCallCount += 1
        lastRequest = request
        lastScope = scope
        let id = nextID
        nextID += 1
        if let resultInsideTheCall {
            completion(resultInsideTheCall)
        } else {
            pending[id] = completion
        }
        return Token(loader: self, id: id)
    }

    /// Delivers the result of load `id` (the last one by default), as the provider would.
    func deliver(_ result: Result<ClipboardLoadedItem, ClipboardError>, id: Int? = nil) {
        pending.removeValue(forKey: id ?? lastID)?(result)
    }

    /// Delivers a result that the loader produced although the load was already resolved: the
    /// test keeps the completion to call it again (a late result reaching the manager's closure).
    func completion(of id: Int) -> ((Result<ClipboardLoadedItem, ClipboardError>) -> Void)? {
        pending[id]
    }

    fileprivate func cancel(id: Int) {
        tokenCancels.append(Thread.isMainThread)
        pending.removeValue(forKey: id)?(.failure(.cancelled))
    }

    func cancelAll() {
        cancelAllCallCount += 1
        let all = pending
        pending.removeAll()
        for (_, completion) in all.sorted(by: { $0.key < $1.key }) {
            completion(.failure(.cancelled))
        }
    }
}

/// The completions one request reported, with the thread they arrived on.
@MainActor
final class LoadCompletions {
    struct Call: Equatable {
        let isSuccess: Bool
        let item: ClipboardLoadedItem?
        let errorCode: String?
        let hasMessage: Bool
        let isMainThread: Bool
    }

    private(set) var calls: [Call] = []

    var completion: (Bool, ClipboardLoadedItem?, String?, String?) -> Void {
        { [self] isSuccess, item, errorCode, message in
            calls.append(Call(isSuccess: isSuccess, item: item, errorCode: errorCode,
                              hasMessage: message != nil, isMainThread: Thread.isMainThread))
        }
    }

    static func cancelled() -> Call {
        Call(isSuccess: false, item: nil, errorCode: "CLIPBOARD_CANCELLED", hasMessage: true, isMainThread: true)
    }

    static func loaded(_ item: ClipboardLoadedItem) -> Call {
        Call(isSuccess: true, item: item, errorCode: nil, hasMessage: false, isMainThread: true)
    }
}

/// Closes a box from a background thread and waits for that thread synchronously, with a time
/// limit: the main thread is blocked meanwhile, so a `cancelLoad` that waited for the main thread
/// would not return (a synchronous helper, as blocking waits are not for `async` contexts).
private func cancelOnAnotherThreadWhileMainIsBlocked(_ manager: IosClipboardManager, _ box: RequestBox) -> Bool {
    let returned = DispatchSemaphore(value: 0)
    Thread.detachNewThread {
        manager.cancelLoad(box)
        returned.signal()
    }
    return returned.wait(timeout: .now() + 5) == .success
}

/// The same with the static form, which needs no manager.
private func cancelWithTheStaticFormOnAnotherThreadWhileMainIsBlocked(_ box: RequestBox) -> Bool {
    let returned = DispatchSemaphore(value: 0)
    Thread.detachNewThread {
        IosClipboardManager.cancelLoad(box)
        returned.signal()
    }
    return returned.wait(timeout: .now() + 5) == .success
}

/// Two flags for a race between the main thread and another thread.
private final class RaceBarrier: Sendable {
    let ready = Atomic<Bool>(false)
    let go = Atomic<Bool>(false)
}

@MainActor
@Suite(.serialized)
struct IosClipboardManagerRequestBoxTests {

    private func makeManager(loader: PendingClipboardLoader) -> IosClipboardManager {
        IosClipboardManager(useCases: ClipboardUseCases(
            repository: MockClipboardRepository(),
            loader: loader,
            typeValidator: MockClipboardTypeIdentifierValidating()
        ))
    }

    // MARK: - Cancelling

    @Test func aCancelledLoadReportsCancelledOnceAndStopsTheLoad() async {
        let loader = PendingClipboardLoader()
        let manager = makeManager(loader: loader)
        let box = RequestBox()
        let completions = LoadCompletions()

        manager.loadItem(.text, scope: .general, requestBox: box, completion: completions.completion)
        #expect(loader.loadCallCount == 1)
        manager.cancelLoad(box)
        // Closed in the call; reported and stopped on a later turn of the main thread.
        #expect(box.isClosed)
        #expect(completions.calls.isEmpty)
        #expect(loader.tokenCancels.isEmpty)
        await drainMainQueue()

        #expect(completions.calls == [LoadCompletions.cancelled()])
        #expect(loader.tokenCancels == [true])
        #expect(loader.pendingCount == 0)
    }

    /// C ABI part 2, P2-12: the static form needs no manager, so another thread can call it before
    /// anything has read `shared`, and it does not wait for the main thread.
    @Test func theStaticFormClosesTheBoxOnItsOwnThreadWhileMainIsBlocked() async {
        let box = RequestBox()
        #expect(cancelWithTheStaticFormOnAnotherThreadWhileMainIsBlocked(box))
        #expect(box.isClosed)
    }

    @Test func aLoadCancelledWithTheStaticFormReportsCancelledOnce() async {
        let loader = PendingClipboardLoader()
        let manager = makeManager(loader: loader)
        let box = RequestBox()
        let completions = LoadCompletions()

        manager.loadItem(.text, scope: .general, requestBox: box, completion: completions.completion)
        IosClipboardManager.cancelLoad(box)
        await drainMainQueue()

        #expect(completions.calls == [LoadCompletions.cancelled()])
        #expect(loader.tokenCancels == [true])
    }

    @Test func aResultThatArrivesAfterTheCancellationIsDropped() async {
        let loader = PendingClipboardLoader()
        let manager = makeManager(loader: loader)
        let box = RequestBox()
        let completions = LoadCompletions()

        manager.loadItem(.text, requestBox: box, completion: completions.completion)
        // The provider's result comes after the box was cancelled but before the main thread
        // stopped the load (cancelLoad from another thread).
        let late = loader.completion(of: loader.lastID)
        manager.cancelLoad(box)
        late?(.success(.text("late")))
        await drainMainQueue(times: 2)

        #expect(completions.calls == [LoadCompletions.cancelled()])
    }

    @Test func aBoxCancelledBeforeTheCallReadsNothing() async {
        let loader = PendingClipboardLoader()
        let manager = makeManager(loader: loader)
        let box = RequestBox()
        let completions = LoadCompletions()

        manager.cancelLoad(box)
        manager.loadItem(.text, requestBox: box, completion: completions.completion)
        #expect(loader.loadCallCount == 0)
        #expect(completions.calls.isEmpty)
        await drainMainQueue()

        #expect(completions.calls == [LoadCompletions.cancelled()])
        #expect(loader.loadCallCount == 0)
    }

    @Test func aCancellationAfterTheResultChangesNothing() async {
        let loader = PendingClipboardLoader()
        let manager = makeManager(loader: loader)
        let box = RequestBox()
        let completions = LoadCompletions()

        manager.loadItem(.url, requestBox: box, completion: completions.completion)
        loader.deliver(.success(.url("https://example.com")))
        manager.cancelLoad(box)
        manager.cancelLoad(box)
        await drainMainQueue(times: 2)

        #expect(completions.calls == [LoadCompletions.loaded(.url("https://example.com"))])
        #expect(loader.tokenCancels.isEmpty)
    }

    @Test func cancellingTwiceReportsOnce() async {
        let loader = PendingClipboardLoader()
        let manager = makeManager(loader: loader)
        let box = RequestBox()
        let completions = LoadCompletions()

        manager.loadItem(.text, requestBox: box, completion: completions.completion)
        manager.cancelLoad(box)
        manager.cancelLoad(box)
        await drainMainQueue(times: 2)

        #expect(completions.calls == [LoadCompletions.cancelled()])
        #expect(loader.tokenCancels == [true])
    }

    /// The close handler only queues on main (it does not inherit the main actor, SR-3), and
    /// `cancelLoad` never waits for the main thread.
    @Test func aCancellationFromAnotherThreadDoesNotWaitAndReportsOnMain() async {
        let loader = PendingClipboardLoader()
        let manager = makeManager(loader: loader)
        let box = RequestBox()
        let completions = LoadCompletions()
        manager.loadItem(.image, requestBox: box, completion: completions.completion)

        #expect(cancelOnAnotherThreadWhileMainIsBlocked(manager, box), "cancelLoad waited for the main thread")
        #expect(box.isClosed)
        #expect(completions.calls.isEmpty)
        await drainMainQueue()

        #expect(completions.calls == [LoadCompletions.cancelled()])
        #expect(loader.tokenCancels == [true])
    }

    /// A cancellation from another thread races the load's result on the main thread: exactly
    /// one of them is reported, once, and only a reported cancellation stops the load.
    @Test func aCancellationRacingTheResultReportsExactlyOnce() async {
        let rounds = 200
        let loader = PendingClipboardLoader()
        let manager = makeManager(loader: loader)
        var requests: [(box: RequestBox, completions: LoadCompletions)] = []

        for round in 0..<rounds {
            let box = RequestBox()
            let completions = LoadCompletions()
            manager.loadItem(.text, requestBox: box, completion: completions.completion)
            // Both sides wait for each other, then close the box at the same moment.
            let barrier = RaceBarrier()
            Thread.detachNewThread {
                barrier.ready.store(true, ordering: .releasing)
                while !barrier.go.load(ordering: .acquiring) {}
                manager.cancelLoad(box)
            }
            while !barrier.ready.load(ordering: .acquiring) {}
            barrier.go.store(true, ordering: .releasing)
            loader.deliver(.success(.text("r\(round)")))
            requests.append((box, completions))
        }
        let deadline = Date().addingTimeInterval(10)
        while requests.contains(where: { $0.completions.calls.isEmpty }), Date() < deadline {
            await drainMainQueue()
        }
        await drainMainQueue(times: 2)

        let wrong = requests.enumerated().filter { $0.element.completions.calls.count != 1 }.map(\.offset)
        #expect(wrong.isEmpty, "rounds without exactly one completion: \(wrong)")
        let cancelled = requests.filter { $0.completions.calls.first?.errorCode == "CLIPBOARD_CANCELLED" }.count
        let loaded = requests.enumerated().filter { round, request in
            request.completions.calls.first == LoadCompletions.loaded(.text("r\(round)"))
        }.count
        #expect(cancelled + loaded == rounds)
        #expect(requests.allSatisfy { $0.box.isClosed })
        #expect(requests.allSatisfy { $0.completions.calls.allSatisfy(\.isMainThread) })
        // The result was delivered in the same turn as each load, so no load was pending when a
        // cancellation was reported: no token cancel had anything to stop.
        #expect(loader.pendingCount == 0)
        #expect(loader.tokenCancels.count == cancelled)
    }

    // MARK: - The box

    @Test func theCompletionNeverComesInsideTheCall() async {
        let loader = PendingClipboardLoader()
        loader.resultInsideTheCall = .success(.text("now"))
        let manager = makeManager(loader: loader)
        let completions = LoadCompletions()

        manager.loadItem(.text, requestBox: RequestBox(), completion: completions.completion)
        #expect(completions.calls.isEmpty)
        await drainMainQueue()

        #expect(completions.calls == [LoadCompletions.loaded(.text("now"))])
    }

    @Test func aBoxThatAnotherRequestUsesFailsOnlyTheSecondRequest() async {
        let loader = PendingClipboardLoader()
        let manager = makeManager(loader: loader)
        let box = RequestBox()
        let first = LoadCompletions()
        let second = LoadCompletions()

        manager.loadItem(.text, requestBox: box, completion: first.completion)
        manager.loadItem(.url, requestBox: box, completion: second.completion)
        #expect(loader.loadCallCount == 1)
        #expect(second.calls.isEmpty)
        await drainMainQueue()

        #expect(second.calls == [LoadCompletions.Call(isSuccess: false, item: nil, errorCode: "CLIPBOARD_INVALID_REQUEST",
                                                      hasMessage: true, isMainThread: true)])
        #expect(!box.isClosed)
        #expect(first.calls.isEmpty)

        loader.deliver(.success(.text("first")))
        await drainMainQueue()
        #expect(first.calls == [LoadCompletions.loaded(.text("first"))])
        #expect(second.calls.count == 1)
    }

    @Test func aBoxWhoseRequestHasEndedIsNotUsedAgain() async {
        let loader = PendingClipboardLoader()
        let manager = makeManager(loader: loader)
        let box = RequestBox()
        let first = LoadCompletions()
        let again = LoadCompletions()

        manager.loadItem(.text, requestBox: box, completion: first.completion)
        loader.deliver(.success(.text("first")))
        await drainMainQueue()
        manager.loadItem(.text, requestBox: box, completion: again.completion)
        await drainMainQueue()

        #expect(loader.loadCallCount == 1)
        #expect(first.calls == [LoadCompletions.loaded(.text("first"))])
        #expect(again.calls.map(\.errorCode) == ["CLIPBOARD_INVALID_REQUEST"])
    }

    @Test func aBoxOfADialogRequestIsRefused() async {
        let loader = PendingClipboardLoader()
        let manager = makeManager(loader: loader)
        let box = RequestBox()
        #expect(box.attach { _ in })
        let completions = LoadCompletions()

        manager.loadItem(.text, requestBox: box, completion: completions.completion)
        await drainMainQueue()

        #expect(loader.loadCallCount == 0)
        #expect(completions.calls.map(\.errorCode) == ["CLIPBOARD_INVALID_REQUEST"])
    }

    @Test func aFailedLoadReportsItsErrorCode() async {
        let loader = PendingClipboardLoader()
        let manager = makeManager(loader: loader)
        let box = RequestBox()
        let completions = LoadCompletions()

        manager.loadItem(.file(utType: "public.data"), scope: .named("ut30"), requestBox: box, completion: completions.completion)
        #expect(loader.lastRequest == .file(utType: "public.data"))
        #expect(loader.lastScope == .named("ut30"))
        loader.deliver(.failure(.noMatchingItem))
        await drainMainQueue()

        #expect(completions.calls == [LoadCompletions.Call(isSuccess: false, item: nil, errorCode: "CLIPBOARD_NO_MATCHING_ITEM",
                                                           hasMessage: true, isMainThread: true)])
        #expect(box.isClosed)
    }

    // MARK: - Files

    @Test func aFileThatArrivesAfterTheCancellationIsDeleted() async throws {
        let loader = PendingClipboardLoader()
        let manager = makeManager(loader: loader)
        let file = try Self.makeStoreFile()
        defer { try? FileManager.default.removeItem(at: file.deletingLastPathComponent().deletingLastPathComponent()) }
        let box = RequestBox()
        let completions = LoadCompletions()

        manager.loadItem(.file(utType: "public.data"), requestBox: box, completion: completions.completion)
        let late = loader.completion(of: loader.lastID)
        manager.cancelLoad(box)
        late?(.success(.file(file)))
        await drainMainQueue(times: 2)

        #expect(completions.calls == [LoadCompletions.cancelled()])
        #expect(!FileManager.default.fileExists(atPath: file.deletingLastPathComponent().path))
        #expect(FileManager.default.fileExists(atPath: file.deletingLastPathComponent().deletingLastPathComponent().path))
    }

    @Test func aDeliveredFileIsLeftToTheCaller() async throws {
        let loader = PendingClipboardLoader()
        let manager = makeManager(loader: loader)
        let file = try Self.makeStoreFile()
        defer { try? FileManager.default.removeItem(at: file.deletingLastPathComponent().deletingLastPathComponent()) }
        let completions = LoadCompletions()

        manager.loadItem(.file(utType: "public.data"), requestBox: RequestBox(), completion: completions.completion)
        loader.deliver(.success(.file(file)))
        await drainMainQueue()

        #expect(completions.calls == [LoadCompletions.loaded(.file(file))])
        #expect(FileManager.default.fileExists(atPath: file.path))
    }

    @Test func discardingLeavesAFileOutsideTheStoreAlone() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("ut30-\(UUID().uuidString)/request", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory.deletingLastPathComponent()) }
        let file = directory.appendingPathComponent("file.bin")
        try Data([1]).write(to: file)

        #expect(!ClipboardTemporaryFileStore.discardUndelivered(file))
        #expect(FileManager.default.fileExists(atPath: file.path))
        // Too shallow for the store's layout (`<root>/<session>/<request>/<file>`): the session
        // directory would be removed.
        let shallow = try Self.makeStoreFile().deletingLastPathComponent()
        defer { try? FileManager.default.removeItem(at: shallow.deletingLastPathComponent()) }
        #expect(!ClipboardTemporaryFileStore.discardUndelivered(shallow))
        #expect(FileManager.default.fileExists(atPath: shallow.path))
    }

    /// A file at `<temporary>/IosLibraryClipboard/<session>/<request>/<file>`, as the store
    /// creates it.
    private static func makeStoreFile() throws -> URL {
        let request = FileManager.default.temporaryDirectory
            .appendingPathComponent("IosLibraryClipboard", isDirectory: true)
            .appendingPathComponent("ut30-\(UUID().uuidString)", isDirectory: true)
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: request, withIntermediateDirectories: true)
        let file = request.appendingPathComponent("\(UUID().uuidString).bin")
        try Data([0x41, 0x42]).write(to: file)
        return file
    }

    // MARK: - With the other ways of cancelling

    @Test func cancelAllLoadsCancelsABoxedLoadToo() async {
        let loader = PendingClipboardLoader()
        let manager = makeManager(loader: loader)
        let box = RequestBox()
        let boxed = LoadCompletions()
        let legacy = LoadCompletions()

        manager.loadItem(.text, requestBox: box, completion: boxed.completion)
        manager.loadItem(.text, completion: legacy.completion)
        manager.cancelAllLoads()
        // The token-returning form reports inside the loader's call, as before.
        #expect(legacy.calls == [LoadCompletions.cancelled()])
        await drainMainQueue()

        #expect(boxed.calls == [LoadCompletions.cancelled()])
        #expect(box.isClosed)
        manager.cancelLoad(box)
        await drainMainQueue()
        #expect(boxed.calls.count == 1)
    }

    @Test func releasingTheManagerDuringABoxedLoadReportsCancelledOnce() async {
        let loader = PendingClipboardLoader()
        let box = RequestBox()
        let completions = LoadCompletions()
        weak var weakManager: IosClipboardManager?
        do {
            let manager = makeManager(loader: loader)
            weakManager = manager
            manager.loadItem(.text, requestBox: box, completion: completions.completion)
        }
        #expect(weakManager == nil)
        #expect(loader.cancelAllCallCount == 1)
        await drainMainQueue()

        #expect(completions.calls == [LoadCompletions.cancelled()])
        #expect(box.isClosed)
    }

    @Test func cancelLoadDoesNotTouchTheLoadsOfTheOtherForms() async throws {
        let loader = PendingClipboardLoader()
        let manager = makeManager(loader: loader)
        let legacy = LoadCompletions()
        let box = RequestBox()
        let boxed = LoadCompletions()

        manager.loadItem(.text, completion: legacy.completion)
        let legacyID = loader.lastID
        manager.loadItem(.text, requestBox: box, completion: boxed.completion)
        manager.cancelLoad(box)
        await drainMainQueue()

        #expect(boxed.calls == [LoadCompletions.cancelled()])
        #expect(legacy.calls.isEmpty)
        loader.deliver(.success(.text("legacy")), id: legacyID)
        #expect(legacy.calls == [LoadCompletions.loaded(.text("legacy"))])
    }

    /// The token-returning form is unchanged: it reports inside the loader's completion, and its
    /// token cancels it on the main actor.
    @Test func theTokenFormIsUnchanged() {
        let loader = PendingClipboardLoader()
        let manager = makeManager(loader: loader)
        let completions = LoadCompletions()

        let token = manager.loadItem(.text, completion: completions.completion)
        #expect(completions.calls.isEmpty)
        token.cancel()

        #expect(completions.calls == [LoadCompletions.cancelled()])
        #expect(loader.tokenCancels == [true])
    }

    @Test func theAsyncFormIsUnchanged() async throws {
        let loader = PendingClipboardLoader()
        let manager = makeManager(loader: loader)

        async let item = manager.loadItem(.text)
        #expect(await waitUntil { loader.loadCallCount == 1 })
        loader.deliver(.success(.text("async")))
        #expect(try await item == .text("async"))

        let task = Task { try await manager.loadItem(.url) }
        #expect(await waitUntil { loader.loadCallCount == 2 })
        task.cancel()
        await #expect(throws: ClipboardError.cancelled) { try await task.value }
    }

    // MARK: - Through the real loader

    /// The real loader and a unique pasteboard (never `.general`): a load cancelled in the same
    /// turn reports `CLIPBOARD_CANCELLED`; one that is not reports the text.
    @Test func throughTheRealLoaderACancelledLoadReportsCancelledAndAnotherLoadsTheText() async throws {
        let manager = IosClipboardManager(timeouts: .default, limits: .default)
        let scope = try await manager.createPasteboard(.unique)
        defer { manager.removePasteboard(scope, completion: nil) }
        try await manager.copy(.plainText("ut30-text"), scope: scope)

        let cancelled = LoadCompletions()
        let box = RequestBox()
        manager.loadItem(.text, scope: scope, requestBox: box, completion: cancelled.completion)
        manager.cancelLoad(box)

        let loaded = LoadCompletions()
        manager.loadItem(.text, scope: scope, requestBox: RequestBox(), completion: loaded.completion)

        let deadline = Date().addingTimeInterval(10)
        while loaded.calls.isEmpty || cancelled.calls.isEmpty, Date() < deadline {
            try await Task.sleep(nanoseconds: 20_000_000)
        }
        try await Task.sleep(nanoseconds: 200_000_000)

        #expect(cancelled.calls == [LoadCompletions.cancelled()])
        #expect(loaded.calls == [LoadCompletions.loaded(.text("ut30-text"))])
    }
}
