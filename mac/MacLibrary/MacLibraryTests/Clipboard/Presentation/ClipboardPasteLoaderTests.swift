//
//  ClipboardPasteLoaderTests.swift
//  MacLibraryTests
//

import Testing
import AppKit
import Foundation
@testable import MacLibrary

@Suite("Paste loading")
@MainActor
struct ClipboardPasteLoaderTests {

    private let text = "public.utf8-plain-text"
    private let png = "public.png"

    /// A source with scripted behaviour, so timing and failure can be driven exactly.
    private struct FakeSource: ClipboardPasteLoader.Source {
        let available: [String: Data]
        var delay: Duration = .zero
        var failure: (any Error)?

        func conforms(to identifier: String) async -> Bool {
            available[identifier] != nil
        }

        func loadData(for identifier: String) async throws -> Data {
            if delay > .zero { try? await Task.sleep(for: delay) }
            if let failure { throw failure }
            guard let data = available[identifier] else {
                throw ClipboardError.pasteLoadFailed("missing")
            }
            return data
        }
    }

    private final class Recorder {
        var results: [ClipboardPasteResult] = []
        var callCount: Int { results.count }
    }

    private func makeLoader(acceptedTypes: [String]? = nil,
                            timeout: TimeInterval = 5,
                            recorder: Recorder) throws -> ClipboardPasteLoader {
        try ClipboardPasteLoader(acceptedTypes: acceptedTypes ?? [text, png],
                                 timeout: timeout,
                                 validator: MockClipboardTypeIdentifierValidating(),
                                 onPaste: { recorder.results.append($0) })
    }

    private func wait() async throws {
        try await Task.sleep(for: .milliseconds(150))
    }

    // MARK: - PT-01

    @Test("PT-01: every provider is loaded and returned")
    func loadsEveryProvider() async throws {
        let recorder = Recorder()
        let loader = try makeLoader(recorder: recorder)

        loader.load(from: [
            FakeSource(available: [text: Data("a".utf8)]),
            FakeSource(available: [text: Data("b".utf8)]),
            FakeSource(available: [png: Data("c".utf8)]),
        ])
        try await wait()

        let result = try #require(recorder.results.first)
        #expect(result.items.count == 3)
        #expect(result.failures.isEmpty)
        #expect(!result.isPartial)
    }

    @Test("no providers means an empty result, not a failure")
    func emptyInputIsEmptyResult() throws {
        let recorder = Recorder()
        let loader = try makeLoader(recorder: recorder)

        loader.load(from: [])

        let result = try #require(recorder.results.first)
        #expect(result.isEmpty)
        #expect(!result.isCompleteFailure)
    }

    // MARK: - PT-02 / PT-07

    @Test("PT-02: one failure does not stop the others")
    func partialFailure() async throws {
        let recorder = Recorder()
        let loader = try makeLoader(recorder: recorder)

        loader.load(from: [
            FakeSource(available: [text: Data("a".utf8)]),
            FakeSource(available: [text: Data("b".utf8)],
                       failure: ClipboardError.pasteLoadFailed("boom")),
            FakeSource(available: [text: Data("c".utf8)]),
        ])
        try await wait()

        let result = try #require(recorder.results.first)
        #expect(result.items.count == 2)
        #expect(result.failures.count == 1)
        #expect(result.isPartial)
        #expect(!result.isCompleteFailure)
    }

    @Test("PT-07: every provider failing is a complete failure, not a partial one")
    func completeFailure() async throws {
        let recorder = Recorder()
        let loader = try makeLoader(recorder: recorder)

        loader.load(from: [
            FakeSource(available: [text: Data("a".utf8)],
                       failure: ClipboardError.pasteLoadFailed("boom")),
            FakeSource(available: [text: Data("b".utf8)],
                       failure: ClipboardError.pasteLoadFailed("boom")),
        ])
        try await wait()

        let result = try #require(recorder.results.first)
        #expect(result.isCompleteFailure)
        // Partial means "some worked", so it must be false when none did.
        #expect(!result.isPartial)
    }

