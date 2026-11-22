//
//  ShareTests.swift
//  IosLibraryCApiTests
//

import Foundation
import XCTest
@testable import IosLibrary
@testable import IosLibraryCApi

/// Share.h through C, **without showing a sheet** (these tests also run on the private device under ASan): the
/// receiver's `Sharing` is replaced in `setUp` by one that fails the test, and a test that accepts a share installs
/// a fake that completes as the library would. Showing the sheet is in the UI tests.
final class ShareTests: ClipboardTestCase {
    private let none: Int32 = 0
    private let invalid: Int32 = 1
    private let notSupported: Int32 = 3
    private let emptyContent: Int32 = 7
    private var recorders: [ClipboardRecorder] = []

    private static let failing = ShareReceiver.Sharing { _, completion in
        XCTFail("a share reached the library without a fake")
        completion(.failure(.presentationFailed))
    }

    override func setUpWithError() throws {
        try super.setUpWithError()
        ShareReceiver.sharing = Self.failing
    }

    /// The failing `Sharing` is put back and stays after this class: nothing else in this process shares.
    override func tearDown() async throws {
        ShareReceiver.sharing = Self.failing
        try await super.tearDown()
    }

    private func kept() -> ClipboardRecorder {
        let recorder = ClipboardRecorder()
        recorders.append(recorder)
        return recorder
    }

    private func sized<Value>(_ value: Value, _ set: (inout Value) -> Void = { _ in }) -> Value {
        var result = value
        withUnsafeMutableBytes(of: &result) { $0.storeBytes(of: UInt32(MemoryLayout<Value>.size), as: UInt32.self) }
        set(&result)
        return result
    }

    private func item(_ kind: Int32, _ value: UnsafePointer<CChar>?) -> ntk_share_item {
        sized(ntk_share_item()) {
            $0.kind = kind
            $0.value = value
        }
    }

    private func request(_ items: [ntk_share_item], _ set: (inout ntk_share_request) -> Void = { _ in }) -> ntk_share_request {
        sized(ntk_share_request()) {
            $0.items = items.isEmpty ? nil : array(items)
            $0.item_count = items.count
            set(&$0)
        }
    }

    private var textKind: Int32 { Int32(NTK_SHARE_ITEM_TEXT) }

    // MARK: - Rejected at the entry

    private func assertRejected(_ name: String, expected: Int32 = 1, file: StaticString = #filePath, line: UInt = #line,
                                _ call: (UnsafeMutableRawPointer) -> Int32) {
        let recorder = kept()
        XCTAssertEqual(call(recorder.userData), expected, name, file: file, line: line)
        XCTAssertEqual(recorder.releases, [true], name, file: file, line: line)
        runMainQueue(file: file, line: line)
        XCTAssertEqual(recorder.calls, ["release"], name, file: file, line: line)
    }

    private func assertRejected(_ name: String, expected: Int32 = 1, file: StaticString = #filePath, line: UInt = #line,
                                request value: ntk_share_request) {
        let pointer = array([value])
        assertRejected(name, expected: expected, file: file, line: line) { ntk_share_content_async(pointer, recordHandle, $0, recordRelease) }
    }

    func testANullCallbackOrRequestIsRejected() {
        let valid = array([request([item(textKind, c("t"))])])
        assertRejected("NULL callback") { ntk_share_content_async(valid, nil, $0, recordRelease) }
        assertRejected("NULL request") { ntk_share_content_async(nil, recordHandle, $0, recordRelease) }
        XCTAssertEqual(ntk_share_content_async(nil, nil, nil, nil), invalid, "without a release")
        XCTAssertEqual(ntk_last_system_code(), 0)
    }

    func testARejectionOffTheMainThreadReleasesOnThatThread() {
        let recorder = kept()
        XCTAssertEqual(onAnotherThread { ntk_share_content_async(nil, recordHandle, recorder.userData, recordRelease) }, invalid)
        XCTAssertEqual(recorder.releases, [false])
        runMainQueue()
    }

    /// AP-19: no item is the return value EMPTY_CONTENT, also with a NULL array, before anything else is read.
    func testNoItemIsEmptyContent() {
        assertRejected("no item", expected: emptyContent, request: request([]))
        assertRejected("no item, unreadable array", expected: emptyContent, request: request([]) { $0.items = unreadable() })
    }

