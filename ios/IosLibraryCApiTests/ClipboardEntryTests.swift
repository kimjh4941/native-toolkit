//
//  ClipboardEntryTests.swift
//  IosLibraryCApiTests
//

import UIKit
import XCTest
@testable import IosLibraryCApi

/// The functions of Clipboard.h through C (part 2, 12.1): what is rejected at the entry and how, the
/// completion of what is accepted, and the Clipboard row. Only named pasteboards are written or read
/// (`ClipboardTestSupport`).
final class ClipboardEntryTests: ClipboardTestCase {

    // MARK: - The 11 functions, with a callback or none

    /// A call of one function, and whether to give it its callback.
    private struct Call: @unchecked Sendable {
        let name: String
        /// Frees the handle of the completion.
        var free: (OpaquePointer?) -> Void = { _ in }
        let run: (_ userData: UnsafeMutableRawPointer?, _ release: ntk_release_fn?, _ withCallback: Bool) -> Int32
    }

    /// Each function with a valid request on `scope`, or with NULL for its callback. Nothing reaches the
    /// general pasteboard: `scope` is a named one.
    private func calls(scope: ntk_clipboard_scope) -> [Call] {
        let scopePointer = array([scope])
        let contentPointer = array([plainText("x")])
        let type = c("public.plain-text")
        let number = UInt32(NTK_CLIPBOARD_PATTERN_NUMBER)
        return [
            Call(name: "copy") { ntk_clipboard_copy_async(contentPointer, nil, scopePointer, $2 ? recordDone : nil, $0, $1) },
            Call(name: "append") { ntk_clipboard_append_async(contentPointer, scopePointer, $2 ? recordDone : nil, $0, $1) },
            Call(name: "read", free: ntk_clipboard_read_result_free) { ntk_clipboard_read_async(scopePointer, $2 ? recordHandle : nil, $0, $1) },
            Call(name: "readData", free: ntk_bytes_free) { ntk_clipboard_read_data_async(type, scopePointer, $2 ? recordHandle : nil, $0, $1) },
            Call(name: "snapshot", free: ntk_clipboard_snapshot_free) { ntk_clipboard_get_snapshot_async(nil, 0, scopePointer, $2 ? recordHandle : nil, $0, $1) },
            Call(name: "clear") { ntk_clipboard_clear_async(scopePointer, $2 ? recordDone : nil, $0, $1) },
            Call(name: "create", free: ntk_string_free) { ntk_clipboard_create_pasteboard_async(Int32(NTK_CLIPBOARD_SCOPE_NAMED), scope.name, $2 ? recordHandle : nil, $0, $1) },
            Call(name: "detectPatterns") { ntk_clipboard_detect_patterns_async(number, scopePointer, $2 ? recordPatterns : nil, $0, $1) },
            Call(name: "detectValues", free: ntk_string_free) { ntk_clipboard_detect_values_async(number, scopePointer, $2 ? recordHandle : nil, $0, $1) },
            Call(name: "check") { ntk_clipboard_check_foreground_change_async(scopePointer, $2 ? recordChanged : nil, $0, $1) },
            Call(name: "remove") { ntk_clipboard_remove_pasteboard_async(scopePointer, $2 ? recordDone : nil, $0, $1) },
        ]
    }

    private func assertRejected(_ recorder: ClipboardRecorder, _ error: Int32, _ expected: Int32, onMain: Bool = true, _ message: String = "",
                                file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertEqual(error, expected, message, file: file, line: line)
        // On this thread, before the function returned; nothing queued afterwards calls anything.
        XCTAssertEqual(recorder.releases, [onMain], message, file: file, line: line)
        runMainQueue(file: file, line: line)
        XCTAssertEqual(recorder.calls, ["release"], message, file: file, line: line)
    }

    func testANullCallbackIsRejected() {
        for call in calls(scope: named("never.used")) {
            let recorder = ClipboardRecorder()
            assertRejected(recorder, call.run(recorder.userData, recordRelease, false), ClipboardErrorValue.invalidParameter, call.name)
        }
    }

    func testARejectionWithoutAReleaseIsFine() {
        for call in calls(scope: named("never.used")) {
            XCTAssertEqual(call.run(nil, nil, false), ClipboardErrorValue.invalidParameter, call.name)
        }
    }

    func testARejectionOffTheMainThreadReleasesOnThatThread() {
        let call = calls(scope: named("never.used"))
        for index in call.indices {
            let recorder = ClipboardRecorder()
            let entry = call[index]
            let error = onAnotherThread { entry.run(recorder.userData, recordRelease, false) }
            assertRejected(recorder, error ?? -1, ClipboardErrorValue.invalidParameter, onMain: false, entry.name)
        }
    }