    @Test("a provider with no accepted type is a failure, not a silent drop")
    func unmatchedProviderFails() async throws {
        let recorder = Recorder()
        let loader = try makeLoader(acceptedTypes: [text], recorder: recorder)

        loader.load(from: [FakeSource(available: ["public.rtf": Data("a".utf8)])])
        try await wait()

        let result = try #require(recorder.results.first)
        #expect(result.failures.count == 1)
        #expect(result.items.isEmpty)
    }

    // MARK: - PT-03

    @Test("PT-03: a provider that never answers is timed out and onPaste still runs once")
    func timeoutDeliversOnce() async throws {
        let recorder = Recorder()
        let loader = try makeLoader(timeout: 0.1, recorder: recorder)

        loader.load(from: [
            FakeSource(available: [text: Data("fast".utf8)]),
            FakeSource(available: [text: Data("slow".utf8)], delay: .seconds(10)),
        ])
        try await Task.sleep(for: .milliseconds(400))

        #expect(recorder.callCount == 1)
        let result = try #require(recorder.results.first)
        #expect(result.items.count == 1)
        #expect(result.failures.count == 1)
        #expect(result.failures.first?.error == .pasteLoadTimedOut(seconds: 0))
    }

    @Test("PT-03: every provider index appears exactly once in the result")
    func everyIndexAccountedFor() async throws {
        let recorder = Recorder()
        let loader = try makeLoader(timeout: 0.1, recorder: recorder)

        loader.load(from: [
            FakeSource(available: [text: Data("a".utf8)]),
            FakeSource(available: [text: Data("b".utf8)], delay: .seconds(10)),
            FakeSource(available: [text: Data("c".utf8)],
                       failure: ClipboardError.pasteLoadFailed("boom")),
        ])
        try await Task.sleep(for: .milliseconds(400))

        let result = try #require(recorder.results.first)
        let indexes = result.items.map(\.providerIndex) + result.failures.map(\.providerIndex)
        #expect(Set(indexes) == [0, 1, 2])
        #expect(indexes.count == 3)
    }

    // MARK: - PT-04

    @Test("PT-04: the accepted type order decides which representation is loaded")
    func typePriorityIsDeterministic() async throws {
        let recorder = Recorder()
        let loader = try makeLoader(acceptedTypes: [png, text], recorder: recorder)

        // The provider can supply both; the caller's first choice must win.
        loader.load(from: [FakeSource(available: [text: Data("t".utf8), png: Data("p".utf8)])])
        try await wait()

        let item = try #require(recorder.results.first?.items.first)
        #expect(item.data.representations.keys.sorted() == [png])
        #expect(item.data.representations[png] == Data("p".utf8))
    }

    @Test("PT-04: reversing the priority reverses the choice")
    func typePriorityReversed() async throws {
        let recorder = Recorder()
        let loader = try makeLoader(acceptedTypes: [text, png], recorder: recorder)

        loader.load(from: [FakeSource(available: [text: Data("t".utf8), png: Data("p".utf8)])])
        try await wait()

        let item = try #require(recorder.results.first?.items.first)
        #expect(item.data.representations.keys.sorted() == [text])
    }

    // MARK: - PT-05 / PT-06

