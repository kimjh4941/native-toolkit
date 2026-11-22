//
//  ClipboardTestSupport.swift
//  IosLibraryCApiTests
//

import Foundation
import XCTest
@testable import IosLibraryCApi

// What the Clipboard tests share. These tests also run on the private device under ASan (part 2, 12.2), so
// **whatever reaches a pasteboard uses a named one**: nothing here writes or reads the general pasteboard.
// A NULL scope goes to `ClipboardMapping` or is rejected before it is used.

/// What the C callbacks of Clipboard.h saw.
final class ClipboardRecorder: @unchecked Sendable {
    struct Completion {
        let error: Int32
        let systemCode: UInt32
        let onMain: Bool
        /// Whether the function had returned, when the test says so through `markReturned`.
        let afterReturn: Bool
        let handle: OpaquePointer?
        let value: Int32
        let requestID: UInt64
    }

    /// What one event held; the handle is read and freed inside the callback.
    struct Change: Equatable {
        let kind: Int32
        let scopeKind: Int32
        let scopeName: String?
        let added: [String]
        let removed: [String]
        let onMain: Bool
    }

    private let lock = NSLock()
    private var completionList: [Completion] = []
    private var releaseList: [Bool] = []
    private var order: [String] = []
    private var returned = false
    private var changeList: [Change] = []
    private var depth = 0
    private var deepest = 0

    /// Runs inside a load's completion, after it was recorded.
    var onCompletion: (@Sendable (Completion) -> Void)?
    /// Runs inside a change's callback, after it was recorded.
    var onChange: (@Sendable (Change) -> Void)?

    let outListener: UnsafeMutablePointer<OpaquePointer?>

    init() {
        outListener = .allocate(capacity: 1)
        outListener.initialize(to: nil)
    }

    deinit {
        outListener.deallocate()
    }

    var userData: UnsafeMutableRawPointer { Unmanaged.passUnretained(self).toOpaque() }

    static func from(_ userData: UnsafeMutableRawPointer?) -> ClipboardRecorder? {
        userData.map { Unmanaged<ClipboardRecorder>.fromOpaque($0).takeUnretainedValue() }
    }

    var completions: [Completion] { lock.withLock { completionList } }
    var releases: [Bool] { lock.withLock { releaseList } }
    var calls: [String] { lock.withLock { order } }
    var changes: [Change] { lock.withLock { changeList } }
    /// How many change callbacks were on the stack at most.
    var deepestChange: Int { lock.withLock { deepest } }

    func markReturned() {
        lock.withLock { returned = true }
    }

    func record(_ error: Int32, _ systemCode: UInt32, handle: OpaquePointer? = nil, value: Int32 = 0, requestID: UInt64 = 0) {
        let onMain = Thread.isMainThread
        let completion = lock.withLock {
            let completion = Completion(error: error, systemCode: systemCode, onMain: onMain, afterReturn: returned, handle: handle, value: value, requestID: requestID)
            completionList.append(completion)
            order.append("completion")
            return completion
        }
        onCompletion?(completion)
    }

    func recordChange(_ change: Change) {
        lock.withLock {
            changeList.append(change)
            order.append("change")
            depth += 1
            deepest = max(deepest, depth)
        }
        onChange?(change)
        lock.withLock { depth -= 1 }
    }

    func recordRelease() {
        let onMain = Thread.isMainThread
        lock.withLock {
            releaseList.append(onMain)
            order.append("release")
        }
    }
}

func recordDone(_ userData: UnsafeMutableRawPointer?, _ error: Int32, _ systemCode: UInt32) {
    ClipboardRecorder.from(userData)?.record(error, systemCode)
}

func recordHandle(_ userData: UnsafeMutableRawPointer?, _ error: Int32, _ systemCode: UInt32, _ handle: OpaquePointer?) {
    ClipboardRecorder.from(userData)?.record(error, systemCode, handle: handle)
}

func recordPatterns(_ userData: UnsafeMutableRawPointer?, _ error: Int32, _ systemCode: UInt32, _ patterns: UInt32) {
    ClipboardRecorder.from(userData)?.record(error, systemCode, value: Int32(bitPattern: patterns))
}

func recordChanged(_ userData: UnsafeMutableRawPointer?, _ error: Int32, _ systemCode: UInt32, _ changed: Int32) {
    ClipboardRecorder.from(userData)?.record(error, systemCode, value: changed)
}

func recordLoad(_ userData: UnsafeMutableRawPointer?, _ requestID: UInt64, _ error: Int32, _ systemCode: UInt32, _ item: OpaquePointer?) {
    ClipboardRecorder.from(userData)?.record(error, systemCode, handle: item, requestID: requestID)
}

private func strings(_ count: Int, _ at: (Int) -> UnsafePointer<CChar>?) -> [String] {
    (0..<count).compactMap { at($0).map { String(cString: $0) } }
}

