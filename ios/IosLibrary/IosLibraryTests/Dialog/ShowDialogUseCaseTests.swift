//
//  ShowDialogUseCaseTests.swift
//  IosLibraryTests
//

import Foundation
import Synchronization
import Testing
@testable import IosLibrary

/// A `DialogPresenting` that records its calls and answers as told.
final class MockDialogPresenting: DialogPresenting {
    struct Call: Sendable {
        let request: DialogRequest
        let presenterName: String
        let box: RequestBox
    }

    private let calls = Mutex<[Call]>([])
    private let stubbed: Result<DialogAnswer, DialogError>?

    /// - Parameter stubbedResult: Delivered on the main queue after each call; `nil` delivers
    ///   nothing.
    init(stubbedResult: Result<DialogAnswer, DialogError>? = nil) {
        stubbed = stubbedResult
    }

    var presentCallCount: Int { calls.withLock { $0.count } }
    var lastCall: Call? { calls.withLock { $0.last } }

    func present(_ request: DialogRequest, presenter: PresenterSelection, box: RequestBox,
                 completion: @escaping @MainActor @Sendable (Result<DialogAnswer, DialogError>) -> Void) {
        calls.withLock { $0.append(Call(request: request, presenterName: presenter.logName, box: box)) }
        guard let stubbed else { return }
        DispatchQueue.main.async { MainActor.assumeIsolated { completion(stubbed) } }
    }
}

/// UT-07: the request type's defaults and texts, and `ShowDialogUseCase`.
struct DialogRequestTests {

    @Test func defaultTextsAreTheOnesOfTheShowMethods() {
        #expect(DialogRequest.alert(title: nil, message: nil)
                == .alert(title: nil, message: nil, buttonTitle: "OK"))
        #expect(DialogRequest.confirm(title: nil, message: nil)
                == .confirm(title: nil, message: nil, confirmTitle: "OK", cancelTitle: "Cancel"))
        #expect(DialogRequest.destructive(title: nil, message: nil)
                == .destructive(title: nil, message: nil, destructiveTitle: "Delete", cancelTitle: "Cancel"))
        #expect(DialogRequest.actionSheet(title: nil, message: nil, options: ["A"])
                == .actionSheet(title: nil, message: nil, options: ["A"], cancelTitle: "Cancel"))
        #expect(DialogRequest.textInput(title: nil, message: nil)
                == .textInput(title: nil, message: nil, placeholder: nil, confirmTitle: "OK", cancelTitle: "Cancel",
                              enableConfirmWhenEmpty: true))
        #expect(DialogRequest.login(title: nil, message: nil)
                == .login(title: nil, message: nil, usernamePlaceholder: "Username", passwordPlaceholder: "Password",
                          loginTitle: "Login", cancelTitle: "Cancel", enableLoginWhenEmpty: true))
    }

    @Test func theInputDescriptionShowsOnlyLengths() {
        let text = DialogInput.text("hello-secret")
        let login = DialogInput.login(username: "taro", password: "pässword")
        #expect(text.description == "text(length: 12)")
        #expect(login.description == "login(username: length 4, password: length 9)")
        #expect(String(describing: text) == text.description)
        #expect(String(reflecting: login) == login.description)
        #expect(!"\(DialogAnswer(button: .primary, title: "OK", input: login))".contains("pässword"))
        // Equality compares the values.
        #expect(DialogInput.text("a") == .text("a"))
        #expect(DialogInput.text("a") != .text("b"))
        #expect(DialogInput.login(username: "a", password: "b") != .login(username: "a", password: "c"))
    }

    @Test func errorTextsAreFixed() {
        let expected: [(DialogError, String)] = [
            (.canceled, "The dialog was canceled."),
            (.dismissedBySystem, "The dialog was dismissed without an answer."),
            (.notForeground, "No view controller in the foreground to present the dialog from."),
            (.presentationFailed, "Failed to present the dialog."),
            (.invalidRequest, "The request box is already used by another request."),
        ]
        for (error, text) in expected {
            #expect(error.errorDescription == text)
            #expect(error.localizedDescription == text)
        }
    }
}

/// Which thread each call came on.
final class ThreadLog: Sendable {
    private let calls = Mutex<[Bool]>([])
    func record() { calls.withLock { $0.append(Thread.isMainThread) } }
    var isMainThread: [Bool] { calls.withLock { $0 } }
}

struct ShowDialogUseCaseTests {

    @Test func passesTheRequestThePresenterAndTheBoxToThePort() async {
        let port = MockDialogPresenting()
        let box = RequestBox()
        let request = DialogRequest.textInput(title: "t", message: "m", placeholder: "p")
        ShowDialogUseCase(presenter: port).execute(request, presenter: .foreground, box: box) { _ in }
        #expect(port.presentCallCount == 1)
        #expect(port.lastCall?.request == request)
        #expect(port.lastCall?.presenterName == "foreground")
        #expect(port.lastCall?.box === box)
    }

    @Test func theResultOfThePortReachesTheCompletion() async {
        let answer = DialogAnswer(button: .option(index: 2), title: "C", input: nil)
        let port = MockDialogPresenting(stubbedResult: .success(answer))
        let received = await withCheckedContinuation { (continuation: CheckedContinuation<Result<DialogAnswer, DialogError>, Never>) in
            ShowDialogUseCase(presenter: port).execute(.alert(title: nil, message: nil), presenter: .firstActiveScene, box: RequestBox()) {
                continuation.resume(returning: $0)
            }
        }
        #expect(received == .success(answer))
    }

    @Test func aBoxThatAnotherRequestUsesIsRefusedWithoutCallingThePort() async {
        let port = MockDialogPresenting()
        let box = RequestBox()
        #expect(box.attach { _ in })  // the first request
        let onMain = ThreadLog()
        let recorder = await MainActor.run { MainRecorder<Result<DialogAnswer, DialogError>>() }
        ShowDialogUseCase(presenter: port).execute(.alert(title: nil, message: nil), presenter: .foreground, box: box) {
            onMain.record()
            recorder.record($0)
        }
        // Bounded: a use case that calls the port instead (the mock never answers) must fail here,
        // not hang.
        #expect(await waitUntil(timeout: 5) { recorder.values.count == 1 })
        #expect(await recorder.values == [.failure(.invalidRequest)])
        #expect(onMain.isMainThread == [true])
        #expect(port.presentCallCount == 0)
        // The first request's box is not touched.
        #expect(!box.isClosed)
    }

    @Test func aBoxClosedBeforeItsRequestStartedIsNotRefused() {
        let port = MockDialogPresenting()
        let box = RequestBox()
        box.close(.canceled)
        ShowDialogUseCase(presenter: port).execute(.alert(title: nil, message: nil), presenter: .foreground, box: box) { _ in }
        #expect(port.presentCallCount == 1)
    }

    @Test func theRefusalIsNeverDeliveredInsideTheCall() async {
        let box = RequestBox()
        #expect(box.attach { _ in })
        let recorder = await MainActor.run { MainRecorder<Result<DialogAnswer, DialogError>>() }
        let deliveredInside = await MainActor.run { () -> Bool in
            ShowDialogUseCase(presenter: MockDialogPresenting()).execute(.alert(title: nil, message: nil), presenter: .foreground, box: box) {
                recorder.record($0)
            }
            return !recorder.values.isEmpty
        }
        #expect(!deliveredInside)
        await drainMainQueue()
        #expect(await recorder.values == [.failure(.invalidRequest)])
    }
}