    func testTheItemsAreChecked() {
        assertRejected("NULL array with a count", request: request([]) { $0.item_count = 1 })
        assertRejected("kind out of range", request: request([item(4, c("v"))]))
        assertRejected("negative kind", request: request([item(-1, c("v"))]))
        assertRejected("NULL value", request: request([item(textKind, nil)]))
        for bytes in invalidUTF8 {
            assertRejected("value \(bytes)", request: request([item(textKind, raw(bytes))]))
            assertRejected("subject \(bytes)", request: request([item(textKind, c("t"))]) { $0.subject = self.raw(bytes) })
            assertRejected("preview title \(bytes)", request: request([item(textKind, c("t"))]) { $0.preview_title = self.raw(bytes) })
        }
        assertRejected("item reserved1", request: request([sized(item(textKind, c("t"))) { $0.reserved1 = 1 }]))
        assertRejected("a count that does not fit", request: request([item(textKind, c("t"))]) { $0.item_count = .max })
    }

    func testTheExcludedTypesAreChecked() {
        assertRejected("NULL array with a count", request: request([item(textKind, c("t"))]) { $0.excluded_activity_type_count = 1 })
        let withNull: [UnsafePointer<CChar>?] = [c("a"), nil]
        assertRejected("a NULL type", request: request([item(textKind, c("t"))]) {
            $0.excluded_activity_types = self.array(withNull)
            $0.excluded_activity_type_count = 2
        })
    }

    func testTheStructRules() {
        var small = request([item(textKind, c("t"))])
        small.struct_size = 8
        assertRejected("small request", request: small)
        var smallItem = item(textKind, c("t"))
        smallItem.struct_size = 8
        assertRejected("small item", request: request([smallItem]))
        let size = MemoryLayout<ntk_share_request>.size
        let memory = UnsafeMutableRawPointer.allocate(byteCount: size + 8, alignment: 8)
        defer { memory.deallocate() }
        memory.initializeMemory(as: UInt8.self, repeating: 0, count: size + 8)
        var base = request([item(textKind, c("t"))])
        base.struct_size = UInt32(size + 8)
        memory.storeBytes(of: base, as: ntk_share_request.self)
        memory.storeBytes(of: UInt8(1), toByteOffset: size + 7, as: UInt8.self)
        let pointer = UnsafePointer(memory.assumingMemoryBound(to: ntk_share_request.self))
        assertRejected("unknown tail", expected: notSupported) { ntk_share_content_async(pointer, recordHandle, $0, recordRelease) }
    }

    // MARK: - The mapping

    private func describe(_ item: ShareItem) -> String {
        switch item {
        case .text(let value): return "text(\(value))"
        case .url(let value): return "url(\(value))"
        case .imageFile(let path): return "image(\(path))"
        case .file(let path): return "file(\(path))"
        @unknown default: return "unknown"
        }
    }

    func testAZeroFilledRequestOfEachKind() throws {
        let rows: [(Int, String)] = [(Int(NTK_SHARE_ITEM_TEXT), "text(v)"), (Int(NTK_SHARE_ITEM_URL), "url(v)"),
                                     (Int(NTK_SHARE_ITEM_IMAGE_FILE), "image(v)"), (Int(NTK_SHARE_ITEM_FILE), "file(v)")]
        for (kind, expected) in rows {
            var value = request([item(Int32(kind), c("v"))])
            let content = try ShareMapping.content(&value)
            XCTAssertEqual(content.items.map(describe), [expected])
            XCTAssertNil(content.subject)
            XCTAssertNil(content.previewTitle)
            XCTAssertEqual(content.excludedActivityTypes, [])
        }
    }

    func testAFullRequest() throws {
        let types: [UnsafePointer<CChar>?] = [c("com.apple.UIKit.activity.Print"), c("")]
        var value = request([item(textKind, c("")), item(Int32(NTK_SHARE_ITEM_URL), c("https://example.com"))]) {
            $0.subject = self.c("S")
            $0.preview_title = self.c("")
            $0.excluded_activity_types = self.array(types)
            $0.excluded_activity_type_count = 2
        }
        let content = try ShareMapping.content(&value)
        XCTAssertEqual(content.items.map(describe), ["text()", "url(https://example.com)"], "an empty text is the library's to judge")
        XCTAssertEqual(content.subject, "S")
        XCTAssertEqual(content.previewTitle, "")
        XCTAssertEqual(content.excludedActivityTypes, ["com.apple.UIKit.activity.Print", ""])
    }

