//
//  DialogEntryTests.swift
//  IosLibraryCApiTests
//

import IosLibrary
import XCTest
@testable import IosLibraryCApi

/// Dialog.h through C, without showing anything: what is rejected at the entry, what is cancelled before the
/// first main turn (part 2, 5.3 and 12.1), and the readers. These tests also run on the private device under
/// ASan (12.2), and their host must not show a dialog there: **an accepted request is cancelled in the same
/// main turn, so that it never starts**. Showing a dialog is in the UI tests.
final class DialogEntryTests: ClipboardTestCase {
    private let cancelValue: Int32 = 6
    private let invalidParameter: Int32 = 1
    private let tooFar = Int(bitPattern: UInt.max)

    private struct Show: @unchecked Sendable {
        let name: String
        let call: (_ callback: ntk_dialog_result_fn?, _ userData: UnsafeMutableRawPointer?, _ release: ntk_release_fn?, _ id: UnsafeMutablePointer<UInt64>?) -> Int32
    }

    /// Each show function with a valid zero-filled request.
    private func shows() -> [Show] {
        func filled<Request>(_ request: Request) -> UnsafePointer<Request> {
            var value = request
            withUnsafeMutableBytes(of: &value) { $0.storeBytes(of: UInt32(MemoryLayout<Request>.size), as: UInt32.self) }
            return array([value])
        }
        let alert = filled(ntk_dialog_alert_request())
        let confirm = filled(ntk_dialog_confirm_request())
        let destructive = filled(ntk_dialog_destructive_request())
        let sheet = filled(ntk_dialog_action_sheet_request())
        let textInput = filled(ntk_dialog_text_input_request())
        let login = filled(ntk_dialog_login_request())
        return [
            Show(name: "alert") { ntk_dialog_show_alert_async(alert, $0, $1, $2, $3) },
            Show(name: "confirm") { ntk_dialog_show_confirm_async(confirm, $0, $1, $2, $3) },
            Show(name: "destructive") { ntk_dialog_show_destructive_async(destructive, $0, $1, $2, $3) },
            Show(name: "actionSheet") { ntk_dialog_show_action_sheet_async(sheet, $0, $1, $2, $3) },
            Show(name: "textInput") { ntk_dialog_show_text_input_async(textInput, $0, $1, $2, $3) },
            Show(name: "login") { ntk_dialog_show_login_async(login, $0, $1, $2, $3) },
        ]
    }

    /// Each show function with NULL for its request.
    private func showsOfNull() -> [Show] {
        [
            Show(name: "alert") { ntk_dialog_show_alert_async(nil, $0, $1, $2, $3) },
            Show(name: "confirm") { ntk_dialog_show_confirm_async(nil, $0, $1, $2, $3) },
            Show(name: "destructive") { ntk_dialog_show_destructive_async(nil, $0, $1, $2, $3) },
            Show(name: "actionSheet") { ntk_dialog_show_action_sheet_async(nil, $0, $1, $2, $3) },
            Show(name: "textInput") { ntk_dialog_show_text_input_async(nil, $0, $1, $2, $3) },
            Show(name: "login") { ntk_dialog_show_login_async(nil, $0, $1, $2, $3) },
        ]
    }

    // MARK: - Rejected

    private func assertRejected(_ show: Show, callback: ntk_dialog_result_fn?, file: StaticString = #filePath, line: UInt = #line) {
        let recorder = ClipboardRecorder()
        var requestID: UInt64 = 77
        XCTAssertEqual(show.call(callback, recorder.userData, recordRelease, &requestID), invalidParameter, show.name, file: file, line: line)
        XCTAssertEqual(requestID, 77, "the value output is left alone: \(show.name)", file: file, line: line)
        XCTAssertEqual(recorder.releases, [true], show.name, file: file, line: line)
        runMainQueue(file: file, line: line)
        XCTAssertEqual(recorder.calls, ["release"], show.name, file: file, line: line)
    }

    func testANullCallbackIsRejected() {
        for show in shows() {
            assertRejected(show, callback: nil)
        }
    }

    func testANullRequestIsRejected() {
        for show in showsOfNull() {
            assertRejected(show, callback: recordLoad)
        }
    }

    func testARejectionWithoutAReleaseIsFine() {
        for show in shows() {
            XCTAssertEqual(show.call(nil, nil, nil, nil), invalidParameter, show.name)
        }
    }

    func testARejectionOffTheMainThreadReleasesOnThatThread() {
        let table = shows()
        for index in table.indices {
            let show = table[index]
            let recorder = ClipboardRecorder()
            XCTAssertEqual(onAnotherThread { show.call(nil, recorder.userData, recordRelease, nil) }, invalidParameter, show.name)
            XCTAssertEqual(recorder.releases, [false], show.name)
        }
    }

    func testTheSystemCodeAfterARejectionIsZero() {
        XCTAssertEqual(ntk_dialog_show_alert_async(nil, recordLoad, nil, nil, nil), invalidParameter)
        XCTAssertEqual(ntk_last_system_code(), 0)
    }

    // MARK: - Cancelled before the first main turn: nothing is shown