/// Reads the handle through C and frees it, as a receiver of the event owns it.
func recordChange(_ userData: UnsafeMutableRawPointer?, _ change: OpaquePointer?) {
    let value = ClipboardRecorder.Change(
        kind: ntk_clipboard_change_kind(change),
        scopeKind: ntk_clipboard_change_scope_kind(change),
        scopeName: ntk_clipboard_change_scope_name(change, nil).map { String(cString: $0) },
        added: strings(ntk_clipboard_change_types_added_count(change)) { ntk_clipboard_change_types_added_at(change, $0, nil) },
        removed: strings(ntk_clipboard_change_types_removed_count(change)) { ntk_clipboard_change_types_removed_at(change, $0, nil) },
        onMain: Thread.isMainThread)
    ntk_clipboard_change_free(change)
    ClipboardRecorder.from(userData)?.recordChange(value)
}

func recordRelease(_ userData: UnsafeMutableRawPointer?) {
    ClipboardRecorder.from(userData)?.recordRelease()
}

/// The numbers of 11.3, written out so that a change of the header does not change the test.
enum ClipboardErrorValue {
    static let none: Int32 = 0
    static let invalidParameter: Int32 = 1
    static let notSupported: Int32 = 3
    static let unknown: Int32 = 4
    static let emptyContent: Int32 = 6
    static let emptyItems: Int32 = 7
    static let invalidURI: Int32 = 8
    static let unavailable: Int32 = 9
    static let emptyPatterns: Int32 = 12
    static let noMatchingItem: Int32 = 23
    static let canceled: Int32 = 27
    static let invalidType: Int32 = 13
    static let invalidName: Int32 = 14
    static let invalidColor: Int32 = 15
    static let invalidImageData: Int32 = 16
    static let invalidExpiration: Int32 = 17
    static let fileNotFound: Int32 = 19
    static let imageLoadFailed: Int32 = 20
    static let cannotRemoveGeneral: Int32 = 22
}

/// A pointer that stops the process when read: a field `kind` does not name must not be read.
func unreadable<Pointee>(_ type: Pointee.Type = Pointee.self) -> UnsafePointer<Pointee> {
    UnsafePointer(bitPattern: 0x10)!
}

/// C values for a test. They live until the end of the test; `free` lets one go earlier.
@MainActor
class ClipboardTestCase: XCTestCase {
    private var texts: [UnsafeMutablePointer<CChar>] = []
    private var buffers: [UnsafeMutableRawPointer] = []
    private var pasteboardNames: [String] = []

    /// The removals run after this: the main queue does not run inside an `async` function on it.
    override func tearDown() async throws {
        for name in pasteboardNames {
            var scope = named(name)
            _ = ntk_clipboard_remove_pasteboard_async(&scope, recordDone, nil, nil)
        }
        pasteboardNames = []
        texts.forEach { free($0) }
        texts = []
        buffers.forEach { $0.deallocate() }
        buffers = []
    }

    func c(_ text: String) -> UnsafePointer<CChar> {
        let copy = strdup(text)!
        texts.append(copy)
        return UnsafePointer(copy)
    }

    /// A NUL-terminated string of exactly these bytes.
    func raw(_ bytes: [UInt8]) -> UnsafePointer<CChar> {
        let copy = UnsafeMutableRawPointer.allocate(byteCount: bytes.count + 1, alignment: 1)
        buffers.append(copy)
        copy.copyMemory(from: bytes + [0], byteCount: bytes.count + 1)
        return UnsafePointer(copy.assumingMemoryBound(to: CChar.self))
    }

    func array<Element>(_ elements: [Element]) -> UnsafePointer<Element> {
        let copy = UnsafeMutablePointer<Element>.allocate(capacity: max(elements.count, 1))
        buffers.append(UnsafeMutableRawPointer(copy))
        copy.initialize(from: elements, count: elements.count)
        return UnsafePointer(copy)
    }

    /// The sequences part 1, chapter 6 names: not UTF-8 by RFC 3629.
    var invalidUTF8: [[UInt8]] {
        [[0xC3, 0x28], [0xED, 0xA0, 0x80], [0xC0, 0xAF], [0xFF], [0xF4, 0x90, 0x80, 0x80]]
    }

    // MARK: Structs

    func named(_ name: String) -> ntk_clipboard_scope {
        var scope = ntk_clipboard_scope()
        scope.struct_size = UInt32(MemoryLayout<ntk_clipboard_scope>.size)
        scope.kind = Int32(NTK_CLIPBOARD_SCOPE_NAMED)
        scope.name = c(name)
        return scope
    }

    func zeroScope() -> ntk_clipboard_scope {
        var scope = ntk_clipboard_scope()
        scope.struct_size = UInt32(MemoryLayout<ntk_clipboard_scope>.size)
        return scope
    }

