//
//  CommonEntryTests.swift
//  IosLibraryCApiTests
//

import Foundation
import XCTest
@testable import IosLibraryCApi

/// Common.h through its C functions. No public function makes a handle yet, so the handles come from
/// `Handle.make*`, as the receivers will make them.
final class CommonEntryTests: XCTestCase {

    // MARK: - The version and the system code

    func testVersionIsTheOneOfTheHeader() {
        XCTAssertEqual(ntk_version(), 0x020000)
        XCTAssertEqual(ntk_version(), UInt32(NTK_VERSION_MAJOR << 16 | NTK_VERSION_MINOR << 8 | NTK_VERSION_PATCH))
        XCTAssertEqual(ntk_version(), UInt32(NTK_VERSION))
    }

    func testVersionIsTheOneOfTheFramework() throws {
        let bundle = try XCTUnwrap(Bundle(identifier: "com.jonghyunkim.nativetoolkit.IosLibraryCApi"))
        XCTAssertEqual(bundle.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String,
                       "\(NTK_VERSION_MAJOR).\(NTK_VERSION_MINOR).\(NTK_VERSION_PATCH)")
    }

    func testLastSystemCodeIsAlwaysZero() {
        XCTAssertEqual(ntk_last_system_code(), 0)
        XCTAssertEqual(onAnotherThread { ntk_last_system_code() }, 0)
        // After a call that failed, on the thread it failed on.
        XCTAssertEqual(onAnotherThread { () -> UInt32 in
            _ = ntk_notification_install()
            return ntk_last_system_code()
        }, 0)
    }

    // MARK: - ntk_string

    func testStringNull() {
        XCTAssertNil(ntk_string_data(nil))
        XCTAssertEqual(ntk_string_size(nil), 0)
        ntk_string_free(nil)
    }

    func testStringKeepsItsText() {
        assertString("", is: [])
        assertString("ascii", is: Array("ascii".utf8))
        assertString("a\u{E9}\u{65E5}\u{1F600}", is: [0x61, 0xC3, 0xA9, 0xE6, 0x97, 0xA5, 0xF0, 0x9F, 0x98, 0x80])
    }

    func testStringReplacesU0000WithFFFD() {
        assertString("\0", is: replacement)
        assertString("a\0b", is: [0x61] + replacement + [0x62])
        assertString("\0\0", is: replacement + replacement)
    }

    func testStringReplacesUnpairedSurrogatesWithFFFD() {
        let high: unichar = 0xD83D
        let low: unichar = 0xDE00
        assertString(bridged([high]), is: replacement)
        assertString(bridged([low]), is: replacement)
        assertString(bridged([0x61, high, 0x62]), is: [0x61] + replacement + [0x62])
        assertString(bridged([low, high]), is: replacement + replacement)
        // A pair in the right order is a character, not two replacements.
        assertString(bridged([high, low]), is: [0xF0, 0x9F, 0x98, 0x80])
    }

    // MARK: - ntk_bytes

    func testBytesNull() {
        XCTAssertNil(ntk_bytes_data(nil))
        XCTAssertEqual(ntk_bytes_size(nil), 0)
        ntk_bytes_free(nil)
    }

    func testBytesOfSizeZeroHaveAPointer() {
        let handle = Handle.makeBytes([UInt8]())
        defer { ntk_bytes_free(handle) }
        XCTAssertNotNil(ntk_bytes_data(handle))
        XCTAssertEqual(ntk_bytes_size(handle), 0)
    }

    func testBytesAreKeptAsTheyAre() throws {
        // A NUL and what is not UTF-8 go through; only text is replaced.
        let bytes: [UInt8] = [0x00, 0xFF, 0x00, 0xED, 0xA0, 0x80, 0x00]
        let handle = Handle.makeBytes(bytes)
        defer { ntk_bytes_free(handle) }
        XCTAssertEqual(ntk_bytes_size(handle), bytes.count)
        let data = try XCTUnwrap(ntk_bytes_data(handle))
        XCTAssertEqual(Array(UnsafeBufferPointer(start: data, count: bytes.count)), bytes)
    }

    // MARK: - ntk_string_list

    func testStringListNull() {
        var size = sentinelSize
        XCTAssertEqual(ntk_string_list_count(nil), 0)
        XCTAssertNil(ntk_string_list_at(nil, 0, &size))
        XCTAssertEqual(size, 0)
        ntk_string_list_free(nil)
    }

    func testStringListEmpty() {
        let list = Handle.makeStringList([])
        defer { ntk_string_list_free(list) }
        var size = sentinelSize
        XCTAssertEqual(ntk_string_list_count(list), 0)
        XCTAssertNil(ntk_string_list_at(list, 0, &size))
        XCTAssertEqual(size, 0)
    }

    func testStringListItems() throws {
        let list = Handle.makeStringList(["one", "", "a\0b", bridged([0xD83D])])
        defer { ntk_string_list_free(list) }
        XCTAssertEqual(ntk_string_list_count(list), 4)
        let expected: [[UInt8]] = [Array("one".utf8), [], [0x61] + replacement + [0x62], replacement]
        for (index, bytes) in expected.enumerated() {
            var size = sentinelSize
            let text = try XCTUnwrap(ntk_string_list_at(list, index, &size))
            XCTAssertEqual(size, bytes.count, "index \(index)")
            XCTAssertEqual(strlen(text), bytes.count, "index \(index)")
            XCTAssertEqual(contents(text, count: bytes.count), bytes, "index \(index)")
        }
    }