    func testACancelBeforeTheFirstMainTurnCompletesEachKindAsCanceled() {
        let before = Registry.requestCount
        for show in shows() {
            let recorder = ClipboardRecorder()
            var requestID: UInt64 = 0
            XCTAssertEqual(show.call(recordLoad, recorder.userData, recordRelease, &requestID), ClipboardErrorValue.none, show.name)
            XCTAssertNotEqual(requestID, 0, show.name)
            XCTAssertEqual(Registry.requestCount, before + 1, show.name)
            XCTAssertEqual(ntk_dialog_cancel(requestID), ClipboardErrorValue.none, show.name)
            recorder.markReturned()
            XCTAssertEqual(recorder.calls, [], "nothing runs inside the calls: \(show.name)")

            let result = finished(recorder)

            XCTAssertEqual(result?.error, cancelValue, show.name)
            XCTAssertEqual(result?.requestID, requestID, show.name)
            XCTAssertNil(result?.handle, show.name)
            XCTAssertEqual(result?.afterReturn, true, show.name)
            XCTAssertEqual(Registry.requestCount, before, show.name)
        }
    }

    /// With the main thread stopped: both return, and the release is on the main thread.
    func testShowingAndCancellingOffTheMainThreadDoNotWaitForIt() {
        let table = shows()
        for index in table.indices {
            let show = table[index]
            let recorder = ClipboardRecorder()
            let id = onAnotherThread { () -> UInt64 in
                var requestID: UInt64 = 0
                guard show.call(recordLoad, recorder.userData, recordRelease, &requestID) == 0 else { return 0 }
                _ = ntk_dialog_cancel(requestID)
                return requestID
            }
            XCTAssertNotEqual(id ?? 0, 0, show.name)
            XCTAssertEqual(recorder.calls, [], show.name)
            XCTAssertEqual(finished(recorder)?.error, cancelValue, show.name)
        }
    }

    func testAcceptedWithoutARelease() {
        let recorder = ClipboardRecorder()
        var requestID: UInt64 = 0
        XCTAssertEqual(shows()[0].call(recordLoad, recorder.userData, nil, &requestID), ClipboardErrorValue.none)
        XCTAssertEqual(ntk_dialog_cancel(requestID), ClipboardErrorValue.none)
        spin(5) { !recorder.completions.isEmpty }
        XCTAssertEqual(recorder.calls, ["completion"])
    }

    func testIdsThatAreNotARunningRequestDoNothing() {
        XCTAssertEqual(ntk_dialog_cancel(0), ClipboardErrorValue.none)
        XCTAssertEqual(ntk_dialog_cancel(UInt64.max), ClipboardErrorValue.none)

        let recorder = ClipboardRecorder()
        var requestID: UInt64 = 0
        XCTAssertEqual(shows()[0].call(recordLoad, recorder.userData, recordRelease, &requestID), ClipboardErrorValue.none)
        XCTAssertEqual(ntk_dialog_cancel(requestID), ClipboardErrorValue.none)
        XCTAssertEqual(ntk_dialog_cancel(requestID), ClipboardErrorValue.none, "a second time")
        finished(recorder)
        XCTAssertEqual(ntk_dialog_cancel(requestID), ClipboardErrorValue.none, "a finished one")
        spin(0.1)
        XCTAssertEqual(recorder.calls, ["completion", "release"])
    }

    /// A Clipboard cancel does not end a Dialog request, nor the other way.
    func testTheCancelOfTheOtherFeatureDoesNothing() {
        let recorder = ClipboardRecorder()
        var requestID: UInt64 = 0
        XCTAssertEqual(shows()[0].call(recordLoad, recorder.userData, recordRelease, &requestID), ClipboardErrorValue.none)
        XCTAssertEqual(ntk_clipboard_cancel_load(requestID), ClipboardErrorValue.none)
        XCTAssertEqual(ntk_dialog_cancel(requestID), ClipboardErrorValue.none, "now it is the right one, and it is still there")
        XCTAssertEqual(finished(recorder)?.error, cancelValue)

        let scope = makeNamedPasteboard()
        var scopeValue = scope
        let load = ClipboardRecorder()
        var loadID: UInt64 = 0
        XCTAssertEqual(ntk_clipboard_load_item_async(0, nil, &scopeValue, recordLoad, load.userData, recordRelease, &loadID), ClipboardErrorValue.none)
        XCTAssertEqual(ntk_dialog_cancel(loadID), ClipboardErrorValue.none)
        XCTAssertEqual(finished(load)?.error, ClipboardErrorValue.noMatchingItem, "the load was not cancelled")
    }

    // MARK: - The completion, from the receiver (no dialog)

    /// What the library's result becomes: a registration made here, which never started anything, is given each
    /// outcome through `finish`, as the manager's completion does. No dialog is involved.
    private func completion(of outcome: Result<DialogAnswer, DialogError>, file: StaticString = #filePath, line: UInt = #line) -> ClipboardRecorder.Completion? {
        let recorder = ClipboardRecorder()
        let registration = Registration<ntk_dialog_result_fn>(callback: recordLoad, userData: recorder.userData, release: recordRelease,
                                                              cancellable: nil, canceled: nil, onRemoval: nil)
        DialogReceiver.finish(registration, outcome)
        XCTAssertEqual(recorder.calls, ["completion", "release"], file: file, line: line)
        XCTAssertEqual(recorder.completions.first?.requestID, registration.id, file: file, line: line)
        return recorder.completions.first
    }