    @Test("PT-06: results are in input order, not completion order")
    func resultsAreInInputOrder() async throws {
        let recorder = Recorder()
        let loader = try makeLoader(timeout: 5, recorder: recorder)

        // The last provider finishes first.
        loader.load(from: [
            FakeSource(available: [text: Data("a".utf8)], delay: .milliseconds(80)),
            FakeSource(available: [text: Data("b".utf8)], delay: .milliseconds(40)),
            FakeSource(available: [text: Data("c".utf8)]),
        ])
        try await Task.sleep(for: .milliseconds(400))

        let result = try #require(recorder.results.first)
        #expect(result.items.map(\.providerIndex) == [0, 1, 2])
        #expect(result.items.map { $0.data.representations[self.text] }
                == [Data("a".utf8), Data("b".utf8), Data("c".utf8)])
    }

    @Test("PT-05: cancelling suppresses delivery")
    func cancelSuppressesDelivery() async throws {
        let recorder = Recorder()
        let loader = try makeLoader(timeout: 5, recorder: recorder)

        loader.load(from: [FakeSource(available: [text: Data("a".utf8)],
                                      delay: .milliseconds(200))])
        loader.cancel()
        try await Task.sleep(for: .milliseconds(400))

        // The view that asked for the paste is gone; there is nobody to hand a result to.
        #expect(recorder.callCount == 0)
    }

    @Test("PT-05: cancelling twice is a no-op")
    func cancelIsIdempotent() throws {
        let recorder = Recorder()
        let loader = try makeLoader(recorder: recorder)
        loader.cancel()
        loader.cancel()
        #expect(recorder.callCount == 0)
    }

    @Test("cancelling after delivery does not undo it")
    func cancelAfterDelivery() async throws {
        let recorder = Recorder()
        let loader = try makeLoader(recorder: recorder)

        loader.load(from: [FakeSource(available: [text: Data("a".utf8)])])
        try await wait()
        loader.cancel()

        #expect(recorder.callCount == 1)
    }

    // MARK: - H-4 repeated presses

    @Test("H-4: a second press delivers its own result")
    func secondPressDelivers() async throws {
        let recorder = Recorder()
        let loader = try makeLoader(recorder: recorder)

        loader.load(from: [FakeSource(available: [text: Data("first".utf8)])])
        try await wait()
        loader.load(from: [FakeSource(available: [text: Data("second".utf8)])])
        try await wait()

        // The button stays on screen, so the loader outlives one press. Exactly-once is per
        // press, not per loader.
        #expect(recorder.callCount == 2)
        #expect(recorder.results.last?.items.first?.data.representations[text] == Data("second".utf8))
    }

    @Test("H-4: a new press supersedes one still running")
    func newPressSupersedesRunning() async throws {
        let recorder = Recorder()
        let loader = try makeLoader(timeout: 5, recorder: recorder)

        loader.load(from: [FakeSource(available: [text: Data("slow".utf8)],
                                      delay: .milliseconds(300))])
        try await Task.sleep(for: .milliseconds(50))
        loader.load(from: [FakeSource(available: [text: Data("fast".utf8)])])
        try await Task.sleep(for: .milliseconds(600))

        // The superseded press must not deliver: its result is for a payload the user has
        // already replaced.
        #expect(recorder.callCount == 1)
        #expect(recorder.results.first?.items.first?.data.representations[text] == Data("fast".utf8))
    }

    @Test("H-4: cancelling still suppresses a later press")
    func cancelSuppressesSubsequentPresses() async throws {
        let recorder = Recorder()
        let loader = try makeLoader(recorder: recorder)

        loader.cancel()
        loader.load(from: [FakeSource(available: [text: Data("a".utf8)])])
        try await wait()

        // cancel means the owning view is gone, so nothing may be delivered afterwards.
        #expect(recorder.callCount == 0)
    }

    // MARK: - H-1 unresponsive providers

    /// Never resumes, and ignores cancellation. Stands in for a provider whose callback never
    /// arrives, which a `Task.sleep` based fake cannot represent because sleeping *is*
    /// cancellable.
    private struct HangingSource: ClipboardPasteLoader.Source {
        let available: [String: Data]

        func conforms(to identifier: String) async -> Bool { available[identifier] != nil }

        func loadData(for identifier: String) async throws -> Data {
            await withCheckedContinuation { (_: CheckedContinuation<Void, Never>) in
                // Deliberately dropped: no resume, no cancellation handler.
            }
            return Data()
        }
    }

    @Test("H-1: a provider that never calls back still hits the deadline", .timeLimit(.minutes(1)))
    func hangingProviderStillTimesOut() async throws {
        let recorder = Recorder()
        let loader = try makeLoader(timeout: 0.2, recorder: recorder)

        loader.load(from: [
            FakeSource(available: [text: Data("ok".utf8)]),
            HangingSource(available: [text: Data("never".utf8)]),
        ])
        try await Task.sleep(for: .milliseconds(800))

        // Waiting for the group to drain would hang here forever.
        #expect(recorder.callCount == 1)
        let result = try #require(recorder.results.first)
        #expect(result.items.count == 1)
        #expect(result.failures.first?.error == .pasteLoadTimedOut(seconds: 0))
    }

    @Test("H-1: every provider hanging still produces a result", .timeLimit(.minutes(1)))
    func allHangingStillTimesOut() async throws {
        let recorder = Recorder()
        let loader = try makeLoader(timeout: 0.2, recorder: recorder)

        loader.load(from: [
            HangingSource(available: [text: Data("a".utf8)]),
            HangingSource(available: [text: Data("b".utf8)]),
        ])
        try await Task.sleep(for: .milliseconds(800))

        #expect(recorder.callCount == 1)
        #expect(recorder.results.first?.isCompleteFailure == true)
    }

    // MARK: - M-4 / M-5 the production adapter boundary

    /// Exercises `ItemProviderSource` against a real `NSItemProvider`.
    ///
    /// PT-12 and PT-13 inject a fake source, so they never run the adapter, the progress box
    /// or the gate that H-1 also changed. That is the same shape of gap the first review
    /// found: a test that agrees with the implementation's assumptions instead of checking
    /// them.
    @Suite("Item provider adapter")
    @MainActor
    struct ItemProviderSourceTests {

        private let text = "public.utf8-plain-text"

        @Test("the adapter loads through a real NSItemProvider")
        func loadsThroughRealProvider() async throws {
            let provider = NSItemProvider()
            provider.registerDataRepresentation(forTypeIdentifier: text, visibility: .all) { completion in
                completion(Data("real".utf8), nil)
                return nil
            }
            let source = PasteButtonFactory.ItemProviderSource(provider: provider)

            #expect(await source.conforms(to: text))
            #expect(try await source.loadData(for: text) == Data("real".utf8))
        }

        @Test("M-4: cancelling before the Progress exists still cancels the provider work",
              .timeLimit(.minutes(1)))
        func cancelBeforeProgressInstalled() async throws {
            // The provider hands back its Progress only after the load has started, so a task
            // cancelled at the wrong moment can leave a Progress nobody ever cancels. The
            // caller returns either way, which is exactly why this needs its own test.
            let observed = ProgressObserver()
            let provider = NSItemProvider()
            provider.registerDataRepresentation(forTypeIdentifier: text, visibility: .all) { _ in
                let progress = Progress(totalUnitCount: 1)
                observed.value = progress
                // Never completes: only cancellation can end this.
                return progress
            }
            let source = PasteButtonFactory.ItemProviderSource(provider: provider)

            let task = Task { try await source.loadData(for: self.text) }
            // Cancel while the load is starting, so the race is the one described above.
            task.cancel()
            _ = try? await task.value
            try await Task.sleep(for: .milliseconds(300))

            let progress = try #require(observed.value, "the provider should have started")
            #expect(progress.isCancelled, "a Progress installed after cancellation must still be cancelled")
        }

        @Test("M-4: cancelling after the Progress exists cancels it", .timeLimit(.minutes(1)))
        func cancelAfterProgressInstalled() async throws {
            let observed = ProgressObserver()
            let provider = NSItemProvider()
            provider.registerDataRepresentation(forTypeIdentifier: text, visibility: .all) { _ in
                let progress = Progress(totalUnitCount: 1)
                observed.value = progress
                return progress
            }
            let source = PasteButtonFactory.ItemProviderSource(provider: provider)

            let task = Task { try await source.loadData(for: self.text) }
            try await Task.sleep(for: .milliseconds(200))
            task.cancel()
            _ = try? await task.value
            try await Task.sleep(for: .milliseconds(200))

            let progress = try #require(observed.value)
            #expect(progress.isCancelled)
        }

        @Test("a cancelled load reports cancellation rather than hanging", .timeLimit(.minutes(1)))
        func cancelledLoadThrows() async throws {
            let provider = NSItemProvider()
            provider.registerDataRepresentation(forTypeIdentifier: text, visibility: .all) { _ in
                Progress(totalUnitCount: 1)
            }
            let source = PasteButtonFactory.ItemProviderSource(provider: provider)

            let task = Task { try await source.loadData(for: self.text) }
            try await Task.sleep(for: .milliseconds(100))
            task.cancel()

            await #expect(throws: (any Error).self) { _ = try await task.value }
        }
    }

    /// Captures the `Progress` a provider creates, from whichever thread creates it.
    private final class ProgressObserver: @unchecked Sendable {
        private let lock = NSLock()
        private var stored: Progress?
        var value: Progress? {
            get { lock.withLock { stored } }
            set { lock.withLock { stored = newValue } }
        }
    }

    // MARK: - Validation

    @Test("an empty accepted type list is rejected")
    func rejectsEmptyAcceptedTypes() {
        let recorder = Recorder()
        #expect(throws: ClipboardError.invalidTypeIdentifier("")) {
            _ = try self.makeLoader(acceptedTypes: [], recorder: recorder)
        }
    }

    @Test("a malformed accepted type is rejected")
    func rejectsMalformedAcceptedType() throws {
        let recorder = Recorder()
        let validator = MockClipboardTypeIdentifierValidating()
        validator.invalidIdentifiers = ["bad"]
        #expect(throws: ClipboardError.invalidTypeIdentifier("bad")) {
            _ = try ClipboardPasteLoader(acceptedTypes: ["bad"], timeout: 5,
                                         validator: validator, onPaste: { _ in })
        }
    }

    @Test("a timeout outside the allowed range is rejected", arguments: [0.0, -1.0, 301.0])
    func rejectsInvalidTimeout(timeout: TimeInterval) {
        let recorder = Recorder()
        #expect(throws: ClipboardError.invalidConfiguration(
            "Paste timeout must be greater than 0 and at most 300 seconds.")) {
            _ = try self.makeLoader(timeout: timeout, recorder: recorder)
        }
    }
}