    func content(_ kind: Int) -> ntk_clipboard_write_content {
        var content = ntk_clipboard_write_content()
        content.struct_size = UInt32(MemoryLayout<ntk_clipboard_write_content>.size)
        content.kind = Int32(kind)
        return content
    }

    func plainText(_ text: String) -> ntk_clipboard_write_content {
        var value = content(Int(NTK_CLIPBOARD_CONTENT_PLAIN_TEXT))
        value.text = c(text)
        return value
    }

    func representation(_ utType: UnsafePointer<CChar>?, _ data: [UInt8]) -> ntk_clipboard_representation {
        var value = ntk_clipboard_representation()
        value.struct_size = UInt32(MemoryLayout<ntk_clipboard_representation>.size)
        value.ut_type = utType
        value.data = array(data)
        value.data_size = data.count
        return value
    }

    func options() -> ntk_clipboard_copy_options {
        var value = ntk_clipboard_copy_options()
        value.struct_size = UInt32(MemoryLayout<ntk_clipboard_copy_options>.size)
        return value
    }

    // MARK: The pasteboard of the test

    /// A named pasteboard, made through C and removed at the end of the test.
    func makeNamedPasteboard(file: StaticString = #filePath, line: UInt = #line) -> ntk_clipboard_scope {
        let name = "ntk.capi.tests.\(UUID().uuidString)"
        let recorder = ClipboardRecorder()
        XCTAssertEqual(ntk_clipboard_create_pasteboard_async(Int32(NTK_CLIPBOARD_SCOPE_NAMED), c(name), recordHandle, recorder.userData, recordRelease),
                       ClipboardErrorValue.none, file: file, line: line)
        let completion = finished(recorder, file: file, line: line)
        XCTAssertEqual(completion?.error, ClipboardErrorValue.none, file: file, line: line)
        ntk_string_free(completion?.handle)
        pasteboardNames.append(name)
        return named(name)
    }

    /// Runs the main thread until the release of an accepted request, and checks what every accepted
    /// request has in common: one completion and then one release, both on the main thread, with system code 0.
    @discardableResult
    func finished(_ recorder: ClipboardRecorder, timeout: TimeInterval = 10, file: StaticString = #filePath, line: UInt = #line) -> ClipboardRecorder.Completion? {
        let deadline = Date(timeIntervalSinceNow: timeout)
        while recorder.releases.isEmpty, Date() < deadline {
            RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.002))
        }
        runMainQueue(file: file, line: line)
        XCTAssertEqual(recorder.calls, ["completion", "release"], file: file, line: line)
        XCTAssertEqual(recorder.releases, [true], file: file, line: line)
        guard let completion = recorder.completions.first else { return nil }
        XCTAssertTrue(completion.onMain, file: file, line: line)
        XCTAssertEqual(completion.systemCode, 0, file: file, line: line)
        return completion
    }

    /// The call, from this thread (the main one), and what it completed with.
    func completion(file: StaticString = #filePath, line: UInt = #line, of call: (ClipboardRecorder) -> Int32) -> ClipboardRecorder.Completion? {
        let recorder = ClipboardRecorder()
        XCTAssertEqual(call(recorder), ClipboardErrorValue.none, "rejected at the entry", file: file, line: line)
        recorder.markReturned()
        XCTAssertEqual(recorder.calls, [], "something ran inside the call", file: file, line: line)
        let result = finished(recorder, file: file, line: line)
        XCTAssertEqual(result?.afterReturn, true, file: file, line: line)
        return result
    }

    /// `ntk_clipboard_copy_async` on `scope`; the error of the completion.
    @discardableResult
    func copy(_ value: ntk_clipboard_write_content, options: ntk_clipboard_copy_options? = nil, to scope: ntk_clipboard_scope,
              file: StaticString = #filePath, line: UInt = #line) -> Int32? {
        completion(file: file, line: line) { recorder in
            var value = value
            var scope = scope
            if var options {
                return ntk_clipboard_copy_async(&value, &options, &scope, recordDone, recorder.userData, recordRelease)
            }
            return ntk_clipboard_copy_async(&value, nil, &scope, recordDone, recorder.userData, recordRelease)
        }?.error
    }

    /// Runs the main thread for a time, for what must not come, or until `until` is true.
    func spin(_ seconds: TimeInterval, until: () -> Bool = { false }) {
        let deadline = Date(timeIntervalSinceNow: seconds)
        while !until(), Date() < deadline {
            RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.002))
        }
    }

    func text(_ pointer: UnsafePointer<CChar>?) -> String? {
        pointer.map { String(cString: $0) }
    }

    func bytes(of handle: OpaquePointer?) -> [UInt8]? {
        guard let handle, let data = ntk_bytes_data(handle) else { return nil }
        return Array(UnsafeBufferPointer(start: data, count: ntk_bytes_size(handle)))
    }
}