    func testEachFailureReachesTheCallbackWithNoResult() {
        for (failure, value) in [(DialogError.dismissedBySystem, Int32(7)), (.notForeground, 8), (.presentationFailed, 10), (.canceled, 6), (.invalidRequest, 1)] {
            let result = completion(of: .failure(failure))
            XCTAssertEqual(result?.error, value, "\(failure)")
            XCTAssertNil(result?.handle, "\(failure)")
        }
    }

    func testAnAnswerReachesTheCallbackAsAHandle() {
        let result = completion(of: .success(DialogAnswer(button: .option(index: 2), title: "Beta", input: nil)))
        XCTAssertEqual(result?.error, ClipboardErrorValue.none)
        defer { ntk_dialog_result_free(result?.handle) }
        XCTAssertEqual(ntk_dialog_result_button(result?.handle), 3)
        XCTAssertEqual(ntk_dialog_result_option_index(result?.handle), 2)
        XCTAssertEqual(text(ntk_dialog_result_button_text(result?.handle, nil)), "Beta")
    }

    // MARK: - The readers

    private func handle(_ button: DialogAnswer.Button, title: String? = "b", input: DialogInput? = nil) -> OpaquePointer? {
        DialogMapping.result(of: DialogAnswer(button: button, title: title, input: input)).map(DialogHandles.makeResult)
    }

    func testAResultWithAText() {
        let result = handle(.primary, title: "OK", input: .text("a\0b"))
        defer { ntk_dialog_result_free(result) }
        XCTAssertEqual(ntk_dialog_result_button(result), 0)
        XCTAssertEqual(ntk_dialog_result_option_index(result), -1)
        var size = -1
        XCTAssertEqual(text(ntk_dialog_result_button_text(result, &size)), "OK")
        XCTAssertEqual(size, 2)
        XCTAssertEqual(text(ntk_dialog_result_text(result, &size)), "a\u{FFFD}b")
        XCTAssertEqual(size, 5)
        size = -1
        XCTAssertNil(ntk_dialog_result_username(result, &size))
        XCTAssertEqual(size, 0)
        size = -1
        XCTAssertNil(ntk_dialog_result_password(result, &size))
        XCTAssertEqual(size, 0)
    }

    func testAResultWithALogin() {
        let result = handle(.primary, input: .login(username: "user", password: "pass\u{65E5}"))
        defer { ntk_dialog_result_free(result) }
        var size = -1
        XCTAssertEqual(text(ntk_dialog_result_username(result, &size)), "user")
        XCTAssertEqual(size, 4)
        XCTAssertEqual(text(ntk_dialog_result_password(result, &size)), "pass\u{65E5}")
        XCTAssertEqual(size, 7)
        size = -1
        XCTAssertNil(ntk_dialog_result_text(result, &size))
        XCTAssertEqual(size, 0)
    }

    /// An empty input is there: not NULL.
    func testAnEmptyInputIsNotNull() {
        let result = handle(.primary, input: .text(""))
        defer { ntk_dialog_result_free(result) }
        var size = -1
        XCTAssertEqual(text(ntk_dialog_result_text(result, &size)), "")
        XCTAssertEqual(size, 0)
    }

    func testAResultWithNoTitle() {
        let result = handle(.cancel, title: nil)
        defer { ntk_dialog_result_free(result) }
        XCTAssertEqual(ntk_dialog_result_button(result), 1)
        var size = -1
        XCTAssertNil(ntk_dialog_result_button_text(result, &size))
        XCTAssertEqual(size, 0)
    }

    func testAResultOfNull() {
        var size = -1
        XCTAssertEqual(ntk_dialog_result_button(nil), -1)
        XCTAssertEqual(ntk_dialog_result_option_index(nil), -1)
        XCTAssertNil(ntk_dialog_result_button_text(nil, &size))
        XCTAssertEqual(size, 0)
        XCTAssertNil(ntk_dialog_result_text(nil, nil))
        XCTAssertNil(ntk_dialog_result_username(nil, nil))
        XCTAssertNil(ntk_dialog_result_password(nil, nil))
        ntk_dialog_result_free(nil)
    }

    /// Undefined by the contract (part 1, chapter 6).
    func testAHandleOfAnotherTypeReadsAsNothing() {
        let other = Handle.makeString("x")
        defer { ntk_string_free(other) }
        XCTAssertEqual(ntk_dialog_result_button(other), -1)
        XCTAssertEqual(ntk_dialog_result_option_index(other), -1)
        XCTAssertNil(ntk_dialog_result_password(other, nil))
        let result = handle(.primary)
        defer { ntk_dialog_result_free(result) }
        XCTAssertNil(ntk_string_data(result))
    }
}