    /// What every function that takes a scope does with a bad one: nothing is registered.
    func testABadScopeIsRejectedByEachFunction() {
        var bad = named("a.name")
        bad.reserved1 = 1
        let scopePointer = array([bad])
        let contentPointer = array([plainText("x")])
        let type = c("public.plain-text")
        let number = UInt32(NTK_CLIPBOARD_PATTERN_NUMBER)
        let table: [(ClipboardRecorder) -> Int32] = [
            { ntk_clipboard_copy_async(contentPointer, nil, scopePointer, recordDone, $0.userData, recordRelease) },
            { ntk_clipboard_append_async(contentPointer, scopePointer, recordDone, $0.userData, recordRelease) },
            { ntk_clipboard_read_async(scopePointer, recordHandle, $0.userData, recordRelease) },
            { ntk_clipboard_read_data_async(type, scopePointer, recordHandle, $0.userData, recordRelease) },
            { ntk_clipboard_get_snapshot_async(nil, 0, scopePointer, recordHandle, $0.userData, recordRelease) },
            { ntk_clipboard_clear_async(scopePointer, recordDone, $0.userData, recordRelease) },
            { ntk_clipboard_remove_pasteboard_async(scopePointer, recordDone, $0.userData, recordRelease) },
            { ntk_clipboard_detect_patterns_async(number, scopePointer, recordPatterns, $0.userData, recordRelease) },
            { ntk_clipboard_detect_values_async(number, scopePointer, recordHandle, $0.userData, recordRelease) },
            { ntk_clipboard_check_foreground_change_async(scopePointer, recordChanged, $0.userData, recordRelease) },
        ]
        for (index, call) in table.enumerated() {
            let recorder = ClipboardRecorder()
            assertRejected(recorder, call(recorder), ClipboardErrorValue.invalidParameter, "function \(index)")
        }
    }

    func testEachFunctionRejectsItsOwnArguments() {
        let scope = array([named("a.name")])
        let empty = content(Int(NTK_CLIPBOARD_CONTENT_MULTIPLE_TEXT))
        let emptyPointer = array([empty])
        let noRepresentationsPointer = array([content(Int(NTK_CLIPBOARD_CONTENT_MULTI_REPRESENTATION))])
        var emptyPath = content(Int(NTK_CLIPBOARD_CONTENT_IMAGE_FILE))
        emptyPath.path = c("")
        let emptyPathPointer = array([emptyPath])
        var badOptions = options()
        badOptions.reserved0 = 1
        let badOptionsPointer = array([badOptions])
        let textPointer = array([plainText("x")])
        let number = UInt32(NTK_CLIPBOARD_PATTERN_NUMBER)
        let unknownBit: UInt32 = 1 << 11
        let invalidParameter = ClipboardErrorValue.invalidParameter
        let table: [(String, Int32, (ClipboardRecorder) -> Int32)] = [
            ("copy NULL", invalidParameter, { ntk_clipboard_copy_async(nil, nil, scope, recordDone, $0.userData, recordRelease) }),
            ("copy options", invalidParameter, { ntk_clipboard_copy_async(textPointer, badOptionsPointer, scope, recordDone, $0.userData, recordRelease) }),
            ("copy empty", ClipboardErrorValue.emptyItems, { ntk_clipboard_copy_async(emptyPointer, nil, scope, recordDone, $0.userData, recordRelease) }),
            ("copy no representations", ClipboardErrorValue.emptyItems, { ntk_clipboard_copy_async(noRepresentationsPointer, nil, scope, recordDone, $0.userData, recordRelease) }),
            ("copy empty path", invalidParameter, { ntk_clipboard_copy_async(emptyPathPointer, nil, scope, recordDone, $0.userData, recordRelease) }),
            ("append NULL", invalidParameter, { ntk_clipboard_append_async(nil, scope, recordDone, $0.userData, recordRelease) }),
            ("append empty", ClipboardErrorValue.emptyItems, { ntk_clipboard_append_async(emptyPointer, scope, recordDone, $0.userData, recordRelease) }),
            ("append no representations", ClipboardErrorValue.emptyItems, { ntk_clipboard_append_async(noRepresentationsPointer, scope, recordDone, $0.userData, recordRelease) }),
            ("append empty path", invalidParameter, { ntk_clipboard_append_async(emptyPathPointer, scope, recordDone, $0.userData, recordRelease) }),
            ("readData NULL", invalidParameter, { ntk_clipboard_read_data_async(nil, scope, recordHandle, $0.userData, recordRelease) }),
            ("readData UTF-8", invalidParameter, { ntk_clipboard_read_data_async(self.raw([0xFF]), scope, recordHandle, $0.userData, recordRelease) }),
            ("snapshot NULL", invalidParameter, { ntk_clipboard_get_snapshot_async(nil, 1, scope, recordHandle, $0.userData, recordRelease) }),
            ("create GENERAL", invalidParameter, { ntk_clipboard_create_pasteboard_async(Int32(NTK_CLIPBOARD_SCOPE_GENERAL), self.c("a"), recordHandle, $0.userData, recordRelease) }),
            ("create NULL", invalidParameter, { ntk_clipboard_create_pasteboard_async(Int32(NTK_CLIPBOARD_SCOPE_NAMED), nil, recordHandle, $0.userData, recordRelease) }),
            ("remove NULL", invalidParameter, { ntk_clipboard_remove_pasteboard_async(nil, recordDone, $0.userData, recordRelease) }),
            ("patterns 0", ClipboardErrorValue.emptyPatterns, { ntk_clipboard_detect_patterns_async(0, scope, recordPatterns, $0.userData, recordRelease) }),
            ("patterns bit", invalidParameter, { ntk_clipboard_detect_patterns_async(unknownBit, scope, recordPatterns, $0.userData, recordRelease) }),
            ("values 0", ClipboardErrorValue.emptyPatterns, { ntk_clipboard_detect_values_async(0, scope, recordHandle, $0.userData, recordRelease) }),
            ("values bit", invalidParameter, { ntk_clipboard_detect_values_async(number | unknownBit, scope, recordHandle, $0.userData, recordRelease) }),
        ]
        for (name, expected, call) in table {
            let recorder = ClipboardRecorder()
            assertRejected(recorder, call(recorder), expected, name)
        }
    }