    func testStringListSizeOutputMayBeNull() throws {
        let list = Handle.makeStringList(["one"])
        defer { ntk_string_list_free(list) }
        let text = try XCTUnwrap(ntk_string_list_at(list, 0, nil))
        XCTAssertEqual(String(cString: text), "one")
    }

    func testStringListOutOfRange() {
        let list = Handle.makeStringList(["one", "two"])
        defer { ntk_string_list_free(list) }
        // SIZE_MAX arrives as -1.
        for index in [2, 3, Int.max, -1, Int.min] {
            var size = sentinelSize
            XCTAssertNil(ntk_string_list_at(list, index, &size), "index \(index)")
            XCTAssertEqual(size, 0, "index \(index): the size of no item, as on Windows and Android")
            XCTAssertNil(ntk_string_list_at(list, index, nil), "index \(index)")
        }
    }

    // MARK: - Handles

    /// Undefined by the contract, but the classes are separate so that it gives NULL or 0 (part 1, chapter 6).
    func testReadingAHandleAsAnotherTypeGivesNullOrZero() {
        let string = Handle.makeString("text")
        let bytes = Handle.makeBytes([UInt8(1)])
        let list = Handle.makeStringList(["item"])
        defer {
            ntk_string_free(string)
            ntk_bytes_free(bytes)
            ntk_string_list_free(list)
        }
        var size = sentinelSize
        for other in [bytes, list] {
            XCTAssertNil(ntk_string_data(other))
            XCTAssertEqual(ntk_string_size(other), 0)
        }
        for other in [string, list] {
            XCTAssertNil(ntk_bytes_data(other))
            XCTAssertEqual(ntk_bytes_size(other), 0)
        }
        for other in [string, bytes] {
            XCTAssertEqual(ntk_string_list_count(other), 0)
            XCTAssertNil(ntk_string_list_at(other, 0, &size))
            XCTAssertEqual(size, 0)
            size = sentinelSize
        }
    }

    func testAHandleHoldsItsObjectUntilItsFree() {
        let cases: [(OpaquePointer, (OpaquePointer) -> AnyObject?, (OpaquePointer?) -> Void)] = [
            (Handle.makeString("text"), { Handle.borrow($0, as: StringHandle.self) }, ntk_string_free),
            (Handle.makeBytes([UInt8(1)]), { Handle.borrow($0, as: BytesHandle.self) }, ntk_bytes_free),
            (Handle.makeStringList(["item"]), { Handle.borrow($0, as: StringListHandle.self) }, ntk_string_list_free),
        ]
        for (handle, borrow, free) in cases {
            weak let object = borrow(handle)
            XCTAssertNotNil(object, "alive until it is freed")
            free(handle)
            XCTAssertNil(object, "freed by its _free")
        }
    }

    /// Reads at the same time, and a free on another thread than the one that made the handle
    /// (part 1, 1.3.1). What it finds is for TSan.
    func testHandlesAreReadFromManyThreadsAndFreedOnAnother() throws {
        let string = UInt(bitPattern: Handle.makeString("text"))
        let list = UInt(bitPattern: Handle.makeStringList(["item"]))
        DispatchQueue.concurrentPerform(iterations: 200) { _ in
            let handle = OpaquePointer(bitPattern: string)
            let items = OpaquePointer(bitPattern: list)
            if ntk_string_size(handle) != 4 || ntk_string_data(handle) == nil
                || ntk_string_list_count(items) != 1 || ntk_string_list_at(items, 0, nil) == nil {
                XCTFail("a read gave something else")
            }
        }
        XCTAssertEqual(onAnotherThread { () -> Bool in
            ntk_string_free(OpaquePointer(bitPattern: string))
            ntk_string_list_free(OpaquePointer(bitPattern: list))
            return true
        }, true)
    }

    // MARK: - Helpers

    private let replacement: [UInt8] = [0xEF, 0xBF, 0xBD]
    private let sentinelSize = 12_345

    /// A String over an NSString, which may hold what a Swift String cannot (part 1, 5.9).
    private func bridged(_ units: [unichar]) -> String {
        NSString(characters: units, length: units.count) as String
    }

    private func contents(_ text: UnsafePointer<CChar>, count: Int) -> [UInt8] {
        Array(UnsafeRawBufferPointer(start: text, count: count))
    }

    private func assertString(_ value: String, is bytes: [UInt8], line: UInt = #line) {
        let handle = Handle.makeString(value)
        defer { ntk_string_free(handle) }
        XCTAssertEqual(ntk_string_size(handle), bytes.count, line: line)
        guard let text = ntk_string_data(handle) else {
            return XCTFail("NULL for a valid handle", line: line)
        }
        XCTAssertEqual(strlen(text), bytes.count, "a NUL inside, or none at the end", line: line)
        XCTAssertEqual(contents(text, count: bytes.count), bytes, line: line)
    }
}