    /// 11.4, every case written out.
    func testEveryShareError() {
        let detail = FailureDetail(domain: "d", code: 1)
        let rows: [(ShareError, Int32)] = [
            (.noValidItems, 7), (.invalidURL("u"), 17), (.imageLoadFailed(path: "p"), 18), (.fileNotFound(path: "p"), 9),
            (.noRootViewController, 6), (.notForeground, 6), (.presentationFailed, 19), (.dismissedBySystem, 20), (.activityFailed(detail), 21),
        ]
        for (failure, value) in rows {
            XCTAssertEqual(ShareMapping.error(for: failure), value, "\(failure)")
        }
    }

    // MARK: - Accepted, with a fake

    @MainActor
    private final class FakeSharing {
        var contents: [ShareContent] = []
        var outcome: Result<ShareResult, ShareError> = .success(ShareResult(completed: false, activityType: nil))

        var sharing: ShareReceiver.Sharing {
            ShareReceiver.Sharing { [self] content, completion in
                contents.append(content)
                completion(outcome)
            }
        }
    }

    private func completed(_ outcome: Result<ShareResult, ShareError>, file: StaticString = #filePath, line: UInt = #line)
        -> (FakeSharing, ClipboardRecorder.Completion?) {
        let fake = FakeSharing()
        fake.outcome = outcome
        ShareReceiver.sharing = fake.sharing
        let recorder = kept()
        let value = array([request([item(textKind, c("t"))])])
        XCTAssertEqual(ntk_share_content_async(value, recordHandle, recorder.userData, recordRelease), none, file: file, line: line)
        recorder.markReturned()
        XCTAssertEqual(recorder.calls, [], file: file, line: line)
        let completion = finished(recorder, file: file, line: line)
        XCTAssertEqual(completion?.afterReturn, true, file: file, line: line)
        return (fake, completion)
    }

    func testACompletedShare() {
        let (_, completion) = completed(.success(ShareResult(completed: true, activityType: "com.apple.UIKit.activity.CopyToPasteboard")))
        XCTAssertEqual(completion?.error, none)
        defer { ntk_share_result_free(completion?.handle) }
        XCTAssertEqual(ntk_share_result_completed(completion?.handle), 1)
        var size = 0
        XCTAssertEqual(text(ntk_share_result_activity_type(completion?.handle, &size)), "com.apple.UIKit.activity.CopyToPasteboard")
        XCTAssertEqual(size, "com.apple.UIKit.activity.CopyToPasteboard".utf8.count)
    }

    func testAClosedSheet() {
        let (_, completion) = completed(.success(ShareResult(completed: false, activityType: nil)))
        XCTAssertEqual(completion?.error, none)
        defer { ntk_share_result_free(completion?.handle) }
        XCTAssertNotNil(completion?.handle)
        XCTAssertEqual(ntk_share_result_completed(completion?.handle), 0)
        var size = 9
        XCTAssertNil(ntk_share_result_activity_type(completion?.handle, &size))
        XCTAssertEqual(size, 0)
    }

    func testAFailureHasNoResult() {
        let (_, completion) = completed(.failure(.notForeground))
        XCTAssertEqual(completion?.error, 6)
        XCTAssertNil(completion?.handle)
    }

    /// The caller may free its strings once the function returns (part 1, 1.1).
    func testTheContentIsCopiedAtTheCall() {
        let fake = FakeSharing()
        ShareReceiver.sharing = fake.sharing
        let value = strdup("before")!
        let recorder = kept()
        var raw = request([item(textKind, UnsafePointer(value))])
        XCTAssertEqual(ntk_share_content_async(&raw, recordHandle, recorder.userData, recordRelease), none)
        strcpy(value, "after!")
        free(value)
        ntk_share_result_free(finished(recorder)?.handle)
        XCTAssertEqual(fake.contents.first?.items.map(describe), ["text(before)"])
    }

    func testTheReadersOfNothing() {
        let other = Handle.makeString("another type")
        defer { ntk_string_free(other) }
        for handle in [nil, other] {
            XCTAssertEqual(ntk_share_result_completed(handle), 0)
            var size = 9
            XCTAssertNil(ntk_share_result_activity_type(handle, &size))
            XCTAssertEqual(size, 0)
        }
        ntk_share_result_free(nil)
    }

    // MARK: - Review fixes (TB-9)

    private func mappingRejection(_ pointer: UnsafePointer<ntk_share_request>?) -> ShareRejection? {
        do throws(ShareRejection) {
            _ = try ShareMapping.content(pointer)
            return nil
        } catch {
            return error
        }
    }

    /// As Dialog's `assertTheStructRules`: NULL, reserved0 of the request and of an item, a struct_size too small and
    /// above 4096, an unknown part of 0 accepted and of anything else NOT_SUPPORTED.
    func testTheStructRulesOfTheRequestAndTheItem() throws {
        XCTAssertEqual(mappingRejection(nil), .entry(.invalidParameter))
        var reservedRequest = request([item(textKind, c("t"))]) { $0.reserved0 = 1 }
        XCTAssertEqual(mappingRejection(&reservedRequest), .entry(.invalidParameter), "request reserved0")
        var reservedItem = request([sized(item(textKind, c("t"))) { $0.reserved0 = 1 }])
        XCTAssertEqual(mappingRejection(&reservedItem), .entry(.invalidParameter), "item reserved0")
        let base = request([item(textKind, c("t"))])
        let size = MemoryLayout<ntk_share_request>.size
        let memory = UnsafeMutableRawPointer.allocate(byteCount: size + 8, alignment: 8)
        defer { memory.deallocate() }
        func prepared(structSize: Int) -> UnsafePointer<ntk_share_request> {
            memory.initializeMemory(as: UInt8.self, repeating: 0, count: size + 8)
            withUnsafeBytes(of: base) { memory.copyMemory(from: $0.baseAddress!, byteCount: size) }
            memory.storeBytes(of: UInt32(structSize), as: UInt32.self)
            return UnsafePointer(memory.assumingMemoryBound(to: ntk_share_request.self))
        }
        XCTAssertEqual(mappingRejection(prepared(structSize: 4097)), .entry(.invalidParameter), "above 4096")
        XCTAssertNil(mappingRejection(prepared(structSize: size + 8)), "the unknown part is 0")
        memory.storeBytes(of: UInt8(1), toByteOffset: size + 7, as: UInt8.self)
        XCTAssertEqual(mappingRejection(UnsafePointer(memory.assumingMemoryBound(to: ntk_share_request.self))), .entry(.notSupported))
    }

    /// P2-5: the items are stepped by their own struct_size, and an array of mixed sizes is rejected.
    func testTheItemsAreSteppedByTheirOwnSize() throws {
        let known = MemoryLayout<ntk_share_item>.size
        let wide = known + 8
        let memory = UnsafeMutableRawPointer.allocate(byteCount: wide * 2, alignment: 8)
        defer { memory.deallocate() }
        memory.initializeMemory(as: UInt8.self, repeating: 0, count: wide * 2)
        for (index, value) in ["a", "b"].enumerated() {
            var element = item(textKind, c(value))
            element.struct_size = UInt32(wide)
            memory.advanced(by: index * wide).copyMemory(from: &element, byteCount: known)
        }
        var value = request([]) {
            $0.items = UnsafePointer(memory.assumingMemoryBound(to: ntk_share_item.self))
            $0.item_count = 2
        }
        XCTAssertEqual(try ShareMapping.content(&value).items.map(describe), ["text(a)", "text(b)"])
        memory.storeBytes(of: UInt8(1), toByteOffset: wide + known, as: UInt8.self)
        XCTAssertEqual(mappingRejection(&value), .entry(.notSupported), "the unknown part of an element")
        // Mixed sizes: the second element is the known size.
        memory.storeBytes(of: UInt8(0), toByteOffset: wide + known, as: UInt8.self)
        memory.storeBytes(of: UInt32(known), toByteOffset: wide, as: UInt32.self)
        XCTAssertEqual(mappingRejection(&value), .entry(.invalidParameter), "mixed sizes")
    }

    func testAnExcludedTypeMustBeUTF8() {
        for bytes in invalidUTF8 {
            let types: [UnsafePointer<CChar>?] = [raw(bytes)]
            assertRejected("excluded \(bytes)", request: request([item(textKind, c("t"))]) {
                $0.excluded_activity_types = self.array(types)
                $0.excluded_activity_type_count = 1
            })
        }
    }

    /// A count of -1 (SIZE_MAX) or one whose size overflows is INVALID_PARAMETER, not EMPTY_CONTENT.
    func testCountsThatDoNotFit() {
        let tooFar = Int(bitPattern: UInt.max)
        for count in [tooFar, 1 << 61] {
            assertRejected("items \(count)", request: request([item(textKind, c("t"))]) { $0.item_count = count })
            assertRejected("excluded \(count)", request: request([item(textKind, c("t"))]) {
                $0.excluded_activity_types = self.array([Optional(unreadable(CChar.self))])
                $0.excluded_activity_type_count = count
            })
        }
    }

    /// C-2: a kind out of range is rejected without reading the value.
    func testAnItemOfAKindOutOfRangeIsNotRead() {
        assertRejected("kind 4, unreadable value", request: request([item(4, unreadable())]))
    }

    /// From another thread while the main thread waits: NONE at once, nothing inside the call, and then one
    /// completion and one release on the main thread (as DialogEntryTests).
    func testAnAcceptedShareOffTheMainThreadDoesNotWaitForIt() {
        let fake = FakeSharing()
        ShareReceiver.sharing = fake.sharing
        let recorder = kept()
        nonisolated(unsafe) let value = array([request([item(textKind, c("t"))])])
        XCTAssertEqual(onAnotherThread { ntk_share_content_async(value, recordHandle, recorder.userData, recordRelease) }, none)
        XCTAssertEqual(recorder.calls, [])
        let completion = finished(recorder)
        XCTAssertEqual(completion?.error, none)
        ntk_share_result_free(completion?.handle)
        XCTAssertEqual(fake.contents.count, 1)
    }

    /// The completions a fake keeps until the test calls them.
    @MainActor
    private final class PendingShares {
        var completions: [@MainActor @Sendable (Result<ShareResult, ShareError>) -> Void] = []
    }

    /// Two shares at once, completed in the other order: each gets its own result, one completion and one release
    /// each, the release after the callback returned.
    func testTwoSharesCompletedInTheOtherOrder() {
        let holder = PendingShares()
        ShareReceiver.sharing = ShareReceiver.Sharing { _, completion in holder.completions.append(completion) }
        let first = kept()
        let second = kept()
        for recorder in [first, second] {
            recorder.onCompletion = { [weak recorder] _ in
                XCTAssertEqual(recorder?.releases, [], "released before the callback returned")
            }
        }
        let value = array([request([item(textKind, c("t"))])])
        XCTAssertEqual(ntk_share_content_async(value, recordHandle, first.userData, recordRelease), none)
        XCTAssertEqual(ntk_share_content_async(value, recordHandle, second.userData, recordRelease), none)
        runMainQueue()
        let pending = holder.completions
        XCTAssertEqual(pending.count, 2)
        pending[1](.success(ShareResult(completed: true, activityType: "second")))
        pending[0](.success(ShareResult(completed: false, activityType: nil)))
        // The readers give 0 and NULL for a NULL handle too, so each result is checked to be a real one.
        XCTAssertNotEqual(first.completions.first?.handle, second.completions.first?.handle)
        for (recorder, activity, completed) in [(second, "second", Int32(1)), (first, nil, 0)] as [(ClipboardRecorder, String?, Int32)] {
            XCTAssertEqual(recorder.calls, ["completion", "release"])
            XCTAssertEqual(recorder.releases, [true])
            XCTAssertEqual(recorder.completions.first?.error, none)
            let handle = recorder.completions.first?.handle
            XCTAssertNotNil(handle)
            XCTAssertEqual(ntk_share_result_completed(handle), completed)
            XCTAssertEqual(text(ntk_share_result_activity_type(handle, nil)), activity)
            ntk_share_result_free(handle)
        }
    }

    /// C-5: an empty activity type is "" with out_size 0, not NULL; U+0000 comes back as U+FFFD.
    func testTheActivityTypeOutput() {
        let empty = ShareHandles.makeResult(ShareResultValue(completed: true, activityType: ""))
        let withNul = ShareHandles.makeResult(ShareResultValue(completed: true, activityType: "a\u{0}b"))
        defer {
            ntk_share_result_free(empty)
            ntk_share_result_free(withNul)
        }
        var size = 9
        XCTAssertEqual(text(ntk_share_result_activity_type(empty, &size)), "")
        XCTAssertEqual(size, 0)
        XCTAssertEqual(text(ntk_share_result_activity_type(withNul, nil)), "a\u{FFFD}b")
    }
}