    /// A count whose size in bytes overflows is positive as an `Int`. The element stops the process when it
    /// is read, so these say that the function returned without reading any.
    func testAMatchingTypeCountThatOverflowsIsRejected() {
        let types = array([Optional(unreadable(CChar.self))])
        let recorder = ClipboardRecorder()
        var scope = named("never.used")
        assertRejected(recorder, ntk_clipboard_get_snapshot_async(types, 1 << 61, &scope, recordHandle, recorder.userData, recordRelease),
                       ClipboardErrorValue.invalidParameter)
    }

    func testATextCountThatOverflowsIsRejected() {
        var value = content(Int(NTK_CLIPBOARD_CONTENT_MULTIPLE_TEXT))
        value.texts = array([Optional(unreadable(CChar.self))])
        value.text_count = 1 << 61
        let recorder = ClipboardRecorder()
        var scope = named("never.used")
        assertRejected(recorder, ntk_clipboard_copy_async(&value, nil, &scope, recordDone, recorder.userData, recordRelease),
                       ClipboardErrorValue.invalidParameter)
    }

    func testTheSystemCodeAfterARejectionIsZero() {
        XCTAssertEqual(ntk_clipboard_read_data_async(nil, nil, recordHandle, nil, nil), ClipboardErrorValue.invalidParameter)
        XCTAssertEqual(ntk_last_system_code(), 0)
    }

    // MARK: - What is accepted

    /// Off the main thread while it is stopped: every function returns, and every completion comes on
    /// the main thread once it runs again (part 1, chapter 6).
    func testEveryFunctionReturnsWithoutTheMainThread() {
        let scope = makeNamedPasteboard()
        for call in calls(scope: scope) {
            let recorder = ClipboardRecorder()
            let error = onAnotherThread { call.run(recorder.userData, recordRelease, true) }
            XCTAssertEqual(error, ClipboardErrorValue.none, call.name)
            XCTAssertEqual(recorder.calls, [], call.name)
            call.free(finished(recorder)?.handle)
        }
    }

