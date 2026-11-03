//
//  CApiStringInputTests.swift
//  IosLibraryCApiTests
//

import XCTest
@testable import IosLibraryCApi

/// Reading the caller's strings (part 1, 5.9, chapter 6; E-15).
final class CApiStringInputTests: XCTestCase {

    private func withCString<Value>(_ bytes: [UInt8], _ body: (UnsafePointer<CChar>) throws -> Value) rethrows -> Value {
        try (bytes + [0]).withUnsafeBytes { try body($0.bindMemory(to: CChar.self).baseAddress!) }
    }

    private func required(_ bytes: [UInt8]) throws -> String {
        try withCString(bytes) { try CApiString.required($0) }
    }

    /// The five sequences of part 1's chapter 6, and the others that RFC 3629 excludes.
    private let invalid: [(String, [UInt8])] = [
        ("a lead byte without its continuation", [0xC3, 0x28]),
        ("a surrogate", [0xED, 0xA0, 0x80]),
        ("the overlong form of /", [0xC0, 0xAF]),
        ("a byte that never appears", [0xFF]),
        ("above U+10FFFF", [0xF4, 0x90, 0x80, 0x80]),
        ("the last surrogate", [0xED, 0xBF, 0xBF]),
        ("C1, which is always overlong", [0xC1, 0xBF]),
        ("an overlong 3-byte form", [0xE0, 0x80, 0x80]),
        ("an overlong 4-byte form", [0xF0, 0x80, 0x80, 0x80]),
        ("F5, which is always above U+10FFFF", [0xF5, 0x80, 0x80, 0x80]),
        ("a continuation byte first", [0x80]),
        ("a 2-byte form cut short", [0xC3]),
        ("a 3-byte form cut short", [0xE2, 0x82]),
        ("a 4-byte form cut short", [0xF0, 0x9F, 0x98]),
        ("after valid text", [0x61, 0xC3, 0xA9, 0xFF]),
    ]

    func testEveryRejectedSequenceFailsInEveryForm() throws {
        for (name, bytes) in invalid {
            try withCString(bytes) { pointer in
                XCTAssertThrowsError(try CApiString.required(pointer), name) { XCTAssertEqual($0 as? EntryError, .invalidParameter, name) }
                XCTAssertThrowsError(try CApiString.optional(pointer), name) { XCTAssertEqual($0 as? EntryError, .invalidParameter, name) }
                XCTAssertThrowsError(try CApiString.orEmpty(pointer), name) { XCTAssertEqual($0 as? EntryError, .invalidParameter, name) }
            }
        }
    }

    /// The limits of the valid ranges, right next to the rejected ones above.
    func testTheValuesNextToTheRejectedOnesAreKept() throws {
        let valid: [([UInt8], String)] = [
            ([], ""),
            ([0x61], "a"),
            ([0xC2, 0x80], "\u{80}"),
            ([0xC3, 0xA9], "\u{E9}"),
            ([0xE0, 0xA0, 0x80], "\u{800}"),
            ([0xED, 0x9F, 0xBF], "\u{D7FF}"),
            ([0xEE, 0x80, 0x80], "\u{E000}"),
            ([0xEF, 0xBF, 0xBD], "\u{FFFD}"),
            ([0xF0, 0x90, 0x80, 0x80], "\u{10000}"),
            ([0xF0, 0x9F, 0x98, 0x80], "\u{1F600}"),
            ([0xF4, 0x8F, 0xBF, 0xBF], "\u{10FFFF}"),
        ]
        for (bytes, expected) in valid {
            XCTAssertEqual(try required(bytes), expected)
            XCTAssertEqual(try required(bytes).utf8.count, bytes.count, "kept byte for byte")
        }
    }

    func testNull() throws {
        XCTAssertThrowsError(try CApiString.required(nil)) { XCTAssertEqual($0 as? EntryError, .invalidParameter) }
        XCTAssertNil(try CApiString.optional(nil))
        XCTAssertEqual(try CApiString.orEmpty(nil), "")
    }

    func testAnEmptyStringIsThereInEveryForm() throws {
        try withCString([]) { pointer in
            XCTAssertEqual(try CApiString.required(pointer), "")
            XCTAssertEqual(try CApiString.optional(pointer), "")
            XCTAssertEqual(try CApiString.orEmpty(pointer), "")
        }
    }

    func testTheTextIsACopy() throws {
        var bytes: [UInt8] = [0x61, 0x62, 0]
        let text = try bytes.withUnsafeBytes { try CApiString.required($0.baseAddress?.assumingMemoryBound(to: CChar.self)) }
        bytes[0] = 0x7A
        XCTAssertEqual(text, "ab")
    }

    /// It stops at the first NUL.
    func testNothingPastTheTerminatorIsRead() throws {
        XCTAssertEqual(try required([0x61, 0, 0xFF]), "a")
    }
}