@Suite("Paste button lifetime")
@MainActor
struct PasteButtonLifetimeTests {

    private func makeCoordinator() -> ClipboardSystemCoordinator {
        ClipboardSystemCoordinator(
            snapshotter: MockFilePromiseSnapshotter(),
            stagingBase: URL(filePath: NSTemporaryDirectory()).appending(path: UUID().uuidString))
    }

    @Test("PT-08: releasing the container view cancels the paste")
    func deinitCancelsPaste() async throws {
        var cancelled: [ClipboardPasteHandle] = []
        let handle = ClipboardPasteHandle()

        // An explicit nil-out rather than scope exit: NSView subclasses are autoreleased, so
        // leaving the scope does not by itself guarantee deinit has run.
        autoreleasepool {
            var view: ClipboardPasteContainerView? = ClipboardPasteContainerView(
                handle: handle, content: NSView(), onCancel: { cancelled.append($0) })
            view = nil
            #expect(view == nil)
        }

        // The view is the only thing whose lifetime tracks "this paste is still wanted".
        #expect(cancelled == [handle])
    }

    @Test("PT-08: cancelling a paste twice does not crash")
    func cancelPasteIsIdempotent() throws {
        let coordinator = makeCoordinator()
        let loader = try ClipboardPasteLoader(acceptedTypes: ["public.utf8-plain-text"],
                                              timeout: 5,
                                              validator: MockClipboardTypeIdentifierValidating(),
                                              onPaste: { _ in })
        let handle = coordinator.registerPasteLoader(loader)
        #expect(coordinator.registeredPasteLoaderCount == 1)

        coordinator.cancelPaste(handle)
        coordinator.cancelPaste(handle)
        coordinator.cancelPaste(ClipboardPasteHandle())

        #expect(coordinator.registeredPasteLoaderCount == 0)
    }

    @Test("the coordinator holds the loader until the paste is cancelled")
    func coordinatorOwnsLoader() throws {
        let coordinator = makeCoordinator()
        let loader = try ClipboardPasteLoader(acceptedTypes: ["public.utf8-plain-text"],
                                              timeout: 5,
                                              validator: MockClipboardTypeIdentifierValidating(),
                                              onPaste: { _ in })
        _ = coordinator.registerPasteLoader(loader)
        #expect(coordinator.registeredPasteLoaderCount == 1)
    }
}
