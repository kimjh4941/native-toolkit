//
//  IosDialogManagerShownTests.swift
//  IosLibraryTests
//

import Foundation
import Testing
import UIKit
@testable import IosLibrary

/// `PresentationEnvironment` whose UIKit declines every presentation: `present` does nothing and
/// calls no completion, and `presentingViewController` stays `nil` (MS-01).
@MainActor
struct DecliningPresentationEnvironment: PresentationEnvironment {
    let top: UIViewController
    /// A misbehaving UIKit: declines (no `presentingViewController`) and still calls the
    /// completion on the next turn.
    var completesAnyway = false

    func firstActiveSceneTop() -> UIViewController? { top }
    func foregroundTop() -> UIViewController? { top }
    func isSettled(_ node: UIViewController) -> Bool { true }
    func isStableForLegacyPresentation(_ node: UIViewController) -> Bool { true }
    func isInWindow(_ node: UIViewController) -> Bool { true }
    func waitForTransition(of node: UIViewController, then: @escaping @MainActor () -> Void) -> Bool { false }
    func nextTurn(_ body: @escaping @MainActor () -> Void) {
        DispatchQueue.main.async { MainActor.assumeIsolated { body() } }
    }
    func anchorPopover(of presented: UIViewController, at node: UIViewController) {}
    func present(_ presented: UIViewController, on node: UIViewController, animated: Bool, completion: @escaping @MainActor () -> Void) {
        guard completesAnyway else { return }
        DispatchQueue.main.async { MainActor.assumeIsolated { completion() } }
    }
    func isPresentationAccepted(_ presented: UIViewController) -> Bool { false }
}

/// The `animated` argument of each presentation, in order.
@MainActor
final class AnimationLog {
    private(set) var values: [Bool] = []

    func record(_ value: Bool) {
        values.append(value)
    }
}

/// UIKit (``UIKitPresentationEnvironment``), recording the `animated` argument of `present`.
@MainActor
struct AnimationRecordingEnvironment: PresentationEnvironment {
    let base = UIKitPresentationEnvironment()
    let log: AnimationLog

    func firstActiveSceneTop() -> UIViewController? { base.firstActiveSceneTop() }
    func foregroundTop() -> UIViewController? { base.foregroundTop() }
    func isSettled(_ node: UIViewController) -> Bool { base.isSettled(node) }
    func isStableForLegacyPresentation(_ node: UIViewController) -> Bool { base.isStableForLegacyPresentation(node) }
    func isInWindow(_ node: UIViewController) -> Bool { base.isInWindow(node) }
    func waitForTransition(of node: UIViewController, then: @escaping @MainActor () -> Void) -> Bool {
        base.waitForTransition(of: node, then: then)
    }
    func nextTurn(_ body: @escaping @MainActor () -> Void) { base.nextTurn(body) }
    func anchorPopover(of presented: UIViewController, at node: UIViewController) { base.anchorPopover(of: presented, at: node) }
    func present(_ presented: UIViewController, on node: UIViewController, animated: Bool, completion: @escaping @MainActor () -> Void) {
        log.record(animated)
        base.present(presented, on: node, animated: animated, completion: completion)
    }
    func isPresentationAccepted(_ presented: UIViewController) -> Bool { base.isPresentationAccepted(presented) }
}

/// UT-10 (with a presented dialog) and UT-11: the dialog manager on the host app.
@MainActor
struct IosDialogManagerShownTests {

    /// One callback of a `show...` method.
    enum Event: Equatable {
        case completion(Bool, String?)
        case button(String, [String?])
    }

    private func manager(_ sessions: SessionRecorder) -> IosDialogManager {
        IosDialogManager(core: AlertDialogPresenter.recording(into: sessions))
    }

    /// Waits for the dialog of the latest session and for `completion(true, nil)`.
    private func waitShown(_ sessions: SessionRecorder, _ events: MainRecorder<Event>, count: Int) async throws -> DialogSession {
        #expect(await waitUntil { sessions.sessions.count == count && sessions.last?.isPresented == true })
        #expect(await waitUntil { events.values.last == .completion(true, nil) }, "completion(true, nil) once presented")
        return try #require(sessions.last)
    }

    // MARK: - UT-10: the button callbacks keep their values

