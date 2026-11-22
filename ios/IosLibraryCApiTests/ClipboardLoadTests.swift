//
//  ClipboardLoadTests.swift
//  IosLibraryCApiTests
//

import IosLibrary
import UIKit
import XCTest
@testable import IosLibraryCApi

/// OP-11 and OP-12 through C, on named pasteboards (part 2, 5.3 and 12.1, "取り消し"). The app wrote the
/// content, so the system asks nothing; the paste prompt is in the UI tests. The test body is on the main
/// thread, so what it queues waits until it runs the main thread: that holds an order in place.
final class ClipboardLoadTests: ClipboardTestCase {
    private func png() -> [UInt8] {
        let image = UIGraphicsImageRenderer(size: CGSize(width: 1, height: 1)).image { context in
            UIColor.red.setFill()
            context.fill(CGRect(x: 0, y: 0, width: 1, height: 1))
        }
        return Array(image.pngData()!)
    }

    private func imageContent(_ bytes: [UInt8]) -> ntk_clipboard_write_content {
        var value = content(Int(NTK_CLIPBOARD_CONTENT_IMAGE_DATA))
        value.data = array(bytes)
        value.data_size = bytes.count
        value.ut_type = c("public.png")
        return value
    }

    /// A pasteboard with a PNG, to load as a file.
    private func pasteboardWithImage(file: StaticString = #filePath, line: UInt = #line) -> (scope: ntk_clipboard_scope, bytes: [UInt8]) {
        let scope = makeNamedPasteboard(file: file, line: line)
        let bytes = png()
        XCTAssertEqual(copy(imageContent(bytes), to: scope), ClipboardErrorValue.none, file: file, line: line)
        return (scope, bytes)
    }

    private func load(_ kind: Int, type: UnsafePointer<CChar>? = nil, _ scope: ntk_clipboard_scope,
                      file: StaticString = #filePath, line: UInt = #line) -> ClipboardRecorder.Completion? {
        var scope = scope
        var requestID: UInt64 = 0
        let result = completion(file: file, line: line) {
            ntk_clipboard_load_item_async(Int32(kind), type, &scope, recordLoad, $0.userData, recordRelease, &requestID)
        }
        XCTAssertNotEqual(requestID, 0, file: file, line: line)
        XCTAssertEqual(result?.requestID, requestID, file: file, line: line)
        return result
    }

    /// The request folders of `IosLibrary`'s temporary files and the files in them: `<root>/<session>/<request>/<file>`.
    /// The folder of the session stays for the process, so it does not count.
    private func temporaryPaths() -> Set<String> {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("IosLibraryClipboard", isDirectory: true).standardizedFileURL
        guard let items = FileManager.default.enumerator(at: root, includingPropertiesForKeys: nil) else { return [] }
        let depth = root.pathComponents.count
        return Set(items.compactMap { ($0 as? URL)?.standardizedFileURL }.filter { $0.pathComponents.count > depth + 1 }.map(\.path))
    }

