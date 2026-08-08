//
//  UnityIosClipboardManagerCallbackContractTests.swift
//  UnityIosPluginTests
//

import Testing
import Foundation
@testable import IosLibrary
@testable import UnityIosPlugin

/// Pins the Bridge callback contract that the `@Sendable` handler annotation formalizes:
/// Unity may call from any thread, and every handler is invoked **exactly once on the main
/// thread**. A `nil` handler is always acceptable.
///
/// Serialized: the observation cases share `UIPasteboard.general`.
@Suite(.serialized)
struct UnityIosClipboardManagerCallbackContractTests {

    /// Records deliveries from whichever thread the handler lands on.
    private final class Recorder: @unchecked Sendable {
        private let lock = NSLock()
        private var _threads: [Bool] = []

        func record(isMain: Bool) {
            lock.lock()
            _threads.append(isMain)
            lock.unlock()
        }

        var count: Int {
            lock.lock(); defer { lock.unlock() }
            return _threads.count
        }

        var allOnMainThread: Bool {
            lock.lock(); defer { lock.unlock() }
            return _threads.allSatisfy { $0 }
        }
    }

    private let manager = UnityIosClipboardManager.shared

    /// Lets any late duplicate delivery land before the assertion runs.
    private func settle() async {
        try? await Task.sleep(nanoseconds: 500_000_000)
    }

    @Test func handlerFromABackgroundThreadIsDeliveredOnceOnTheMainThread() async {
        let recorder = Recorder()
        let json = "{\"scope\":{\"kind\":\"general\"}}"

        // Unity's C entry points are not main-thread-bound; this is the case the `@Sendable`
        // handler annotation makes explicit.
        DispatchQueue.global().async { [manager] in
            manager.getSnapshot(requestJson: json) { _ in
                recorder.record(isMain: Thread.isMainThread)
            }
        }

        await settle()
        #expect(recorder.count == 1)
        #expect(recorder.allOnMainThread)
    }

    @Test func malformedRequestStillDeliversExactlyOnce() async {
        let recorder = Recorder()
        manager.getSnapshot(requestJson: "{not json") { _ in
            recorder.record(isMain: Thread.isMainThread)
        }
        await settle()
        #expect(recorder.count == 1)
        #expect(recorder.allOnMainThread)
    }

    // MARK: - Early-failure paths from a background thread
    //
    // Parse/validation failures return *before* the main-actor hop, so a naive implementation
    // hands the callback back on the caller's thread. These cases pin the contract for the
    // combination the earlier tests missed: background caller + malformed request.

    @Test func malformedOperationRequestFromBackgroundIsDeliveredOnTheMainThread() async {
        let recorder = Recorder()
        DispatchQueue.global().async { [manager] in
            manager.copy(requestJson: "{not json") { _, _, _ in
                recorder.record(isMain: Thread.isMainThread)
            }
        }
        await settle()
        #expect(recorder.count == 1)
        #expect(recorder.allOnMainThread)
    }

    @Test func rejectedAppendOptionsFromBackgroundAreDeliveredOnTheMainThread() async {
        // `append` rejects an `options` key on a second guard, separate from the parse failure.
        let recorder = Recorder()
        let json = """
        {"scope":{"kind":"general"},"content":{"kind":"plainText","text":"hi"},"options":{"localOnly":true}}
        """
        DispatchQueue.global().async { [manager] in
            manager.append(requestJson: json) { isSuccess, _, _ in
                _ = isSuccess
                recorder.record(isMain: Thread.isMainThread)
            }
        }
        await settle()
        #expect(recorder.count == 1)
        #expect(recorder.allOnMainThread)
    }

    @Test func malformedJSONCallbackRequestFromBackgroundIsDeliveredOnTheMainThread() async {
        let recorder = Recorder()
        DispatchQueue.global().async { [manager] in
            manager.getSnapshot(requestJson: "{not json") { _ in
                recorder.record(isMain: Thread.isMainThread)
            }
        }
        await settle()
        #expect(recorder.count == 1)
        #expect(recorder.allOnMainThread)
    }

    @Test func malformedObserveRequestFromBackgroundDeliversStartHandlerOnTheMainThread() async {
        let startRecorder = Recorder()
        let changeRecorder = Recorder()
        DispatchQueue.global().async { [manager] in
            manager.startObserving(
                requestJson: "{\"scope\": null}",
                changeHandler: { _ in changeRecorder.record(isMain: Thread.isMainThread) },
                startHandler: { _, _, _ in startRecorder.record(isMain: Thread.isMainThread) }
            )
        }
        await settle()
        #expect(startRecorder.count == 1)
        #expect(startRecorder.allOnMainThread)
        #expect(changeRecorder.count == 0)
    }

    @Test func nilHandlerIsAccepted() async {
        // The Bridge passes NULL whenever Unity registered no callback; this must not trap.
        manager.getSnapshot(requestJson: "{\"scope\":{\"kind\":\"general\"}}", handler: nil)
        manager.getSnapshot(requestJson: "{not json", handler: nil)
        manager.stopObserving(handler: nil)
        await settle()
    }

    @Test func startObservingDeliversStartHandlerOnceThenStopObservingDoes() async {
        let startRecorder = Recorder()
        let stopRecorder = Recorder()
        let json = "{\"scope\":{\"kind\":\"general\"}}"

        DispatchQueue.global().async { [manager] in
            manager.startObserving(
                requestJson: json,
                changeHandler: { _ in },
                startHandler: { isSuccess, _, _ in
                    _ = isSuccess
                    startRecorder.record(isMain: Thread.isMainThread)
                }
            )
        }
        await settle()
        #expect(startRecorder.count == 1)
        #expect(startRecorder.allOnMainThread)

        manager.stopObserving { _, _, _ in
            stopRecorder.record(isMain: Thread.isMainThread)
        }
        await settle()
        #expect(stopRecorder.count == 1)
        #expect(stopRecorder.allOnMainThread)
        // Stopping must not retroactively fire the start handler again.
        #expect(startRecorder.count == 1)
    }

    @Test func malformedObserveRequestDeliversStartHandlerAndNeverTheChangeHandler() async {
        let startRecorder = Recorder()
        let changeRecorder = Recorder()

        manager.startObserving(
            requestJson: "{\"scope\": null}",
            changeHandler: { _ in changeRecorder.record(isMain: Thread.isMainThread) },
            startHandler: { _, _, _ in startRecorder.record(isMain: Thread.isMainThread) }
        )
        await settle()
        #expect(startRecorder.count == 1)
        #expect(startRecorder.allOnMainThread)
        #expect(changeRecorder.count == 0)
    }
}