    @Test func theButtonCallbacksOfTheShowMethodsKeepTheirValues() async throws {
        try await withHostWindow { host in
            let sessions = SessionRecorder()
            let events = MainRecorder<Event>()
            let manager = manager(sessions)
            let completion: @MainActor @Sendable (Bool, String?) -> Void = { events.record(.completion($0, $1)) }
            func button(_ name: String) -> @MainActor @Sendable (String?, Bool, String?) -> Void {
                { title, isSuccess, error in events.record(.button(name, [title, "\(isSuccess)", error])) }
            }

            manager.showAlert(title: "t", buttonText: "Okay", onButton: button("onButton"), completion: completion)
            try await waitShown(sessions, events, count: 1).press(0)
            _ = await waitUntil { events.values.count == 2 }
            _ = await waitUntil { host.root.presentedViewController == nil }

            manager.showConfirmDialog(confirmTitle: "Yes", cancelTitle: "No", onConfirm: button("onConfirm"), onCancel: button("onCancel"),
                                      completion: completion)
            try await waitShown(sessions, events, count: 2).press(0)
            _ = await waitUntil { events.values.count == 4 }
            _ = await waitUntil { host.root.presentedViewController == nil }
            manager.showConfirmDialog(confirmTitle: "Yes", cancelTitle: "No", onConfirm: button("onConfirm"), onCancel: button("onCancel"),
                                      completion: completion)
            try await waitShown(sessions, events, count: 3).press(1)
            _ = await waitUntil { events.values.count == 6 }
            _ = await waitUntil { host.root.presentedViewController == nil }

            manager.showDestructiveDialog(onDestructive: button("onDestructive"), onCancel: button("onCancel"), completion: completion)
            try await waitShown(sessions, events, count: 4).press(0)
            _ = await waitUntil { events.values.count == 8 }
            _ = await waitUntil { host.root.presentedViewController == nil }

            manager.showActionSheet(options: ["A", "B"], sourceView: host.root.view, onAction: button("onAction"), completion: completion)
            try await waitShown(sessions, events, count: 5).press(1)
            _ = await waitUntil { events.values.count == 10 }
            _ = await waitUntil { host.root.presentedViewController == nil }
            manager.showActionSheet(options: ["A", "B"], cancelTitle: "Close", sourceView: host.root.view, onAction: button("onAction"),
                                    completion: completion)
            try await waitShown(sessions, events, count: 6).press(2)
            _ = await waitUntil { events.values.count == 12 }
            _ = await waitUntil { host.root.presentedViewController == nil }

            #expect(events.values == [
                .completion(true, nil), .button("onButton", ["Okay", "true", nil]),
                .completion(true, nil), .button("onConfirm", ["Yes", "true", nil]),
                .completion(true, nil), .button("onCancel", ["No", "true", nil]),
                .completion(true, nil), .button("onDestructive", ["Delete", "true", nil]),
                .completion(true, nil), .button("onAction", ["B", "true", nil]),
                .completion(true, nil), .button("onAction", ["Close", "true", nil]),
            ])
            #expect(events.allOnMainThread)
        }
    }

    @Test func theInputCallbacksOfTheShowMethodsKeepTheirValues() async throws {
        try await withHostWindow { host in
            let sessions = SessionRecorder()
            let events = MainRecorder<Event>()
            let manager = manager(sessions)
            let completion: @MainActor @Sendable (Bool, String?) -> Void = { events.record(.completion($0, $1)) }

            manager.showTextInputDialog(onConfirm: { title, text, isSuccess, error in
                events.record(.button("onConfirm", [title, text, "\(isSuccess)", error]))
            }, onCancel: { title, isSuccess, error in
                events.record(.button("onCancel", [title, "\(isSuccess)", error]))
            }, completion: completion)
            var session = try await waitShown(sessions, events, count: 1)
            session.alert?.textFields?[0].text = "Taro 太郎"
            session.press(0)
            _ = await waitUntil { events.values.count == 2 }
            _ = await waitUntil { host.root.presentedViewController == nil }

            manager.showTextInputDialog(onCancel: { title, isSuccess, error in
                events.record(.button("onCancel", [title, "\(isSuccess)", error]))
            }, completion: completion)
            session = try await waitShown(sessions, events, count: 2)
            session.alert?.textFields?[0].text = "dropped"
            session.press(1)
            _ = await waitUntil { events.values.count == 4 }
            _ = await waitUntil { host.root.presentedViewController == nil }

            manager.showLoginDialog(onLogin: { title, username, password, isSuccess, error in
                events.record(.button("onLogin", [title, username, password, "\(isSuccess)", error]))
            }, completion: completion)
            session = try await waitShown(sessions, events, count: 3)
            session.alert?.textFields?[0].text = "taro"
            session.alert?.textFields?[1].text = "secret1"
            session.press(0)
            _ = await waitUntil { events.values.count == 6 }
            _ = await waitUntil { host.root.presentedViewController == nil }

            manager.showLoginDialog(onCancel: { title, isSuccess, error in
                events.record(.button("onCancel", [title, "\(isSuccess)", error]))
            }, completion: completion)
            session = try await waitShown(sessions, events, count: 4)
            session.press(1)
            _ = await waitUntil { events.values.count == 8 }
            _ = await waitUntil { host.root.presentedViewController == nil }

            #expect(events.values == [
                .completion(true, nil), .button("onConfirm", ["OK", "Taro 太郎", "true", nil]),
                .completion(true, nil), .button("onCancel", ["Cancel", "true", nil]),
                .completion(true, nil), .button("onLogin", ["Login", "taro", "secret1", "true", nil]),
                .completion(true, nil), .button("onCancel", ["Cancel", "true", nil]),
            ])
        }
    }

    @Test func showDialogPresentsTheCallersActionsAndFields() async throws {
        try await withHostWindow { host in
            let sessions = SessionRecorder()
            let events = MainRecorder<Event>()
            let manager = manager(sessions)
            let custom = UIAlertAction(title: "Custom", style: .destructive) { _ in events.record(.button("custom", [])) }
            manager.showDialog(title: "t", actions: [custom], textFields: [{ $0.placeholder = "field" }]) { events.record(.completion($0, $1)) }
            let session = try await waitShown(sessions, events, count: 1)
            let alert = try #require(session.alert)
            #expect(alert.actions.map(\.title) == ["Custom"])
            #expect(alert.textFields?.map(\.placeholder) == ["field"])
            #expect(session.actionHandlers.isEmpty, "the caller's actions are added as they are")

            host.root.dismiss(animated: false)
            #expect(await waitUntil { host.root.presentedViewController == nil })
            manager.showDialog(title: "default") { events.record(.completion($0, $1)) }
            let second = try await waitShown(sessions, events, count: 2)
            #expect(second.alert?.actions.map(\.title) == ["OK"], "an OK action when none is given")
            #expect(events.values == [.completion(true, nil), .completion(true, nil)])
        }
    }

    // MARK: - UT-10: the other arguments of the show... methods keep their effect

    /// `animated` of `showDialog` and `showActionSheet` reaches `present`; the other methods and
    /// the new API present animated.
    @Test func theAnimatedArgumentReachesThePresentation() async throws {
        try await withHostWindow { host in
            let sessions = SessionRecorder()
            let events = MainRecorder<Event>()
            let log = AnimationLog()
            let manager = IosDialogManager(core: AlertDialogPresenter(makeEnvironment: { AnimationRecordingEnvironment(log: log) },
                                                                      observeSession: { sessions.record($0) }))
            let completion: @MainActor @Sendable (Bool, String?) -> Void = { events.record(.completion($0, $1)) }

            manager.showDialog(title: "t", animated: false, completion: completion)
            _ = try await waitShown(sessions, events, count: 1)
            host.root.dismiss(animated: false)
            #expect(await waitUntil { host.root.presentedViewController == nil })

            manager.showActionSheet(options: ["A"], sourceView: host.root.view, animated: false, completion: completion)
            try await waitShown(sessions, events, count: 2).press(1)
            #expect(await waitUntil { host.root.presentedViewController == nil })

            manager.showAlert(completion: completion)
            try await waitShown(sessions, events, count: 3).press(0)
            #expect(await waitUntil { host.root.presentedViewController == nil })

            manager.show(.alert(title: nil, message: nil), presenter: .foreground) { _ in }
            #expect(await waitUntil { sessions.sessions.count == 4 && sessions.last?.isPresented == true })
            sessions.last?.press(0)
            #expect(await waitUntil { host.root.presentedViewController == nil })

            #expect(log.values == [false, false, true, true])
        }
    }

    /// The popover anchor arguments of `showDialog` and `showActionSheet` reach the action
    /// sheet's popover as before (S-P5): the source view and rect (`nil` is the view's bounds), the
    /// bar button item, and the arrow directions. Checked where an action sheet is a popover (iPad,
    /// and iPhone with iOS 26); elsewhere it has no popover to anchor.
    @Test func theAnchorArgumentsOfTheShowMethodsReachThePopover() async throws {
        try await withHostWindow { host in
            let sessions = SessionRecorder()
            let events = MainRecorder<Event>()
            let manager = manager(sessions)
            let completion: @MainActor @Sendable (Bool, String?) -> Void = { events.record(.completion($0, $1)) }
            let view: UIView = host.root.view
            let isPopover = UIDevice.current.userInterfaceIdiom == .pad
                || ProcessInfo.processInfo.isOperatingSystemAtLeast(OperatingSystemVersion(majorVersion: 26, minorVersion: 0, patchVersion: 0))
            @MainActor func popover(_ session: DialogSession) throws -> UIPopoverPresentationController? {
                let popover = session.alert?.popoverPresentationController
                if isPopover {
                    try #require(popover != nil, "an action sheet is a popover here")
                }
                return popover
            }
            let rect = CGRect(x: 10, y: 20, width: 30, height: 40)

            manager.showDialog(preferredStyle: .actionSheet, sourceView: view, sourceRect: rect, permittedArrowDirections: .up,
                               completion: completion)
            var session = try await waitShown(sessions, events, count: 1)
            if let anchored = try popover(session) {
                #expect(anchored.sourceView === view)
                #expect(anchored.sourceRect == rect)
                #expect(anchored.permittedArrowDirections == .up)
            }
            host.root.dismiss(animated: false)
            #expect(await waitUntil { host.root.presentedViewController == nil })

            manager.showActionSheet(options: ["A"], sourceView: view, sourceRect: nil, completion: completion)
            session = try await waitShown(sessions, events, count: 2)
            if let anchored = try popover(session) {
                #expect(anchored.sourceView === view)
                #expect(anchored.sourceRect == view.bounds, "nil is the source view's bounds")
                #expect(anchored.permittedArrowDirections == .any)
            }
            session.press(1)
            #expect(await waitUntil { host.root.presentedViewController == nil })

            let toolbar = UIToolbar(frame: CGRect(x: 0, y: 100, width: view.bounds.width, height: 44))
            let item = UIBarButtonItem(title: "Anchor", style: .plain, target: nil, action: nil)
            toolbar.items = [item]
            view.addSubview(toolbar)
            defer { toolbar.removeFromSuperview() }
            manager.showDialog(preferredStyle: .actionSheet, barButtonItem: item, completion: completion)
            session = try await waitShown(sessions, events, count: 3)
            if let anchored = try popover(session) {
                #expect(anchored.barButtonItem === item)
            }
            host.root.dismiss(animated: false)
            #expect(await waitUntil { host.root.presentedViewController == nil })
        }
    }

    /// `showDialog` applies `textFields` only to an alert: an action sheet is presented without
    /// them (UIKit does not allow text fields on an action sheet).
    @Test func showDialogIgnoresTheTextFieldsOfAnActionSheet() async throws {
        try await withHostWindow { host in
            let sessions = SessionRecorder()
            let events = MainRecorder<Event>()
            let manager = manager(sessions)
            manager.showDialog(preferredStyle: .actionSheet, textFields: [{ $0.placeholder = "ignored" }], sourceView: host.root.view) {
                events.record(.completion($0, $1))
            }
            let session = try await waitShown(sessions, events, count: 1)
            let fields = session.alert?.textFields ?? []
            #expect(fields.isEmpty)
            #expect(events.values == [.completion(true, nil)])
            host.root.dismiss(animated: false)
            #expect(await waitUntil { host.root.presentedViewController == nil })
        }
    }

    /// S-P5, SR-20: when UIKit declines the presentation, `completion(false, "Failed to present
    /// the dialog")` comes once, and no button callback.
    @Test func aDeclinedPresentationFailsThroughTheCompletionOnce() async throws {
        let events = MainRecorder<Event>()
        let top = UIViewController()
        let manager = IosDialogManager(core: AlertDialogPresenter(makeEnvironment: { DecliningPresentationEnvironment(top: top) }))
        manager.showAlert(onButton: { _, _, _ in events.record(.button("onButton", [])) },
                          completion: { events.record(.completion($0, $1)) })
        manager.showLoginDialog(onLogin: { _, _, _, _, _ in events.record(.button("onLogin", [])) },
                                completion: { events.record(.completion($0, $1)) })
        _ = await waitUntil { events.values.count == 2 }
        try await Task.sleep(nanoseconds: 300_000_000)
        #expect(events.values == [.completion(false, "Failed to present the dialog"), .completion(false, "Failed to present the dialog")])
    }

    /// The same when UIKit declines and still calls `present`'s completion: the failure stays the
    /// only report (no `completion(true, nil)` after it).
    @Test func aDeclinedPresentationWhoseCompletionStillComesFailsOnce() async throws {
        let events = MainRecorder<Event>()
        let top = UIViewController()
        let manager = IosDialogManager(core: AlertDialogPresenter(makeEnvironment: {
            DecliningPresentationEnvironment(top: top, completesAnyway: true)
        }))
        manager.showConfirmDialog(completion: { events.record(.completion($0, $1)) })
        _ = await waitUntil { events.values.count == 1 }
        try await Task.sleep(nanoseconds: 300_000_000)
        #expect(events.values == [.completion(false, "Failed to present the dialog")])
    }

    /// S-P5, SR-20: a dialog dismissed from outside calls nothing (its methods have no result for
    /// it); the new API reports `dismissedBySystem` (the release watch).
    @Test(.disabled(if: isThreadSanitizerEnabled, "a dismissed alert is not freed in the TSan build (design 6.3.4)"))
    func aDialogDismissedFromOutsideCallsNothingButTheNewAPIIsTold() async throws {
        try await withHostWindow { host in
            let sessions = SessionRecorder()
            let events = MainRecorder<Event>()
            let manager = manager(sessions)
            manager.showConfirmDialog(onConfirm: { _, _, _ in events.record(.button("onConfirm", [])) },
                                      onCancel: { _, _, _ in events.record(.button("onCancel", [])) },
                                      completion: { events.record(.completion($0, $1)) })
            weak let legacyAlert = try await waitShown(sessions, events, count: 1).alert
            host.root.dismiss(animated: false)
            #expect(await waitUntil { legacyAlert == nil }, "the dismissed alert is freed")
            try await Task.sleep(nanoseconds: 300_000_000)
            #expect(events.values == [.completion(true, nil)])

            let results = MainRecorder<Result<DialogAnswer, DialogError>>()
            manager.show(.confirm(title: nil, message: nil), presenter: .foreground) { results.record($0) }
            #expect(await waitUntil { sessions.sessions.count == 2 && sessions.last?.isPresented == true })
            host.root.dismiss(animated: false)
            #expect(await waitUntil { results.values.count == 1 })
            #expect(results.values == [.failure(.dismissedBySystem)])
        }
    }

    // MARK: - The new API through the manager

    @Test func showThroughTheManagerReturnsItsBoxAndCompletesOnce() async throws {
        try await withHostWindow { _ in
            let sessions = SessionRecorder()
            let results = MainRecorder<Result<DialogAnswer, DialogError>>()
            let manager = manager(sessions)
            let given = RequestBox()
            let returned = manager.show(.alert(title: nil, message: nil), presenter: .foreground, requestBox: given) { results.record($0) }
            #expect(returned === given)
            let created = manager.show(.alert(title: nil, message: nil), presenter: .foreground) { results.record($0) }
            #expect(created !== given)
            // A box already used: invalidRequest, the first request goes on.
            manager.show(.alert(title: nil, message: nil), presenter: .foreground, requestBox: given) { results.record($0) }
            #expect(await waitUntil { results.values.count == 1 })
            #expect(results.values == [.failure(.invalidRequest)])
            #expect(await waitUntil { sessions.sessions.count == 2 && sessions.sessions.allSatisfy(\.isPresented) })
            sessions.sessions[1].press(0)
            #expect(await waitUntil { sessions.sessions[0].alert?.presentedViewController == nil })
            sessions.sessions[0].press(0)
            #expect(await waitUntil { results.values.count == 3 })
            try await Task.sleep(nanoseconds: 300_000_000)
            #expect(results.values.count == 3)
            #expect(results.allOnMainThread)
        }
    }

    @Test func foregroundViewControllerFindsTheKeyWindowsTop() async throws {
        try await withHostWindow { host in
            #expect(IosDialogManager.shared.foregroundViewController() === host.root)
            #expect(IosDialogManager.shared.getRootViewController() === host.root)
        }
        await withHostScreen {
            #expect(IosDialogManager.shared.foregroundViewController() == nil)
        }
    }

    // MARK: - UT-11: the async form

    @Test func theAsyncFormReturnsTheAnswer() async throws {
        try await withHostWindow { _ in
            let sessions = SessionRecorder()
            let manager = manager(sessions)
            let answers = MainRecorder<DialogAnswer>()
            let task = Task {
                if let answer = try? await manager.show(.confirm(title: nil, message: nil), presenter: .foreground) {
                    answers.record(answer)
                }
            }
            #expect(await waitUntil { sessions.last?.isPresented == true })
            sessions.last?.press(1)
            #expect(await waitUntil { answers.values.count == 1 })
            await task.value
            #expect(answers.values == [DialogAnswer(button: .cancel, title: "Cancel", input: nil)])
        }
    }

    /// A task cancelled after the button was pressed (before the answer arrived) still returns
    /// the answer: the button closed the request first.
    @Test func theAsyncFormReturnsTheAnswerWhenTheTaskIsCancelledAfterTheButton() async throws {
        try await withHostWindow { _ in
            let sessions = SessionRecorder()
            let manager = manager(sessions)
            let finished = MainRecorder<String>()
            let task = Task {
                do {
                    let answer = try await manager.show(.confirm(title: nil, message: nil), presenter: .foreground)
                    finished.record("answer \(answer.button.logName)")
                } catch {
                    finished.record("\(type(of: error))")
                }
            }
            #expect(await waitUntil { sessions.last?.isPresented == true })
            let session = try #require(sessions.last)
            // The same turn of the main queue: the answer is queued, then the task is cancelled.
            session.press(0)
            task.cancel()
            #expect(await waitUntil { !finished.values.isEmpty })
            await task.value
            #expect(finished.values == ["answer primary"])
            #expect(session.box.outcome?.logName == "completed")
        }
    }

    @Test func theAsyncFormThrowsTheDialogError() async throws {
        await withHostScreen {
            let manager = manager(SessionRecorder())
            await #expect(throws: DialogError.notForeground) {
                try await manager.show(.alert(title: nil, message: nil), presenter: .foreground)
            }
        }
    }

    /// Cancelling the task cancels the request (its dialog is dismissed) and throws
    /// `CancellationError`.
    @Test func cancellingTheTaskCancelsTheRequest() async throws {
        try await withHostWindow { host in
            let sessions = SessionRecorder()
            let manager = manager(sessions)
            let finished = MainRecorder<String>()
            let task = Task {
                do {
                    _ = try await manager.show(.confirm(title: nil, message: nil), presenter: .foreground)
                    finished.record("answer")
                } catch is CancellationError {
                    finished.record("CancellationError")
                } catch {
                    finished.record("\(error)")
                }
            }
            #expect(await waitUntil { sessions.last?.isPresented == true })
            let session = try #require(sessions.last)
            task.cancel()
            let done = await waitUntil(timeout: 5) { !finished.values.isEmpty }
            if !done {
                // Unblock the task so that the test ends.
                session.press(1)
            }
            await task.value
            #expect(finished.values == ["CancellationError"])
            #expect(session.box.outcome.map { "\($0.logName)" } == "canceled")
            #expect(await waitUntil { host.root.presentedViewController == nil }, "the dialog is dismissed")
        }
    }

    @Test func aTaskCancelledBeforeTheCallShowsNothing() async throws {
        try await withHostWindow { host in
            let sessions = SessionRecorder()
            let manager = manager(sessions)
            let finished = MainRecorder<String>()
            let task = Task {
                withUnsafeCurrentTask { $0?.cancel() }
                do {
                    _ = try await manager.show(.alert(title: nil, message: nil), presenter: .foreground)
                    finished.record("answer")
                } catch is CancellationError {
                    finished.record("CancellationError")
                } catch {
                    finished.record("\(error)")
                }
            }
            if !(await waitUntil(timeout: 5) { !finished.values.isEmpty }) {
                // Unblock the task so that the test ends.
                sessions.last?.press(0)
            }
            await task.value
            #expect(finished.values == ["CancellationError"])
            #expect(sessions.sessions.isEmpty)
            #expect(host.root.presentedViewController == nil)
        }
    }
}