    /// The paths once they did not change for `quiet` seconds: a load that lost a race can still be copying its
    /// file, and deletes it when it finds out. A set that never settles fails the test.
    private func settledTemporaryPaths(quiet: TimeInterval = 2, timeout: TimeInterval = 30,
                                       file: StaticString = #filePath, line: UInt = #line) -> Set<String> {
        let deadline = Date(timeIntervalSinceNow: timeout)
        var paths = temporaryPaths()
        var since = Date()
        while Date() < deadline {
            RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.02))
            let now = temporaryPaths()
            if now != paths {
                paths = now
                since = Date()
            } else if Date().timeIntervalSince(since) >= quiet {
                return paths
            }
        }
        XCTFail("the temporary files did not settle in \(timeout) s", file: file, line: line)
        return paths
    }

    /// The file and the folder belong to the caller of a `.file` load.
    private func removeLoadedFile(_ path: String) {
        try? FileManager.default.removeItem(at: URL(fileURLWithPath: path).deletingLastPathComponent())
    }

    // MARK: - What is loaded

    func testLoadingText() {
        let scope = makeNamedPasteboard()
        XCTAssertEqual(copy(plainText("a\u{65E5}"), to: scope), ClipboardErrorValue.none)
        let result = load(Int(NTK_CLIPBOARD_ITEM_TEXT), scope)
        defer { ntk_clipboard_loaded_item_free(result?.handle) }
        XCTAssertEqual(result?.error, ClipboardErrorValue.none)
        XCTAssertEqual(ntk_clipboard_loaded_item_kind(result?.handle), 0)
        var size = 0
        XCTAssertEqual(text(ntk_clipboard_loaded_item_text(result?.handle, &size)), "a\u{65E5}")
        XCTAssertEqual(size, 4)
    }

    func testLoadingAUrl() {
        let scope = makeNamedPasteboard()
        var value = content(Int(NTK_CLIPBOARD_CONTENT_URL))
        value.url = c("https://example.com/a")
        XCTAssertEqual(copy(value, to: scope), ClipboardErrorValue.none)
        let result = load(Int(NTK_CLIPBOARD_ITEM_URL), scope)
        defer { ntk_clipboard_loaded_item_free(result?.handle) }
        XCTAssertEqual(result?.error, ClipboardErrorValue.none)
        XCTAssertEqual(ntk_clipboard_loaded_item_kind(result?.handle), 1)
        XCTAssertEqual(text(ntk_clipboard_loaded_item_url(result?.handle, nil)), "https://example.com/a")
    }

    func testLoadingAnImage() {
        let (scope, _) = pasteboardWithImage()
        let result = load(Int(NTK_CLIPBOARD_ITEM_IMAGE), scope)
        defer { ntk_clipboard_loaded_item_free(result?.handle) }
        XCTAssertEqual(result?.error, ClipboardErrorValue.none)
        XCTAssertEqual(ntk_clipboard_loaded_item_kind(result?.handle), 2)
        var size = 0
        let data = ntk_clipboard_loaded_item_image_data(result?.handle, &size)
        XCTAssertNotNil(data)
        XCTAssertGreaterThan(size, 0)
        XCTAssertNotNil(data.flatMap { UIImage(data: Data(bytes: $0, count: size)) }, "the bytes are an image")
        XCTAssertNotNil(ntk_clipboard_loaded_item_image_type(result?.handle, nil))
    }

    /// A real `.file`: the bytes arrive, and `_free` deletes neither the file nor its folder.
    func testLoadingAFileGivesItAwayAndTheFreeLeavesIt() throws {
        let (scope, bytes) = pasteboardWithImage()
        let result = load(Int(NTK_CLIPBOARD_ITEM_FILE), type: c("public.png"), scope)
        XCTAssertEqual(result?.error, ClipboardErrorValue.none)
        XCTAssertEqual(ntk_clipboard_loaded_item_kind(result?.handle), 3)
        let path = try XCTUnwrap(text(ntk_clipboard_loaded_item_file_path(result?.handle, nil)))
        defer { removeLoadedFile(path) }
        XCTAssertEqual(try Data(contentsOf: URL(fileURLWithPath: path)), Data(bytes))

        ntk_clipboard_loaded_item_free(result?.handle)
        runMainQueue()

        XCTAssertTrue(FileManager.default.fileExists(atPath: path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: URL(fileURLWithPath: path).deletingLastPathComponent().path))
    }

    // MARK: - What fails in the completion

    func testNothingToLoad() {
        let scope = makeNamedPasteboard()
        let result = load(Int(NTK_CLIPBOARD_ITEM_TEXT), scope)
        XCTAssertEqual(result?.error, ClipboardErrorValue.noMatchingItem)
        XCTAssertNil(result?.handle)
    }

    func testAnEmptyTypeToLoadIsTheLibrarys() {
        let (scope, _) = pasteboardWithImage()
        let result = load(Int(NTK_CLIPBOARD_ITEM_FILE), type: c(""), scope)
        XCTAssertEqual(result?.error, ClipboardErrorValue.noMatchingItem)
        XCTAssertNil(result?.handle)
    }

    func testAPasteboardThatIsNotThere() {
        let result = load(Int(NTK_CLIPBOARD_ITEM_TEXT), named("ntk.capi.tests.notcreated.\(UUID().uuidString)"))
        XCTAssertEqual(result?.error, ClipboardErrorValue.unavailable)
        XCTAssertNil(result?.handle)
    }

    // MARK: - The entry

    /// The value output is left alone on a rejection (part 1, 5.7), and the call registered nothing.
    func testTheEntryRejects() {
        var bad = named("a.name")
        bad.reserved0 = 1
        let badScope = array([bad])
        let scope = array([named("never.used")])
        let table: [(String, Int32, UnsafePointer<CChar>?, UnsafePointer<ntk_clipboard_scope>?, Bool)] = [
            ("NULL callback", 0, nil, scope, false),
            ("kind -1", -1, nil, scope, true),
            ("kind 4", 4, nil, scope, true),
            ("FILE NULL", 3, nil, scope, true),
            ("FILE UTF-8", 3, raw([0xFF]), scope, true),
            ("bad scope", 0, nil, badScope, true),
        ]
        let before = Registry.requestCount
        for (name, kind, type, scopePointer, hasCallback) in table {
            let recorder = ClipboardRecorder()
            var requestID: UInt64 = 77
            XCTAssertEqual(ntk_clipboard_load_item_async(kind, type, scopePointer, hasCallback ? recordLoad : nil, recorder.userData, recordRelease, &requestID),
                           ClipboardErrorValue.invalidParameter, name)
            XCTAssertEqual(requestID, 77, name)
            XCTAssertEqual(recorder.releases, [true], name)
            runMainQueue()
            XCTAssertEqual(recorder.calls, ["release"], name)
        }
        XCTAssertEqual(Registry.requestCount, before)
    }

    func testARejectionOffTheMainThreadReleasesOnThatThread() {
        let recorder = ClipboardRecorder()
        let error = onAnotherThread { ntk_clipboard_load_item_async(-1, nil, nil, recordLoad, recorder.userData, recordRelease, nil) }
        XCTAssertEqual(error, ClipboardErrorValue.invalidParameter)
        XCTAssertEqual(recorder.releases, [false])
    }

    func testTheOutputOfTheIdMayBeNull() {
        let scope = makeNamedPasteboard()
        var scopeValue = scope
        let result = completion { ntk_clipboard_load_item_async(0, nil, &scopeValue, recordLoad, $0.userData, recordRelease, nil) }
        XCTAssertEqual(result?.error, ClipboardErrorValue.noMatchingItem)
        XCTAssertNotEqual(result?.requestID, 0)
    }

    func testIdsAreNotReused() {
        let scope = makeNamedPasteboard()
        var scopeValue = scope
        var first: UInt64 = 0
        var second: UInt64 = 0
        let one = ClipboardRecorder()
        let two = ClipboardRecorder()
        XCTAssertEqual(ntk_clipboard_load_item_async(0, nil, &scopeValue, recordLoad, one.userData, recordRelease, &first), ClipboardErrorValue.none)
        XCTAssertEqual(ntk_clipboard_load_item_async(0, nil, &scopeValue, recordLoad, two.userData, recordRelease, &second), ClipboardErrorValue.none)
        XCTAssertGreaterThan(second, first)
        finished(one)
        finished(two)
    }

    func testTheTypeIsCopiedBeforeItReturns() throws {
        let (scope, bytes) = pasteboardWithImage()
        var scopeValue = scope
        let recorder = ClipboardRecorder()
        let type = strdup("public.png")!
        XCTAssertEqual(ntk_clipboard_load_item_async(3, type, &scopeValue, recordLoad, recorder.userData, recordRelease, nil), ClipboardErrorValue.none)
        memset(type, 0x7A, strlen(type))
        free(type)
        let result = finished(recorder)
        XCTAssertEqual(result?.error, ClipboardErrorValue.none)
        let path = try XCTUnwrap(text(ntk_clipboard_loaded_item_file_path(result?.handle, nil)))
        defer { removeLoadedFile(path) }
        XCTAssertEqual(try Data(contentsOf: URL(fileURLWithPath: path)), Data(bytes))
        ntk_clipboard_loaded_item_free(result?.handle)
    }

    // MARK: - Cancelling

    /// Before the first main turn: nothing starts, and the removal gives CANCELED through the form that the
    /// receiver passes to the registry.
    func testACancelBeforeTheFirstMainTurnNeverStartsTheLoad() {
        let (scope, _) = pasteboardWithImage()
        var scopeValue = scope
        let files = settledTemporaryPaths()
        let recorder = ClipboardRecorder()
        var requestID: UInt64 = 0
        let before = Registry.requestCount

        XCTAssertEqual(ntk_clipboard_load_item_async(3, c("public.png"), &scopeValue, recordLoad, recorder.userData, recordRelease, &requestID), ClipboardErrorValue.none)
        XCTAssertEqual(Registry.requestCount, before + 1)
        XCTAssertEqual(ntk_clipboard_cancel_load(requestID), ClipboardErrorValue.none)
        recorder.markReturned()
        XCTAssertEqual(recorder.calls, [], "the completion comes on the main thread, not in the call")

        let result = finished(recorder)

        XCTAssertEqual(result?.error, ClipboardErrorValue.canceled)
        XCTAssertEqual(result?.requestID, requestID)
        XCTAssertNil(result?.handle)
        XCTAssertEqual(result?.afterReturn, true)
        XCTAssertEqual(Registry.requestCount, before)
        spin(0.3)
        XCTAssertEqual(recorder.calls, ["completion", "release"], "the load did not come later")
        XCTAssertEqual(settledTemporaryPaths().subtracting(files), [], "no file was written")
    }

    /// With the main thread stopped, from another thread: it returns, and the load ends with CANCELED.
    func testACancelFromAnotherThreadDoesNotWaitForTheMainThread() {
        let (scope, _) = pasteboardWithImage()
        var scopeValue = scope
        let recorder = ClipboardRecorder()
        var requestID: UInt64 = 0
        XCTAssertEqual(ntk_clipboard_load_item_async(3, c("public.png"), &scopeValue, recordLoad, recorder.userData, recordRelease, &requestID), ClipboardErrorValue.none)
        let id = requestID

        XCTAssertEqual(onAnotherThread { ntk_clipboard_cancel_load(id) }, ClipboardErrorValue.none)

        XCTAssertEqual(recorder.calls, [])
        XCTAssertEqual(finished(recorder)?.error, ClipboardErrorValue.canceled)
    }

    /// After the start. The test holds the main thread, so nothing can complete between the look and the cancel.
    func testACancelOfALoadThatStartedEndsWithCanceled() {
        let (scope, _) = pasteboardWithImage()
        var scopeValue = scope
        let recorder = ClipboardRecorder()
        var requestID: UInt64 = 0
        XCTAssertEqual(ntk_clipboard_load_item_async(3, c("public.png"), &scopeValue, recordLoad, recorder.userData, recordRelease, &requestID), ClipboardErrorValue.none)
        runMainQueue()
        let notYetDone = recorder.completions.isEmpty

        XCTAssertEqual(ntk_clipboard_cancel_load(requestID), ClipboardErrorValue.none)

        let result = finished(recorder)
        if notYetDone {
            XCTAssertEqual(result?.error, ClipboardErrorValue.canceled)
            XCTAssertNil(result?.handle)
            spin(0.3)
            XCTAssertEqual(recorder.calls, ["completion", "release"], "the result of the load does not complete it again")
        } else {
            // The load had finished before the cancel: the cancel changes nothing, and the file is the caller's.
            XCTAssertEqual(result?.error, ClipboardErrorValue.none)
            XCTAssertEqual(ntk_clipboard_loaded_item_kind(result?.handle), 3)
            let path = text(ntk_clipboard_loaded_item_file_path(result?.handle, nil))
            XCTAssertEqual(path.map { FileManager.default.fileExists(atPath: $0) }, true)
            spin(0.3)
            XCTAssertEqual(recorder.calls, ["completion", "release"])
            path.map(removeLoadedFile)
            ntk_clipboard_loaded_item_free(result?.handle)
        }
        // The notes count how often each branch is taken.
        print("[ClipboardLoadTests] the load had \(notYetDone ? "not finished" : "finished") at the cancel")
    }

    /// Against the end of the load, from another thread: whoever wins, exactly one completion, and a file
    /// only for the one that got it (part 2, 5.3). Only a `.file` the caller received stays.
    func testACancelAgainstTheEndOfALoadLeavesNoFileBehind() throws {
        let (scope, _) = pasteboardWithImage()
        var canceled = 0
        var delivered = 0
        let files = settledTemporaryPaths()
        for round in 0..<40 {
            var scopeValue = scope
            let recorder = ClipboardRecorder()
            var requestID: UInt64 = 0
            XCTAssertEqual(ntk_clipboard_load_item_async(3, c("public.png"), &scopeValue, recordLoad, recorder.userData, recordRelease, &requestID), ClipboardErrorValue.none)
            let id = requestID
            let delay = Double(round % 20) * 0.0005
            Thread.detachNewThread {
                Thread.sleep(forTimeInterval: delay)
                _ = ntk_clipboard_cancel_load(id)
            }
            let result = try XCTUnwrap(finished(recorder))
            if result.error == ClipboardErrorValue.none {
                delivered += 1
                let path = try XCTUnwrap(text(ntk_clipboard_loaded_item_file_path(result.handle, nil)))
                XCTAssertTrue(FileManager.default.fileExists(atPath: path))
                removeLoadedFile(path)
                ntk_clipboard_loaded_item_free(result.handle)
            } else {
                canceled += 1
                XCTAssertEqual(result.error, ClipboardErrorValue.canceled)
                XCTAssertNil(result.handle)
            }
        }
        XCTAssertEqual(settledTemporaryPaths().subtracting(files), [], "a file or a folder was left behind")
        // Which side won is timing; the notes quote this line.
        print("[ClipboardLoadTests] the race: canceled \(canceled), delivered \(delivered)")
    }

    /// Cancels as soon as the box of the request is closed. A block that queues itself is ahead of whatever the
    /// close queues, so this runs after the load's end closed the box and before its result reaches the receiver.
    private static func cancelOnceClosed(_ box: RequestBox, id: UInt64) {
        MainQueue.async {
            if box.isClosed {
                _ = ntk_clipboard_cancel_load(id)
            } else {
                cancelOnceClosed(box, id: id)
            }
        }
    }

    /// Part 2, 5.3: the library reports a success, and C reports CANCELED. Only the receiver can delete the file:
    /// `IosLibrary` deletes it only when it loses the box.
    func testACancelAfterTheLoadsSuccessClosedTheBoxDeletesTheFile() throws {
        let (scope, _) = pasteboardWithImage()
        var scopeValue = scope
        let files = settledTemporaryPaths()
        let recorder = ClipboardRecorder()
        var requestID: UInt64 = 0
        XCTAssertEqual(ntk_clipboard_load_item_async(3, c("public.png"), &scopeValue, recordLoad, recorder.userData, recordRelease, &requestID), ClipboardErrorValue.none)
        Self.cancelOnceClosed(try XCTUnwrap(Registry.requestBox(id: requestID)), id: requestID)

        let result = finished(recorder)

        XCTAssertEqual(result?.error, ClipboardErrorValue.canceled)
        XCTAssertNil(result?.handle)
        XCTAssertEqual(settledTemporaryPaths().subtracting(files), [], "the file of the success the caller did not get, or its folder")
    }

    /// A cancel from inside the callback does not delete what it was given (part 2, 5.3).
    func testACancelInsideTheCallbackLeavesTheFileItWasGiven() throws {
        let (scope, bytes) = pasteboardWithImage()
        var scopeValue = scope
        let recorder = ClipboardRecorder()
        recorder.onCompletion = { completion in
            XCTAssertEqual(ntk_clipboard_cancel_load(completion.requestID), ClipboardErrorValue.none)
        }
        XCTAssertEqual(ntk_clipboard_load_item_async(3, c("public.png"), &scopeValue, recordLoad, recorder.userData, recordRelease, nil), ClipboardErrorValue.none)

        let result = finished(recorder)
        spin(0.2)

        XCTAssertEqual(result?.error, ClipboardErrorValue.none)
        XCTAssertEqual(recorder.calls, ["completion", "release"])
        let path = try XCTUnwrap(text(ntk_clipboard_loaded_item_file_path(result?.handle, nil)))
        defer { removeLoadedFile(path) }
        XCTAssertEqual(try Data(contentsOf: URL(fileURLWithPath: path)), Data(bytes))
        ntk_clipboard_loaded_item_free(result?.handle)
    }

    /// A callback may start another load and cancel it: each completes once, after its own call returned.
    func testALoadStartedInsideTheCompletionOfAnother() {
        let scope = makeNamedPasteboard()
        XCTAssertEqual(copy(plainText("x"), to: scope), ClipboardErrorValue.none)
        let scopePointer = array([scope])
        let scopeAddress = UInt(bitPattern: scopePointer)
        let outer = ClipboardRecorder()
        let inner = ClipboardRecorder()
        outer.onCompletion = { _ in
            var id: UInt64 = 0
            XCTAssertEqual(ntk_clipboard_load_item_async(0, nil, UnsafePointer(bitPattern: scopeAddress), recordLoad, inner.userData, recordRelease, &id), ClipboardErrorValue.none)
            XCTAssertEqual(ntk_clipboard_cancel_load(id), ClipboardErrorValue.none)
            XCTAssertEqual(inner.calls, [], "nothing runs inside the call, also inside a callback")
        }
        XCTAssertEqual(ntk_clipboard_load_item_async(0, nil, scopePointer, recordLoad, outer.userData, recordRelease, nil), ClipboardErrorValue.none)

        let result = finished(outer)
        let canceled = finished(inner)

        XCTAssertEqual(result?.error, ClipboardErrorValue.none)
        ntk_clipboard_loaded_item_free(result?.handle)
        XCTAssertEqual(canceled?.error, ClipboardErrorValue.canceled)
    }

    /// A CANCELED callback that turns the run loop: nothing completes it again and the release waits for it.
    func testTheCanceledCallbackMayTurnTheRunLoop() {
        let (scope, _) = pasteboardWithImage()
        var scopeValue = scope
        let recorder = ClipboardRecorder()
        recorder.onCompletion = { _ in
            RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.1))
            XCTAssertEqual(recorder.releases, [], "the release does not overlap the callback")
        }
        var requestID: UInt64 = 0
        XCTAssertEqual(ntk_clipboard_load_item_async(3, c("public.png"), &scopeValue, recordLoad, recorder.userData, recordRelease, &requestID), ClipboardErrorValue.none)
        XCTAssertEqual(ntk_clipboard_cancel_load(requestID), ClipboardErrorValue.none)

        XCTAssertEqual(finished(recorder)?.error, ClipboardErrorValue.canceled)
    }

    func testIdsThatAreNotARunningLoadDoNothing() {
        XCTAssertEqual(ntk_clipboard_cancel_load(0), ClipboardErrorValue.none)
        XCTAssertEqual(ntk_clipboard_cancel_load(UInt64.max), ClipboardErrorValue.none)

        let scope = makeNamedPasteboard()
        let result = load(0, scope)
        let id = result?.requestID ?? 0
        XCTAssertEqual(ntk_clipboard_cancel_load(id), ClipboardErrorValue.none, "a finished one")
        XCTAssertEqual(ntk_clipboard_cancel_load(id), ClipboardErrorValue.none, "and again")
        runMainQueue()
    }

    func testASecondCancelDoesNothing() {
        let (scope, _) = pasteboardWithImage()
        var scopeValue = scope
        let recorder = ClipboardRecorder()
        var requestID: UInt64 = 0
        XCTAssertEqual(ntk_clipboard_load_item_async(0, nil, &scopeValue, recordLoad, recorder.userData, recordRelease, &requestID), ClipboardErrorValue.none)
        XCTAssertEqual(ntk_clipboard_cancel_load(requestID), ClipboardErrorValue.none)
        XCTAssertEqual(ntk_clipboard_cancel_load(requestID), ClipboardErrorValue.none)
        XCTAssertEqual(finished(recorder)?.error, ClipboardErrorValue.canceled)
    }

    /// The id of another kind of request is not a load's (`Registry.cancel`): a Dialog's cancel leaves it.
    func testACancelOfTheOtherKindLeavesALoadAlone() {
        let scope = makeNamedPasteboard()
        XCTAssertEqual(copy(plainText("x"), to: scope), ClipboardErrorValue.none)
        var scopeValue = scope
        let recorder = ClipboardRecorder()
        var requestID: UInt64 = 0
        XCTAssertEqual(ntk_clipboard_load_item_async(0, nil, &scopeValue, recordLoad, recorder.userData, recordRelease, &requestID), ClipboardErrorValue.none)
        Registry.cancel(id: requestID, request: DialogReceiver.cancelKind)
        let result = finished(recorder)
        XCTAssertEqual(result?.error, ClipboardErrorValue.none)
        ntk_clipboard_loaded_item_free(result?.handle)
    }
}
