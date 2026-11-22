//
//  IosDialogManagerTests.swift
//  IosLibraryTests
//

import Foundation
import Synchronization
import Testing
import UIKit
@testable import IosLibrary

/// Delivery of the Dialog callbacks on the main thread, exactly once (README 0e, migration plan C),
/// and UT-10: the `show...` methods keep their shape on the new core (S-P5).
///
/// The tests in this suite run in the host app without a window (inside `withHostScreen`, so no
/// other test's window is up), so every `show...` method takes its "no root view controller" path.
/// Each test first requires that no root view controller is found, so that it never presents
/// real UI. The paths with a presented dialog are in `IosDialogManagerShownTests`.
struct IosDialogManagerTests {

    private static let noRootMessage = "Failed to get root view controller"

    /// Records every call of a callback with the thread it ran on.
    private final class CallRecorder<Value: Sendable>: Sendable {
        private let calls = Mutex<[(value: Value, isMainThread: Bool)]>([])

        func record(_ value: Value) {
            let isMainThread = Thread.isMainThread
            calls.withLock { $0.append((value, isMainThread)) }
        }

        var all: [(value: Value, isMainThread: Bool)] {
            calls.withLock { $0 }
        }
    }

    private struct Failure: Sendable, Equatable {
        let isSuccess: Bool
        let errorMessage: String?
    }

    private func requireNoRootViewController() async throws {
        let hasRoot = await MainActor.run { IosDialogManager.shared.getRootViewController() != nil }
        try #require(!hasRoot, "the test process must have no foreground scene, or the tests would present real UI")
    }

    /// Runs `start` on a background thread and waits up to 30 s for `recorder` to get a first
    /// call, then 200 ms more, so that a second call (or a call of another callback) is also seen.
    ///
    /// The first `UIAlertAction` created in the test process can take several seconds on the main
    /// thread (UIKit loads lazily), hence the long upper bound.
    private func runOnBackgroundThread<Value: Sendable>(
        waitingFor recorder: CallRecorder<Value>,
        _ start: @escaping @Sendable () -> Void
    ) async throws {
        DispatchQueue.global().async(execute: start)
        for _ in 0..<3000 where recorder.all.isEmpty {
            try await Task.sleep(nanoseconds: 10_000_000)
        }
        try await Task.sleep(nanoseconds: 200_000_000)
    }

    private func expectSingleFailureOnMain(
        _ calls: [(value: Failure, isMainThread: Bool)],
        sourceLocation: SourceLocation = #_sourceLocation
    ) {
        #expect(calls.count == 1, "completion must be invoked exactly once", sourceLocation: sourceLocation)
        #expect(calls.allSatisfy { $0.isMainThread }, "completion must be invoked on the main thread", sourceLocation: sourceLocation)
        #expect(calls.first?.value == Failure(isSuccess: false, errorMessage: Self.noRootMessage), sourceLocation: sourceLocation)
    }

    @Test func showDialogFailsOnTheMainThreadExactlyOnce() async throws {
        try await withHostScreen {
            try await requireNoRootViewController()
            let completion = CallRecorder<Failure>()

            try await runOnBackgroundThread(waitingFor: completion) {
                IosDialogManager.shared.showDialog(title: "title", message: "message") { isSuccess, errorMessage in
                    completion.record(Failure(isSuccess: isSuccess, errorMessage: errorMessage))
                }
            }

            expectSingleFailureOnMain(completion.all)
        }
    }

    @Test func showAlertFailsOnTheMainThreadExactlyOnce() async throws {
        try await withHostScreen {
            try await requireNoRootViewController()
            let completion = CallRecorder<Failure>()
            let buttons = CallRecorder<String?>()

            try await runOnBackgroundThread(waitingFor: completion) {
                IosDialogManager.shared.showAlert(
                    title: "title",
                    message: "message",
                    onButton: { buttonText, _, _ in buttons.record(buttonText) },
                    completion: { isSuccess, errorMessage in
                        completion.record(Failure(isSuccess: isSuccess, errorMessage: errorMessage))
                    }
                )
            }

            expectSingleFailureOnMain(completion.all)
            #expect(buttons.all.isEmpty)
        }
    }

    @Test func showConfirmDialogFailsOnTheMainThreadExactlyOnce() async throws {
        try await withHostScreen {
            try await requireNoRootViewController()
            let completion = CallRecorder<Failure>()
            let buttons = CallRecorder<String?>()

            try await runOnBackgroundThread(waitingFor: completion) {
                IosDialogManager.shared.showConfirmDialog(
                    title: "title",
                    message: "message",
                    onConfirm: { buttonText, _, _ in buttons.record(buttonText) },
                    onCancel: { buttonText, _, _ in buttons.record(buttonText) },
                    completion: { isSuccess, errorMessage in
                        completion.record(Failure(isSuccess: isSuccess, errorMessage: errorMessage))
                    }
                )
            }

            expectSingleFailureOnMain(completion.all)
            #expect(buttons.all.isEmpty)
        }
    }