    /// A NULL release is accepted.
    func testAcceptedWithoutARelease() {
        let scope = makeNamedPasteboard()
        var scopeValue = scope
        let recorder = ClipboardRecorder()
        XCTAssertEqual(ntk_clipboard_check_foreground_change_async(&scopeValue, recordChanged, recorder.userData, nil), ClipboardErrorValue.none)
        let deadline = Date(timeIntervalSinceNow: 5)
        while recorder.completions.isEmpty, Date() < deadline {
            RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.002))
        }
        XCTAssertEqual(recorder.calls, ["completion"])
    }

    /// Everything is copied before the function returns (part 1, chapter 6, R-5): the buffers are
    /// changed and freed while the main thread has not started the request.
    func testTheInputIsCopiedBeforeItReturns() throws {
        let scope = makeNamedPasteboard()
        var scopeValue = scope
        let recorder = ClipboardRecorder()

        let type = strdup("com.example.type")!
        let name = strdup(String(cString: scope.name))!
        // Longer than what `Data` keeps inline, so that a copy is not an accident of its size.
        let original = (0..<256).map { UInt8($0) }
        let data = UnsafeMutablePointer<UInt8>.allocate(capacity: original.count)
        data.initialize(from: original, count: original.count)
        let elements = UnsafeMutablePointer<ntk_clipboard_representation>.allocate(capacity: 1)
        var element = ntk_clipboard_representation()
        element.struct_size = UInt32(MemoryLayout<ntk_clipboard_representation>.size)
        element.ut_type = UnsafePointer(type)
        element.data = UnsafePointer(data)
        element.data_size = original.count
        elements.initialize(to: element)
        let value = UnsafeMutablePointer<ntk_clipboard_write_content>.allocate(capacity: 1)
        var raw = content(Int(NTK_CLIPBOARD_CONTENT_MULTI_REPRESENTATION))
        raw.representations = UnsafePointer(elements)
        raw.representation_count = 1
        value.initialize(to: raw)
        scopeValue.name = UnsafePointer(name)

        XCTAssertEqual(ntk_clipboard_copy_async(value, nil, &scopeValue, recordDone, recorder.userData, recordRelease), ClipboardErrorValue.none)

        // Now the caller reuses all of it. Under ASan a later read would stop the test.
        memset(type, 0x7A, strlen(type))
        memset(name, 0x7A, strlen(name))
        data.update(repeating: 9, count: original.count)
        value.pointee.kind = 99
        elements.pointee.reserved0 = 1
        free(type)
        free(name)
        data.deallocate()
        elements.deallocate()
        value.deallocate()
        scopeValue.name = nil

        XCTAssertEqual(finished(recorder)?.error, ClipboardErrorValue.none)

        var readScope = scope
        let read = completion { ntk_clipboard_read_data_async(c("com.example.type"), &readScope, recordHandle, $0.userData, recordRelease) }
        XCTAssertEqual(bytes(of: read?.handle), original)
        ntk_bytes_free(read?.handle)
    }

    /// The same for the text of the queries and of the creation: freed before the main thread gets to them.
    func testTheTextOfTheQueriesIsCopiedBeforeItReturns() {
        let scope = makeNamedPasteboard()
        var custom = content(Int(NTK_CLIPBOARD_CONTENT_CUSTOM_DATA))
        custom.data = array([1, 2, 3])
        custom.data_size = 3
        custom.ut_type = c("com.example.type")
        XCTAssertEqual(copy(custom, to: scope), ClipboardErrorValue.none)
        var scopeValue = scope

        func spoiled(_ text: UnsafeMutablePointer<CChar>) {
            memset(text, 0x7A, strlen(text))
            free(text)
        }

        let dataRecorder = ClipboardRecorder()
        let type = strdup("com.example.type")!
        XCTAssertEqual(ntk_clipboard_read_data_async(type, &scopeValue, recordHandle, dataRecorder.userData, recordRelease), ClipboardErrorValue.none)
        spoiled(type)
        let data = finished(dataRecorder)
        XCTAssertEqual(bytes(of: data?.handle), [1, 2, 3])
        ntk_bytes_free(data?.handle)

        let snapshotRecorder = ClipboardRecorder()
        let matching = strdup("com.example.type")!
        let types = UnsafeMutablePointer<UnsafePointer<CChar>?>.allocate(capacity: 1)
        types.initialize(to: UnsafePointer(matching))
        XCTAssertEqual(ntk_clipboard_get_snapshot_async(types, 1, &scopeValue, recordHandle, snapshotRecorder.userData, recordRelease), ClipboardErrorValue.none)
        types.pointee = nil
        types.deallocate()
        spoiled(matching)
        let snapshot = finished(snapshotRecorder)
        XCTAssertEqual(ntk_clipboard_snapshot_matching_count(snapshot?.handle), 1)
        XCTAssertEqual(ntk_clipboard_snapshot_matching_at(snapshot?.handle, 0), 0)
        ntk_clipboard_snapshot_free(snapshot?.handle)

        let nameRecorder = ClipboardRecorder()
        let newName = "ntk.capi.tests.\(UUID().uuidString)"
        let name = strdup(newName)!
        XCTAssertEqual(ntk_clipboard_create_pasteboard_async(Int32(NTK_CLIPBOARD_SCOPE_NAMED), name, recordHandle, nameRecorder.userData, recordRelease), ClipboardErrorValue.none)
        spoiled(name)
        let created = finished(nameRecorder)
        XCTAssertEqual(text(ntk_string_data(created?.handle)), newName)
        ntk_string_free(created?.handle)
        var createdScope = named(newName)
        XCTAssertEqual(completion { ntk_clipboard_remove_pasteboard_async(&createdScope, recordDone, $0.userData, recordRelease) }?.error, ClipboardErrorValue.none)
    }

    // MARK: - Writing, and reading back through C: the 9 kinds

    /// The text of the only item, and the free of the handle.
    private func readItems(_ scope: ntk_clipboard_scope, file: StaticString = #filePath, line: UInt = #line) -> OpaquePointer? {
        var scope = scope
        let result = completion(file: file, line: line) { ntk_clipboard_read_async(&scope, recordHandle, $0.userData, recordRelease) }
        XCTAssertEqual(result?.error, ClipboardErrorValue.none, file: file, line: line)
        return result?.handle
    }

    private func readData(_ type: String, _ scope: ntk_clipboard_scope, file: StaticString = #filePath, line: UInt = #line) -> [UInt8]? {
        var scope = scope
        let result = completion(file: file, line: line) { ntk_clipboard_read_data_async(c(type), &scope, recordHandle, $0.userData, recordRelease) }
        XCTAssertEqual(result?.error, ClipboardErrorValue.none, file: file, line: line)
        defer { ntk_bytes_free(result?.handle) }
        return bytes(of: result?.handle)
    }

    private func snapshot(_ scope: ntk_clipboard_scope, matching: [String]? = nil, file: StaticString = #filePath, line: UInt = #line) -> OpaquePointer? {
        var scope = scope
        let types = matching.map { array($0.map { Optional(c($0)) }) }
        let result = completion(file: file, line: line) { ntk_clipboard_get_snapshot_async(types, matching?.count ?? 0, &scope, recordHandle, $0.userData, recordRelease) }
        XCTAssertEqual(result?.error, ClipboardErrorValue.none, file: file, line: line)
        return result?.handle
    }

    private func png() -> [UInt8] {
        let image = UIGraphicsImageRenderer(size: CGSize(width: 1, height: 1)).image { context in
            UIColor.red.setFill()
            context.fill(CGRect(x: 0, y: 0, width: 1, height: 1))
        }
        return Array(image.pngData()!)
    }

    func testRoundTripOfPlainText() {
        let scope = makeNamedPasteboard()
        XCTAssertEqual(copy(plainText("a\u{65E5}\u{1F600}"), to: scope), ClipboardErrorValue.none)
        let handle = readItems(scope)
        defer { ntk_clipboard_read_result_free(handle) }
        XCTAssertEqual(ntk_clipboard_read_result_item_count(handle), 1)
        var size = 0
        XCTAssertEqual(text(ntk_clipboard_read_result_item_text_at(handle, 0, &size)), "a\u{65E5}\u{1F600}")
        XCTAssertEqual(size, 8)
        XCTAssertGreaterThan(ntk_clipboard_read_result_item_type_count(handle, 0), 0)
        XCTAssertEqual(readData("public.plain-text", scope), Array("a\u{65E5}\u{1F600}".utf8))
    }

    func testRoundTripOfHtml() {
        let scope = makeNamedPasteboard()
        var value = content(Int(NTK_CLIPBOARD_CONTENT_HTML))
        value.text = c("plain")
        value.html = c("<b>x</b>")
        XCTAssertEqual(copy(value, to: scope), ClipboardErrorValue.none)
        XCTAssertEqual(readData("public.html", scope), Array("<b>x</b>".utf8))
        let handle = readItems(scope)
        defer { ntk_clipboard_read_result_free(handle) }
        XCTAssertEqual(text(ntk_clipboard_read_result_item_text_at(handle, 0, nil)), "plain")
    }

    /// As on Android: the plain text may be left out. What it reads back as is not compared: `""` goes in
    /// (`ClipboardMappingTests.testHtml`), and the read gave the text of the HTML (working notes 6.6).
    func testCopyingHtmlWithoutPlainTextKeepsTheHtml() {
        let scope = makeNamedPasteboard()
        var value = content(Int(NTK_CLIPBOARD_CONTENT_HTML))
        value.html = c("<b>x</b>")
        XCTAssertEqual(copy(value, to: scope), ClipboardErrorValue.none)
        XCTAssertEqual(readData("public.html", scope), Array("<b>x</b>".utf8))
    }

    func testRoundTripOfAUrl() {
        let scope = makeNamedPasteboard()
        var value = content(Int(NTK_CLIPBOARD_CONTENT_URL))
        value.url = c("https://example.com/a")
        XCTAssertEqual(copy(value, to: scope), ClipboardErrorValue.none)
        let handle = readItems(scope)
        defer { ntk_clipboard_read_result_free(handle) }
        XCTAssertEqual(text(ntk_clipboard_read_result_item_url_at(handle, 0, nil)), "https://example.com/a")
    }

    /// Only the flag: the image that reached the OS is not compared (working notes 6.6).
    func testACopiedImageFileShowsInTheImageFlagOfTheSnapshot() throws {
        let scope = makeNamedPasteboard()
        let file = FileManager.default.temporaryDirectory.appendingPathComponent("\(UUID().uuidString).png")
        try Data(png()).write(to: file)
        defer { try? FileManager.default.removeItem(at: file) }
        var value = content(Int(NTK_CLIPBOARD_CONTENT_IMAGE_FILE))
        value.path = c(file.path)
        XCTAssertEqual(copy(value, to: scope), ClipboardErrorValue.none)
        let handle = snapshot(scope)
        defer { ntk_clipboard_snapshot_free(handle) }
        XCTAssertEqual(ntk_clipboard_snapshot_has_images(handle), 1)
    }

    func testRoundTripOfImageData() {
        let scope = makeNamedPasteboard()
        let bytes = png()
        var value = content(Int(NTK_CLIPBOARD_CONTENT_IMAGE_DATA))
        value.data = array(bytes)
        value.data_size = bytes.count
        value.ut_type = c("public.png")
        XCTAssertEqual(copy(value, to: scope), ClipboardErrorValue.none)
        XCTAssertEqual(readData("public.png", scope), bytes)
        let handle = readItems(scope)
        defer { ntk_clipboard_read_result_free(handle) }
        XCTAssertEqual(text(ntk_clipboard_read_result_item_image_type_at(handle, 0, nil)), "public.png")
    }

    /// Only the flags: the color that reached the OS is not compared (working notes 6.6).
    func testACopiedColorShowsInTheColorFlagOfTheSnapshot() {
        let scope = makeNamedPasteboard()
        var value = content(Int(NTK_CLIPBOARD_CONTENT_COLOR))
        value.red = 1
        value.alpha = 1
        XCTAssertEqual(copy(value, to: scope), ClipboardErrorValue.none)
        let handle = snapshot(scope)
        defer { ntk_clipboard_snapshot_free(handle) }
        XCTAssertEqual(ntk_clipboard_snapshot_has_colors(handle), 1)
        XCTAssertEqual(ntk_clipboard_snapshot_has_strings(handle), 0)
    }

    func testRoundTripOfCustomData() {
        let scope = makeNamedPasteboard()
        var value = content(Int(NTK_CLIPBOARD_CONTENT_CUSTOM_DATA))
        value.data = array([0, 1, 2, 0])
        value.data_size = 4
        value.ut_type = c("com.example.custom")
        XCTAssertEqual(copy(value, to: scope), ClipboardErrorValue.none)
        XCTAssertEqual(readData("com.example.custom", scope), [0, 1, 2, 0], "bytes are returned as they are")
    }

    func testRoundTripOfMultipleText() {
        let scope = makeNamedPasteboard()
        var value = content(Int(NTK_CLIPBOARD_CONTENT_MULTIPLE_TEXT))
        value.texts = array([c("first"), c("second")] as [UnsafePointer<CChar>?])
        value.text_count = 2
        XCTAssertEqual(copy(value, to: scope), ClipboardErrorValue.none)
        let handle = readItems(scope)
        defer { ntk_clipboard_read_result_free(handle) }
        XCTAssertEqual(ntk_clipboard_read_result_item_count(handle), 2)
        XCTAssertEqual(text(ntk_clipboard_read_result_item_text_at(handle, 0, nil)), "first")
        XCTAssertEqual(text(ntk_clipboard_read_result_item_text_at(handle, 1, nil)), "second")
    }

    func testRoundTripOfMultiRepresentation() {
        let scope = makeNamedPasteboard()
        var value = content(Int(NTK_CLIPBOARD_CONTENT_MULTI_REPRESENTATION))
        value.representations = array([representation(c("com.example.a"), [1]), representation(c("com.example.b"), [2, 3])])
        value.representation_count = 2
        XCTAssertEqual(copy(value, to: scope), ClipboardErrorValue.none)
        XCTAssertEqual(readData("com.example.a", scope), [1])
        XCTAssertEqual(readData("com.example.b", scope), [2, 3])
        let handle = snapshot(scope)
        defer { ntk_clipboard_snapshot_free(handle) }
        XCTAssertEqual(ntk_clipboard_snapshot_number_of_items(handle), 1)
        XCTAssertEqual(ntk_clipboard_snapshot_item_type_count(handle, 0), 2)
    }

    func testTheDuplicateRepresentationIsRejectedAtTheEntry() {
        let scope = makeNamedPasteboard()
        var scopeValue = scope
        var value = content(Int(NTK_CLIPBOARD_CONTENT_MULTI_REPRESENTATION))
        value.representations = array([representation(c("com.example.a"), [1]), representation(c("com.example.a"), [2])])
        value.representation_count = 2
        let recorder = ClipboardRecorder()
        assertRejected(recorder, ntk_clipboard_copy_async(&value, nil, &scopeValue, recordDone, recorder.userData, recordRelease), ClipboardErrorValue.invalidParameter)
    }

    func testAppending() {
        let scope = makeNamedPasteboard()
        XCTAssertEqual(copy(plainText("first"), to: scope), ClipboardErrorValue.none)
        var scopeValue = scope
        var value = plainText("second")
        let appended = completion { ntk_clipboard_append_async(&value, &scopeValue, recordDone, $0.userData, recordRelease) }
        XCTAssertEqual(appended?.error, ClipboardErrorValue.none)
        let handle = readItems(scope)
        defer { ntk_clipboard_read_result_free(handle) }
        XCTAssertEqual(ntk_clipboard_read_result_item_count(handle), 2)
        XCTAssertEqual(text(ntk_clipboard_read_result_item_text_at(handle, 1, nil)), "second")
    }

    func testClearing() {
        let scope = makeNamedPasteboard()
        XCTAssertEqual(copy(plainText("first"), to: scope), ClipboardErrorValue.none)
        var scopeValue = scope
        XCTAssertEqual(completion { ntk_clipboard_clear_async(&scopeValue, recordDone, $0.userData, recordRelease) }?.error, ClipboardErrorValue.none)
        let handle = readItems(scope)
        defer { ntk_clipboard_read_result_free(handle) }
        XCTAssertEqual(ntk_clipboard_read_result_item_count(handle), 0)
    }

    // MARK: - What the library says, in the completion (AP-19)

    private func assertCopy(_ value: ntk_clipboard_write_content, options: ntk_clipboard_copy_options? = nil, fails expected: Int32,
                            file: StaticString = #filePath, line: UInt = #line) {
        let scope = makeNamedPasteboard(file: file, line: line)
        XCTAssertEqual(copy(value, options: options, to: scope), expected, file: file, line: line)
    }

    func testTheContentFailuresComeInTheCompletion() {
        var html = content(Int(NTK_CLIPBOARD_CONTENT_HTML))
        html.html = c("  ")
        assertCopy(html, fails: ClipboardErrorValue.emptyContent)

        var url = content(Int(NTK_CLIPBOARD_CONTENT_URL))
        url.url = c("ftp://example.com")
        assertCopy(url, fails: ClipboardErrorValue.invalidURI)

        var file = content(Int(NTK_CLIPBOARD_CONTENT_IMAGE_FILE))
        file.path = c("/no/such/file.png")
        assertCopy(file, fails: ClipboardErrorValue.fileNotFound)

        var color = content(Int(NTK_CLIPBOARD_CONTENT_COLOR))
        color.red = 2
        color.alpha = 1
        assertCopy(color, fails: ClipboardErrorValue.invalidColor)

        var image = content(Int(NTK_CLIPBOARD_CONTENT_IMAGE_DATA))
        image.ut_type = c("public.png")
        assertCopy(image, fails: ClipboardErrorValue.emptyContent)
        image.data = array([1, 2, 3])
        image.data_size = 3
        assertCopy(image, fails: ClipboardErrorValue.invalidImageData)

        var custom = content(Int(NTK_CLIPBOARD_CONTENT_CUSTOM_DATA))
        custom.ut_type = c("")
        custom.data = array([1])
        custom.data_size = 1
        assertCopy(custom, fails: ClipboardErrorValue.invalidType)
    }

    func testAnExpirationInThePastIsInTheCompletion() {
        var past = options()
        past.has_expiration = 1
        past.expiration_unix_seconds = 1
        assertCopy(plainText("x"), options: past, fails: ClipboardErrorValue.invalidExpiration)
    }

    func testOptionsThatAreGoodAreAccepted() {
        let scope = makeNamedPasteboard()
        var future = options()
        future.has_expiration = 1
        future.expiration_unix_seconds = Date(timeIntervalSinceNow: 3600).timeIntervalSince1970
        future.not_local_only = 1
        XCTAssertEqual(copy(plainText("x"), options: future, to: scope), ClipboardErrorValue.none)
        let handle = readItems(scope)
        defer { ntk_clipboard_read_result_free(handle) }
        XCTAssertEqual(text(ntk_clipboard_read_result_item_text_at(handle, 0, nil)), "x")
    }

    func testAPasteboardThatIsNotThereIsUnavailable() {
        let scope = named("ntk.capi.tests.notcreated.\(UUID().uuidString)")
        XCTAssertEqual(copy(plainText("x"), to: scope), ClipboardErrorValue.unavailable)
        var scopeValue = scope
        let read = completion { ntk_clipboard_read_async(&scopeValue, recordHandle, $0.userData, recordRelease) }
        XCTAssertEqual(read?.error, ClipboardErrorValue.unavailable)
        XCTAssertNil(read?.handle)
        let data = completion { ntk_clipboard_read_data_async(c("public.png"), &scopeValue, recordHandle, $0.userData, recordRelease) }
        XCTAssertEqual(data?.error, ClipboardErrorValue.unavailable)
        XCTAssertNil(data?.handle)
        let snap = completion { ntk_clipboard_get_snapshot_async(nil, 0, &scopeValue, recordHandle, $0.userData, recordRelease) }
        XCTAssertEqual(snap?.error, ClipboardErrorValue.unavailable)
        XCTAssertNil(snap?.handle)
        let clear = completion { ntk_clipboard_clear_async(&scopeValue, recordDone, $0.userData, recordRelease) }
        XCTAssertEqual(clear?.error, ClipboardErrorValue.unavailable)
        let patterns = completion { ntk_clipboard_detect_patterns_async(1, &scopeValue, recordPatterns, $0.userData, recordRelease) }
        XCTAssertEqual(patterns?.error, ClipboardErrorValue.unavailable)
        XCTAssertEqual(patterns?.value, 0)
        let values = completion { ntk_clipboard_detect_values_async(1, &scopeValue, recordHandle, $0.userData, recordRelease) }
        XCTAssertEqual(values?.error, ClipboardErrorValue.unavailable)
        XCTAssertNil(values?.handle)
    }

    func testAFailedCreationGivesNoName() {
        let created = completion { ntk_clipboard_create_pasteboard_async(Int32(NTK_CLIPBOARD_SCOPE_NAMED), c("   "), recordHandle, $0.userData, recordRelease) }
        XCTAssertEqual(created?.error, ClipboardErrorValue.invalidName)
        XCTAssertNil(created?.handle)
    }

    // MARK: - Reading

    func testReadDataGivesNullWhenThereIsNoItemOfTheType() {
        let scope = makeNamedPasteboard()
        XCTAssertEqual(copy(plainText("x"), to: scope), ClipboardErrorValue.none)
        var scopeValue = scope
        let result = completion { ntk_clipboard_read_data_async(c("com.example.absent"), &scopeValue, recordHandle, $0.userData, recordRelease) }
        XCTAssertEqual(result?.error, ClipboardErrorValue.none)
        XCTAssertNil(result?.handle)
    }

    func testReadDataOfAnEmptyTypeIsInTheCompletion() {
        let scope = makeNamedPasteboard()
        var scopeValue = scope
        let result = completion { ntk_clipboard_read_data_async(c(""), &scopeValue, recordHandle, $0.userData, recordRelease) }
        XCTAssertEqual(result?.error, ClipboardErrorValue.invalidType)
        XCTAssertNil(result?.handle)
    }

    func testTheSnapshotDoesNotMatchWithoutTypes() {
        let scope = makeNamedPasteboard()
        XCTAssertEqual(copy(plainText("x"), to: scope), ClipboardErrorValue.none)
        var scopeValue = scope
        let unused = array([Optional(unreadable(CChar.self))])
        for (types, count) in [(nil, 0), (unused, 0)] as [(UnsafePointer<UnsafePointer<CChar>?>?, Int)] {
            let result = completion { ntk_clipboard_get_snapshot_async(types, count, &scopeValue, recordHandle, $0.userData, recordRelease) }
            XCTAssertEqual(ntk_clipboard_snapshot_has_matching(result?.handle), 0)
            XCTAssertEqual(ntk_clipboard_snapshot_matching_count(result?.handle), 0)
            XCTAssertEqual(ntk_clipboard_snapshot_matching_at(result?.handle, 0), -1)
            XCTAssertEqual(ntk_clipboard_snapshot_has_strings(result?.handle), 1)
            ntk_clipboard_snapshot_free(result?.handle)
        }
    }

    func testTheSnapshotMatches() {
        let scope = makeNamedPasteboard()
        var value = content(Int(NTK_CLIPBOARD_CONTENT_MULTIPLE_TEXT))
        value.texts = array([c("first"), c("second")] as [UnsafePointer<CChar>?])
        value.text_count = 2
        XCTAssertEqual(copy(value, to: scope), ClipboardErrorValue.none)

        let matched = snapshot(scope, matching: ["public.plain-text"])
        defer { ntk_clipboard_snapshot_free(matched) }
        XCTAssertEqual(ntk_clipboard_snapshot_number_of_items(matched), 2)
        XCTAssertEqual(ntk_clipboard_snapshot_has_matching(matched), 1)
        XCTAssertEqual(ntk_clipboard_snapshot_matching_count(matched), 2)
        XCTAssertEqual(ntk_clipboard_snapshot_matching_at(matched, 0), 0)
        XCTAssertEqual(ntk_clipboard_snapshot_matching_at(matched, 1), 1)
        XCTAssertEqual(ntk_clipboard_snapshot_matching_at(matched, 2), -1)

        let none = snapshot(scope, matching: ["com.example.absent"])
        defer { ntk_clipboard_snapshot_free(none) }
        XCTAssertEqual(ntk_clipboard_snapshot_has_matching(none), 1)
        XCTAssertEqual(ntk_clipboard_snapshot_matching_count(none), 0)
    }

    // MARK: - Pasteboards

    func testCreatingAndRemovingANamedPasteboard() {
        let name = "ntk.capi.tests.\(UUID().uuidString)"
        let created = completion { ntk_clipboard_create_pasteboard_async(Int32(NTK_CLIPBOARD_SCOPE_NAMED), c(name), recordHandle, $0.userData, recordRelease) }
        XCTAssertEqual(created?.error, ClipboardErrorValue.none)
        XCTAssertEqual(text(ntk_string_data(created?.handle)), name)
        ntk_string_free(created?.handle)

        var scope = named(name)
        XCTAssertEqual(copy(plainText("x"), to: scope), ClipboardErrorValue.none)
        XCTAssertEqual(completion { ntk_clipboard_remove_pasteboard_async(&scope, recordDone, $0.userData, recordRelease) }?.error, ClipboardErrorValue.none)
        XCTAssertEqual(copy(plainText("x"), to: scope), ClipboardErrorValue.unavailable)
    }

    func testAUniquePasteboardGivesItsNameToUseAsAScope() {
        let created = completion { ntk_clipboard_create_pasteboard_async(Int32(NTK_CLIPBOARD_SCOPE_UNIQUE), nil, recordHandle, $0.userData, recordRelease) }
        XCTAssertEqual(created?.error, ClipboardErrorValue.none)
        let name = text(ntk_string_data(created?.handle)) ?? ""
        ntk_string_free(created?.handle)
        XCTAssertFalse(name.isEmpty)

        var scope = zeroScope()
        scope.kind = Int32(NTK_CLIPBOARD_SCOPE_UNIQUE)
        scope.name = c(name)
        XCTAssertEqual(copy(plainText("x"), to: scope), ClipboardErrorValue.none)
        XCTAssertEqual(completion { ntk_clipboard_remove_pasteboard_async(&scope, recordDone, $0.userData, recordRelease) }?.error, ClipboardErrorValue.none)
    }

    /// This reaches no pasteboard: the library stops at the scope.
    func testTheGeneralPasteboardCannotBeRemoved() {
        var scope = zeroScope()
        XCTAssertEqual(completion { ntk_clipboard_remove_pasteboard_async(&scope, recordDone, $0.userData, recordRelease) }?.error,
                       ClipboardErrorValue.cannotRemoveGeneral)
    }

    func testRemovingANameThatIsNotThereSucceeds() {
        var scope = named("ntk.capi.tests.absent.\(UUID().uuidString)")
        XCTAssertEqual(completion { ntk_clipboard_remove_pasteboard_async(&scope, recordDone, $0.userData, recordRelease) }?.error, ClipboardErrorValue.none)
    }

    // MARK: - Detection

    func testDetectingPatterns() {
        let scope = makeNamedPasteboard()
        XCTAssertEqual(copy(plainText("https://example.com/a"), to: scope), ClipboardErrorValue.none)
        var scopeValue = scope
        let wanted = UInt32(NTK_CLIPBOARD_PATTERN_PROBABLE_WEB_URL) | UInt32(NTK_CLIPBOARD_PATTERN_NUMBER)
        let result = completion { ntk_clipboard_detect_patterns_async(wanted, &scopeValue, recordPatterns, $0.userData, recordRelease) }
        XCTAssertEqual(result?.error, ClipboardErrorValue.none)
        XCTAssertEqual(result.map { UInt32(bitPattern: $0.value) }, UInt32(NTK_CLIPBOARD_PATTERN_PROBABLE_WEB_URL))
    }

    func testDetectingValues() throws {
        let scope = makeNamedPasteboard()
        XCTAssertEqual(copy(plainText("https://example.com/a"), to: scope), ClipboardErrorValue.none)
        var scopeValue = scope
        let result = completion { ntk_clipboard_detect_values_async(UInt32(NTK_CLIPBOARD_PATTERN_PROBABLE_WEB_URL), &scopeValue, recordHandle, $0.userData, recordRelease) }
        XCTAssertEqual(result?.error, ClipboardErrorValue.none)
        defer { ntk_string_free(result?.handle) }
        let json = try XCTUnwrap(text(ntk_string_data(result?.handle)))
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(json.utf8)) as? [String: Any])
        XCTAssertEqual(object["probableWebURL"] as? String, "https://example.com/a")
        XCTAssertEqual(object["detectedPatterns"] as? [String], ["probableWebURL"])
        XCTAssertEqual(Set(object.keys), ["detectedPatterns", "probableWebURL", "probableWebSearch", "number", "links", "emailAddresses", "phoneNumbers",
                                          "postalAddresses", "calendarEvents", "flightNumbers", "moneyAmounts", "shipmentTrackingNumbers"])
    }

    // MARK: - The change count

    /// The first check gives 0, a change gives 1 once, and a pasteboard that cannot be resolved gives 0.
    func testCheckingForAChange() {
        let scope = makeNamedPasteboard()
        var scopeValue = scope
        func check() -> Int32? {
            let result = completion { ntk_clipboard_check_foreground_change_async(&scopeValue, recordChanged, $0.userData, recordRelease) }
            XCTAssertEqual(result?.error, ClipboardErrorValue.none)
            return result?.value
        }
        XCTAssertEqual(check(), 0)
        XCTAssertEqual(copy(plainText("x"), to: scope), ClipboardErrorValue.none)
        XCTAssertEqual(check(), 1)
        XCTAssertEqual(check(), 0)
    }

    func testCheckingAPasteboardThatIsNotThereGivesZero() {
        var scope = named("ntk.capi.tests.notcreated.\(UUID().uuidString)")
        let result = completion { ntk_clipboard_check_foreground_change_async(&scope, recordChanged, $0.userData, recordRelease) }
        XCTAssertEqual(result?.error, ClipboardErrorValue.none)
        XCTAssertEqual(result?.value, 0)
    }
}
