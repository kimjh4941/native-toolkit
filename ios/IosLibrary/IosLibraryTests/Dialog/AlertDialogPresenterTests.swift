//
//  AlertDialogPresenterTests.swift
//  IosLibraryTests
//

import Foundation
import Testing
import UIKit
@testable import IosLibrary

/// UT-08, UT-09, UT-14: `AlertDialogPresenter` on the host app, presenting real alerts.
///
/// A tap is replaced by calling the button's `UIAlertAction` handler (`DialogSession.press`), the
/// same closure UIKit calls. Every test runs inside `withHostScreen` with its own key window.
@MainActor
struct AlertDialogPresenterTests {

    typealias DialogResult = Result<DialogAnswer, DialogError>

    /// Presents `request` through a recording presenter and waits until `present` has finished.
    private func present(
        _ request: DialogRequest,
        on host: HostWindow,
        presenter selection: PresenterSelection = .foreground,
        box: RequestBox = RequestBox(),
        sessions: SessionRecorder = SessionRecorder(),
        results: MainRecorder<DialogResult>
    ) async throws -> DialogSession {
        let presenter = AlertDialogPresenter.recording(into: sessions)
        let before = sessions.sessions.count
        presenter.present(request, presenter: selection, box: box) { results.record($0) }
        #expect(await waitUntil { sessions.sessions.count > before && sessions.last?.isPresented == true },
                "the dialog must be presented")
        return try #require(sessions.last)
    }

    // MARK: - UT-08: building each request

    @Test func eachRequestBuildsItsButtonsAndFields() async throws {
        try await withHostWindow { host in
            let cases: [(DialogRequest, [String?], [UIAlertAction.Style], Int, UIAlertController.Style)] = [
                (.alert(title: "T", message: "M"), ["OK"], [.default], 0, .alert),
                (.confirm(title: "T", message: "M", confirmTitle: "Yes", cancelTitle: "No"), ["Yes", "No"], [.default, .cancel], 0, .alert),
                (.destructive(title: "T", message: "M"), ["Delete", "Cancel"], [.destructive, .cancel], 0, .alert),
                (.actionSheet(title: "T", message: "M", options: ["A", "B"]), ["A", "B", "Cancel"], [.default, .default, .cancel], 0, .actionSheet),
                (.textInput(title: "T", message: "M", placeholder: "P"), ["OK", "Cancel"], [.default, .cancel], 1, .alert),
                (.login(title: "T", message: "M"), ["Login", "Cancel"], [.default, .cancel], 2, .alert),
            ]
            for (request, titles, styles, fieldCount, style) in cases {
                let results = MainRecorder<DialogResult>()
                let session = try await present(request, on: host, results: results)
                let alert = try #require(session.alert)
                #expect(alert.title == "T")
                #expect(alert.message == "M")
                #expect(alert.preferredStyle == style, "\(request.kindName)")
                #expect(alert.actions.map(\.title) == titles, "\(request.kindName)")
                #expect(alert.actions.map(\.style) == styles, "\(request.kindName)")
                #expect((alert.textFields ?? []).count == fieldCount, "\(request.kindName)")
                // Close it with the last button (cancel, or the only one).
                session.press(titles.count - 1)
                #expect(await waitUntil { host.root.presentedViewController == nil })
                #expect(results.values.count <= 1)
                _ = await waitUntil { results.values.count == 1 }
                #expect(results.values.count == 1)
            }
        }
    }

    @Test func theFieldsOfTextInputAndLogin() async throws {
        try await withHostWindow { host in
            let results = MainRecorder<DialogResult>()
            let text = try await present(.textInput(title: nil, message: nil, placeholder: "Your name"), on: host, results: results)
            let textField = try #require(text.alert?.textFields?.first)
            #expect(textField.placeholder == "Your name")
            #expect(!textField.isSecureTextEntry)
            text.press(1)
            _ = await waitUntil { host.root.presentedViewController == nil }

            let login = try await present(.login(title: nil, message: nil, usernamePlaceholder: "U", passwordPlaceholder: "P"),
                                          on: host, results: results)
            let fields = try #require(login.alert?.textFields)
            #expect(fields.map(\.placeholder) == ["U", "P"])
            #expect(fields.map(\.isSecureTextEntry) == [false, true])
            #expect(fields.map(\.textContentType) == [.username, .password])
            login.press(1)
            _ = await waitUntil { results.values.count == 2 }
        }
    }

    @Test func thePrimaryButtonReportsTheInputAndCancelReportsNone() async throws {
        try await withHostWindow { host in
            let results = MainRecorder<DialogResult>()

            let text = try await present(.textInput(title: nil, message: nil), on: host, results: results)
            text.alert?.textFields?[0].text = "Taro 太郎"
            text.press(0)
            _ = await waitUntil { results.values.count == 1 }
            #expect(results.values.last == .success(DialogAnswer(button: .primary, title: "OK", input: .text("Taro 太郎"))))

            let cancelled = try await present(.textInput(title: nil, message: nil), on: host, results: results)
            cancelled.alert?.textFields?[0].text = "typed"
            cancelled.press(1)
            _ = await waitUntil { results.values.count == 2 }
            #expect(results.values.last == .success(DialogAnswer(button: .cancel, title: "Cancel", input: nil)))

            let login = try await present(.login(title: nil, message: nil), on: host, results: results)
            login.alert?.textFields?[0].text = "taro"
            login.alert?.textFields?[1].text = "secret1"
            login.press(0)
            _ = await waitUntil { results.values.count == 3 }
            #expect(results.values.last == .success(DialogAnswer(button: .primary, title: "Login",
                                                                 input: .login(username: "taro", password: "secret1"))))

            let loginCancelled = try await present(.login(title: nil, message: nil), on: host, results: results)
            loginCancelled.alert?.textFields?[0].text = "taro"
            loginCancelled.alert?.textFields?[1].text = "secret1"
            loginCancelled.press(1)
            _ = await waitUntil { results.values.count == 4 }
            #expect(results.values.last == .success(DialogAnswer(button: .cancel, title: "Cancel", input: nil)))

            let sheet = try await present(.actionSheet(title: nil, message: nil, options: ["A", "B", "C"]), on: host, results: results)
            sheet.press(2)
            _ = await waitUntil { results.values.count == 5 }
            #expect(results.values.last == .success(DialogAnswer(button: .option(index: 2), title: "C", input: nil)))

            let destructive = try await present(.destructive(title: nil, message: nil), on: host, results: results)
            destructive.press(0)
            _ = await waitUntil { results.values.count == 6 }
            #expect(results.values.last == .success(DialogAnswer(button: .destructive, title: "Delete", input: nil)))
            #expect(results.allOnMainThread)
        }
    }

    @Test func thePrimaryButtonFollowsTheFieldsWhenInputIsRequired() async throws {
        try await withHostWindow { host in
            let results = MainRecorder<DialogResult>()
            let login = try await present(.login(title: nil, message: nil, enableLoginWhenEmpty: false), on: host, results: results)
            let fields = try #require(login.alert?.textFields)
            let loginAction = try #require(login.alert?.actions.first)
            #expect(!loginAction.isEnabled)
            fields[0].text = "taro"
            NotificationCenter.default.post(name: UITextField.textDidChangeNotification, object: fields[0])
            #expect(!loginAction.isEnabled, "only the username")
            fields[1].text = "pw"
            NotificationCenter.default.post(name: UITextField.textDidChangeNotification, object: fields[1])
            #expect(loginAction.isEnabled, "both fields")
            fields[0].text = ""
            NotificationCenter.default.post(name: UITextField.textDidChangeNotification, object: fields[0])
            #expect(!loginAction.isEnabled, "the username deleted again")
            login.press(1)

            let text = try await present(.textInput(title: nil, message: nil), on: host, results: results)
            #expect(text.alert?.actions.first?.isEnabled == true, "enabled by default")
            #expect(text.observers.isEmpty, "no observer without validation")
            text.press(1)
            _ = await waitUntil { results.values.count == 2 }

            let required = try await present(.textInput(title: nil, message: nil, enableConfirmWhenEmpty: false), on: host,
                                             results: results)
            let field = try #require(required.alert?.textFields?.first)
            let confirm = try #require(required.alert?.actions.first)
            #expect(!confirm.isEnabled, "disabled while the field is empty")
            #expect(!required.observers.isEmpty, "an observer for the validation")
            field.text = "a"
            NotificationCenter.default.post(name: UITextField.textDidChangeNotification, object: field)
            #expect(confirm.isEnabled, "enabled with text")
            field.text = ""
            NotificationCenter.default.post(name: UITextField.textDidChangeNotification, object: field)
            #expect(!confirm.isEnabled, "disabled again when the text is deleted")
            required.press(1)
            _ = await waitUntil { results.values.count == 3 }
        }
    }

    /// P1-13 / S-P6: an action sheet's popover is anchored at the centre of the presenting view,
    /// on every device where it has a popover (iPad, and iPhone with iOS 26).
    @Test func anActionSheetIsAnchoredAtTheCentreOfThePresentingView() async throws {
        try await withHostWindow { host in
            let results = MainRecorder<DialogResult>()
            let session = try await present(.actionSheet(title: nil, message: nil, options: ["A"]), on: host, results: results)
            let alert = try #require(session.alert)
            if UIDevice.current.userInterfaceIdiom == .pad {
                #expect(alert.popoverPresentationController != nil, "an action sheet is a popover on iPad")
            }
            if let popover = alert.popoverPresentationController {
                #expect(popover.sourceView === host.root.view)
                let bounds = host.root.view.bounds
                #expect(popover.sourceRect == CGRect(x: bounds.midX, y: bounds.midY, width: 0, height: 0))
            }
            session.press(1)
            _ = await waitUntil { results.values.count == 1 }
        }
    }

    /// `.viewController(_:)`: the dialog is presented from the view controller the closure
    /// returns (here in a second window, not the key window `.foreground` would use), and a
    /// closure that returns `nil` ends the request as `notForeground` without presenting.
    @Test func theViewControllerSelectionPresentsFromTheReturnedViewController() async throws {
        try await withHostWindow { host in
            let scene = try #require(host.window.windowScene)
            let other = UIWindow(windowScene: scene)
            let otherRoot = UIViewController()
            other.rootViewController = otherRoot
            other.isHidden = false
            defer {
                other.isHidden = true
                other.rootViewController = nil
            }
            #expect(!other.isKeyWindow, "the second window must not be the key window")

            let results = MainRecorder<DialogResult>()
            let session = try await present(.alert(title: nil, message: nil), on: host,
                                            presenter: .viewController { otherRoot }, results: results)
            #expect(session.alert?.presentingViewController === otherRoot)
            #expect(host.root.presentedViewController == nil, "not presented in the key window")
            session.press(0)
            _ = await waitUntil { results.values.count == 1 }

            let sessions = SessionRecorder()
            AlertDialogPresenter.recording(into: sessions).present(.alert(title: nil, message: nil),
                                                                   presenter: .viewController { nil }, box: RequestBox()) {
                results.record($0)
            }
            _ = await waitUntil { results.values.count == 2 }
            #expect(results.values.last == .failure(.notForeground))
            try await Task.sleep(nanoseconds: 200_000_000)
            #expect(host.root.presentedViewController == nil)
            #expect(sessions.sessions.allSatisfy { $0.alert?.presentingViewController == nil }, "nothing presented")
        }
    }

    @Test func withoutAKeyWindowNothingIsPresented() async {
        await withHostScreen {
            let results = MainRecorder<DialogResult>()
            let sessions = SessionRecorder()
            let presenter = AlertDialogPresenter.recording(into: sessions)
            presenter.present(.alert(title: nil, message: nil), presenter: .foreground, box: RequestBox()) { results.record($0) }
            presenter.present(.alert(title: nil, message: nil), presenter: .firstActiveScene, box: RequestBox()) { results.record($0) }
            _ = await waitUntil { results.values.count == 2 }
            #expect(results.values == [.failure(.notForeground), .failure(.notForeground)])
        }
    }

    @Test func aBoxAlreadyAttachedEndsAsInvalidWithoutPresenting() async throws {
        try await withHostWindow { host in
            let results = MainRecorder<DialogResult>()
            let sessions = SessionRecorder()
            let box = RequestBox()
            #expect(box.attach { _ in })
            AlertDialogPresenter.recording(into: sessions).present(.alert(title: nil, message: nil), presenter: .foreground, box: box) {
                results.record($0)
            }
            _ = await waitUntil { results.values.count == 1 }
            #expect(results.values == [.failure(.invalidRequest)])
            #expect(host.root.presentedViewController == nil)
            #expect(sessions.sessions.isEmpty, "no alert is built")
        }
    }

    // MARK: - UT-09: cancelling

    @Test func cancelledBeforeItStartsItShowsNothing() async throws {
        try await withHostWindow { host in
            let results = MainRecorder<DialogResult>()
            let sessions = SessionRecorder()
            let box = RequestBox()
            IosDialogManager.shared.cancel(box)
            AlertDialogPresenter.recording(into: sessions).present(.alert(title: nil, message: nil), presenter: .foreground, box: box) {
                results.record($0)
            }
            _ = await waitUntil { results.values.count == 1 }
            #expect(results.values == [.failure(.canceled)])
            #expect(sessions.sessions.isEmpty)
            #expect(host.root.presentedViewController == nil)
        }
    }

    /// R4-2: a cancellation while the alert is being presented dismisses it in `present`'s
    /// completion. MS-01 found that this UIKit does not ignore a dismiss during the presentation
    /// (it closes the alert after the presentation), so dismissing at once would give the same
    /// result here: that is why mutation M13 (dismiss at once) is not caught. The wait stays for
    /// the UIKit versions R4-2 expects to ignore it.
    @Test func cancelledWhileBeingPresentedItIsDismissedOncePresented() async throws {
        try await withHostWindow { host in
            let results = MainRecorder<DialogResult>()
            let sessions = SessionRecorder()
            let box = RequestBox()
            AlertDialogPresenter.recording(into: sessions).present(.alert(title: nil, message: nil), presenter: .foreground, box: box) {
                results.record($0)
            }
            #expect(await waitUntil(timeout: 5) { host.presentedAlert != nil })
            let session = try #require(sessions.last)
            try #require(!session.isPresented, "the cancellation must come before present's completion")
            IosDialogManager.shared.cancel(box)
            _ = await waitUntil { results.values.count == 1 }
            #expect(results.values == [.failure(.canceled)])
            #expect(await waitUntil { host.root.presentedViewController == nil }, "dismissed after present's completion")
            #expect(session.isPresented)
        }
    }

    @Test func cancelledWhileShownItIsDismissed() async throws {
        try await withHostWindow { host in
            let results = MainRecorder<DialogResult>()
            let box = RequestBox()
            _ = try await present(.confirm(title: nil, message: nil), on: host, box: box, results: results)
            // From a background thread: closes at once, dismisses on main.
            await Task.detached { IosDialogManager.shared.cancel(box) }.value
            #expect(box.isClosed)
            _ = await waitUntil { results.values.count == 1 }
            #expect(results.values == [.failure(.canceled)])
            #expect(await waitUntil { host.root.presentedViewController == nil })
        }
    }

    /// P1-24: with another view controller over the dialog, cancelling ends the request but leaves
    /// both on screen; the dialog's buttons then do nothing.
    @Test func cancelledUnderAnotherViewControllerItStays() async throws {
        try await withHostWindow { host in
            let results = MainRecorder<DialogResult>()
            let box = RequestBox()
            let session = try await present(.confirm(title: nil, message: nil), on: host, box: box, results: results)
            let alert = try #require(session.alert)
            let cover = UIViewController()
            alert.present(cover, animated: false)
            #expect(await waitUntil { alert.presentedViewController === cover })

            IosDialogManager.shared.cancel(box)
            _ = await waitUntil { results.values.count == 1 }
            #expect(results.values == [.failure(.canceled)])
            // A dismiss of the covered dialog would remove the cover within about 0.5 s.
            try await Task.sleep(nanoseconds: 1_500_000_000)
            #expect(host.presentedChain.map { ObjectIdentifier($0) } == [ObjectIdentifier(alert), ObjectIdentifier(cover)],
                    "the dialog and the view controller over it stay")

            session.press(0, dismissing: false)
            await drainMainQueue(times: 2)
            #expect(results.values.count == 1, "a button of a cancelled dialog does nothing")
        }
    }

    @Test func cancellingAfterTheAnswerChangesNothing() async throws {
        try await withHostWindow { host in
            let results = MainRecorder<DialogResult>()
            let box = RequestBox()
            let session = try await present(.alert(title: nil, message: nil), on: host, box: box, results: results)
            session.press(0)
            _ = await waitUntil { results.values.count == 1 }
            IosDialogManager.shared.cancel(box)
            await drainMainQueue(times: 2)
            #expect(results.values == [.success(DialogAnswer(button: .primary, title: "OK", input: nil))])
        }
    }

    // MARK: - UT-14: nothing keeps the alert alive

    /// The alert, its button handlers and its text-field observers do not keep one another
    /// alive: after the answer and the dismissal the alert is freed and the observers are gone.
    @Test(.disabled(if: isThreadSanitizerEnabled, "a dismissed alert is not freed in the TSan build (design 6.3.4)"))
    func theAlertAndItsObserversAreFreedAfterItCloses() async throws {
        try await withHostWindow { host in
            for (index, closing) in ["button", "cancel"].enumerated() {
                let results = MainRecorder<DialogResult>()
                let box = RequestBox()
                weak var alert: UIAlertController?
                weak var observer: AnyObject?
                do {
                    let session = try await present(.login(title: nil, message: nil, enableLoginWhenEmpty: false), on: host, box: box,
                                                    results: results)
                    alert = session.alert
                    #expect(session.observers.count == 2, "one observer per field")
                    observer = session.observers.first as AnyObject?
                    if closing == "button" {
                        session.alert?.textFields?[0].text = "u"
                        session.alert?.textFields?[1].text = "p"
                        session.press(0)
                    } else {
                        IosDialogManager.shared.cancel(box)
                    }
                }
                _ = await waitUntil { results.values.count == 1 }
                #expect(await waitUntil { host.root.presentedViewController == nil }, "\(closing)")
                #expect(await waitUntil(timeout: 5) { alert == nil }, "the alert must be freed after \(closing) (\(index))")
                #expect(await waitUntil(timeout: 2) { observer == nil }, "the observers must be removed after \(closing)")
            }
        }
    }

    // MARK: - MS-01 on the host app

    /// MS-01 (G-4): UIKit sets `presentingViewController` inside `present` (the supplement of
    /// part 1, 5.13.1 relies on it), and declines a second presentation on a view controller that
    /// is already presenting without calling its completion (so the supplement is what reports
    /// it). Whether a dismiss during the presentation is ignored is not asserted: the library
    /// dismisses a cancelled dialog only after `present`'s completion either way (R4-2).
    @Test func uikitBehavesAsThePresentationProcedureAssumes() async throws {
        try await withHostWindow { host in
            let first = UIAlertController(title: "first", message: nil, preferredStyle: .alert)
            first.addAction(UIAlertAction(title: "OK", style: .default))
            let firstDone = MainRecorder<Bool>()
            host.root.present(first, animated: true) { firstDone.record(true) }
            #expect(first.presentingViewController === host.root, "set inside present")
            #expect(first.isBeingPresented)
            #expect(host.root.transitionCoordinator != nil, "a coordinator to wait for")

            let second = UIAlertController(title: "second", message: nil, preferredStyle: .alert)
            let secondDone = MainRecorder<Bool>()
            host.root.present(second, animated: true) { secondDone.record(true) }
            #expect(second.presentingViewController == nil, "declined: the root is already presenting")

            #expect(await waitUntil { firstDone.values.count == 1 })
            try await Task.sleep(nanoseconds: 500_000_000)
            #expect(secondDone.values.isEmpty, "no completion for a declined presentation")
            #expect(host.presentedAlert === first)
        }
    }

    /// P1-12 on the host app: two requests in the same turn of the main queue, with
    /// `.foreground`, are both shown: the second waits for the first's presentation and is
    /// presented over it.
    @Test func twoRequestsInTheSameTurnAreBothShown() async throws {
        try await withHostWindow { host in
            let results = MainRecorder<DialogResult>()
            let sessions = SessionRecorder()
            let presenter = AlertDialogPresenter.recording(into: sessions)
            presenter.present(.alert(title: "1", message: nil), presenter: .foreground, box: RequestBox()) { results.record($0) }
            presenter.present(.alert(title: "2", message: nil), presenter: .foreground, box: RequestBox()) { results.record($0) }
            #expect(await waitUntil { sessions.sessions.count == 2 && sessions.sessions.allSatisfy(\.isPresented) },
                    "both are presented")
            #expect(host.presentedChain.compactMap { ($0 as? UIAlertController)?.title } == ["1", "2"], "the second over the first")
            sessions.sessions[1].press(0)
            #expect(await waitUntil { host.presentedChain.count == 1 })
            sessions.sessions[0].press(0)
            _ = await waitUntil { results.values.count == 2 }
            #expect(results.values == [.success(DialogAnswer(button: .primary, title: "OK", input: nil)),
                                       .success(DialogAnswer(button: .primary, title: "OK", input: nil))])
        }
    }
}