    @Test func showDestructiveDialogFailsOnTheMainThreadExactlyOnce() async throws {
        try await withHostScreen {
            try await requireNoRootViewController()
            let completion = CallRecorder<Failure>()
            let buttons = CallRecorder<String?>()

            try await runOnBackgroundThread(waitingFor: completion) {
                IosDialogManager.shared.showDestructiveDialog(
                    title: "title",
                    message: "message",
                    onDestructive: { buttonText, _, _ in buttons.record(buttonText) },
                    onCancel: { buttonText, _, _ in buttons.record(buttonText) },
                    completion: { isSuccess, errorMessage in
                        completion.record(Failure(isSuccess: isSuccess, errorMessage: errorMessage))
                    }
                )
            }

            expectSingleFailureOnMain(completion.all)
            #expect(buttons.all.isEmpty)
        }
    }

    @Test func showActionSheetFailsOnTheMainThreadExactlyOnce() async throws {
        try await withHostScreen {
            try await requireNoRootViewController()
            let completion = CallRecorder<Failure>()
            let buttons = CallRecorder<String?>()
            let sourceView = await MainActor.run { UIView() }

            try await runOnBackgroundThread(waitingFor: completion) {
                IosDialogManager.shared.showActionSheet(
                    title: "title",
                    message: "message",
                    options: ["A", "B"],
                    sourceView: sourceView,
                    onAction: { option, _, _ in buttons.record(option) },
                    completion: { isSuccess, errorMessage in
                        completion.record(Failure(isSuccess: isSuccess, errorMessage: errorMessage))
                    }
                )
            }

            expectSingleFailureOnMain(completion.all)
            #expect(buttons.all.isEmpty)
        }
    }

    @Test func showTextInputDialogFailsOnTheMainThreadExactlyOnce() async throws {
        try await withHostScreen {
            try await requireNoRootViewController()
            let completion = CallRecorder<Failure>()
            let buttons = CallRecorder<String?>()

            try await runOnBackgroundThread(waitingFor: completion) {
                IosDialogManager.shared.showTextInputDialog(
                    title: "title",
                    message: "message",
                    enableConfirmWhenEmpty: false,
                    onConfirm: { buttonText, _, _, _ in buttons.record(buttonText) },
                    onCancel: { buttonText, _, _ in buttons.record(buttonText) },
                    completion: { isSuccess, errorMessage in
                        completion.record(Failure(isSuccess: isSuccess, errorMessage: errorMessage))
                    }
                )
            }

            expectSingleFailureOnMain(completion.all)
            #expect(buttons.all.isEmpty)
        }
    }

    /// The login dialog reports the failure through `completion`, like the other methods, and
    /// never through `onLogin` (S-P5; before 1b it was `onLogin(nil, nil, nil, false, …)` and no
    /// `completion`).
    @Test func showLoginDialogFailsThroughCompletionOnTheMainThreadExactlyOnce() async throws {
        try await withHostScreen {
            try await requireNoRootViewController()
            let completion = CallRecorder<Failure>()
            let others = CallRecorder<String>()

            try await runOnBackgroundThread(waitingFor: completion) {
                IosDialogManager.shared.showLoginDialog(
                    title: "title",
                    message: "message",
                    enableLoginWhenEmpty: false,
                    onLogin: { _, _, _, _, _ in others.record("onLogin") },
                    onCancel: { _, _, _ in others.record("onCancel") },
                    completion: { isSuccess, errorMessage in
                        completion.record(Failure(isSuccess: isSuccess, errorMessage: errorMessage))
                    }
                )
            }

            expectSingleFailureOnMain(completion.all)
            #expect(others.all.isEmpty)
        }
    }

    @Test func completionIsAsynchronousWhenCalledOnTheMainThread() async throws {
        try await withHostScreen {
            try await requireNoRootViewController()
            let completion = CallRecorder<Failure>()

            let calledBeforeReturn = await MainActor.run {
                IosDialogManager.shared.showAlert(title: "title", completion: { isSuccess, errorMessage in
                    completion.record(Failure(isSuccess: isSuccess, errorMessage: errorMessage))
                })
                return !completion.all.isEmpty
            }
            try await runOnBackgroundThread(waitingFor: completion) {}

            #expect(!calledBeforeReturn, "completion must not be invoked before the call returns")
            expectSingleFailureOnMain(completion.all)
        }
    }

    @Test func nilCallbacksDoNotTrap() async throws {
        try await withHostScreen {
            try await requireNoRootViewController()
            let sourceView = await MainActor.run { UIView() }
            let done = CallRecorder<Bool>()

            try await runOnBackgroundThread(waitingFor: done) {
                let manager = IosDialogManager.shared
                manager.showDialog()
                manager.showAlert()
                manager.showConfirmDialog()
                manager.showDestructiveDialog()
                manager.showActionSheet(options: ["A"], sourceView: sourceView)
                manager.showTextInputDialog()
                manager.showLoginDialog()
                // Queued after the blocks above on the main queue, so it runs after all of them.
                DispatchQueue.main.async { done.record(true) }
            }

            #expect(done.all.count == 1)
        }
    }
}
