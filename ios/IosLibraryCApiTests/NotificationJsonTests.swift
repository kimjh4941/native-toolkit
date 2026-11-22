//
//  NotificationJsonTests.swift
//  IosLibraryCApiTests
//

import Foundation
import XCTest
@testable import IosLibrary
@testable import IosLibraryCApi

/// The userInfo JSON of part 2, 6.3 and P2-7: what the setter takes, and every row of what the output gives.
final class NotificationJsonTests: XCTestCase {
    private func parsed(_ text: String, file: StaticString = #filePath, line: UInt = #line) -> [String: NotificationUserInfoValue]? {
        do throws(EntryError) {
            return try NotificationJson.userInfo(text)
        } catch {
            return nil
        }
    }

    /// The copy of the key in the C ABI is the library's (12.1).
    func testTheReservedKeyIsTheLibrarys() {
        XCTAssertEqual(NotificationJson.reservedKey, NotificationMarker.key)
    }

    func testEachKindOfValueIn() {
        XCTAssertEqual(parsed(#"{"s":"t","i":-9223372036854775808,"m":9223372036854775807,"u":18446744073709551615,"d":1.5,"t":true,"f":false,"a":[1,"x"],"o":{"k":[]}}"#), [
            "s": .string("t"), "i": .integer(Int64.min), "m": .integer(Int64.max), "u": .unsignedInteger(UInt64.max), "d": .double(1.5),
            "t": .bool(true), "f": .bool(false), "a": .array([.integer(1), .string("x")]), "o": .dictionary(["k": .array([])]),
        ])
    }

    /// A Boolean stays one, and 1 stays a number.
    func testABooleanIsNotANumber() {
        XCTAssertEqual(parsed(#"{"a":1,"b":true,"c":0,"d":false}"#), ["a": .integer(1), "b": .bool(true), "c": .integer(0), "d": .bool(false)])
    }

    /// Part 2, 6.3: whether 1.0 becomes an integer is `JSONSerialization`'s. Here it stays a double.
    func testWhatJSONSerializationMakesOfOnePointZero() {
        XCTAssertEqual(parsed(#"{"a":1.0,"b":1e2}"#), ["a": .double(1.0), "b": .double(100)])
    }

    /// What fits neither `Int64` nor `UInt64` is a double, never an integer clamped to the edge.
    func testAnIntegerOutsideTheIntegerTypesIsADouble() {
        XCTAssertEqual(parsed(#"{"a":-9223372036854775809}"#), ["a": .double(-9223372036854775809.0)])
        XCTAssertEqual(parsed(#"{"a":18446744073709551616}"#), ["a": .double(18446744073709551616.0)])
        // Above Int64 but within UInt64: unsigned, as part 2, 6.3's table says.
        XCTAssertEqual(parsed(#"{"a":9223372036854775808}"#), ["a": .unsignedInteger(9223372036854775808)])
    }

    func testAnEmptyObjectIsFine() {
        XCTAssertEqual(parsed("{}"), [:])
    }

    func testTheReservedKeyOnlyAtTheTop() {
        XCTAssertNil(parsed(#"{"com.jonghyunkim.nativetoolkit":1}"#))
        XCTAssertEqual(parsed(#"{"x":{"com.jonghyunkim.nativetoolkit":1}}"#), ["x": .dictionary(["com.jonghyunkim.nativetoolkit": .integer(1)])])
    }

    func testWhatIsRejected() {
        for text in ["", "{", "[]", "[{}]", "1", "\"x\"", "null", #"{"a":null}"#, #"{"a":{"b":null}}"#, #"{"a":[null]}"#,
                     #"{"a":1e400}"#, #"{"a":-1e400}"#, #"{"a":NaN}"#] {
            XCTAssertNil(parsed(text), text)
        }
    }

    /// The input is what the OS's JSON parser takes (part 2, 6.3), and it takes a trailing comma. This test is here
    /// only to notice when Foundation changes that.
    func testATrailingCommaIsTakenAsJSONSerializationDoes() {
        XCTAssertEqual(parsed(#"{"a":1,}"#), ["a": .integer(1)])
    }

    /// Unicode in keys and values, and an escaped U+0000 inside a string (which C then never sees: the output
    /// replaces it).
    func testUnicode() {
        XCTAssertEqual(parsed(#"{"日":"😀","z":"a\u0000b"}"#), ["\u{65E5}": .string("\u{1F600}"), "z": .string("a\u{0}b")])
    }

    // MARK: - Out: every row of part 2, 6.3

    func testEveryKindOfValueOut() {
        let values: [String: NotificationUserInfoValue] = [
            "s": .string("t"), "i": .integer(-3), "u": .unsignedInteger(UInt64.max), "d": .double(2.5), "b": .bool(true),
            "date": .date(Date(timeIntervalSince1970: 1_000_000_000.25)), "data": .data(Data([0, 1, 2, 255])),
            "a": .array([.integer(1), .bool(false)]), "o": .dictionary(["k": .string("v")]),
        ]
        XCTAssertEqual(NotificationJson.text(of: values),
                       #"{"a":[1,false],"b":true,"d":2.5,"data":"AAEC/w==","date":"2001-09-09T01:46:40.250Z","i":-3,"o":{"k":"v"},"s":"t","u":18446744073709551615}"#)
    }

    /// The bridge's S-11 case: these must not stop the process.
    func testWhatIsNotFiniteIsNull() {
        for number in [Double.nan, .infinity, -.infinity] {
            XCTAssertEqual(NotificationJson.text(of: ["x": .double(number), "y": .array([.double(number)])]), #"{"x":null,"y":[null]}"#)
        }
    }

    func testAnEmptyUserInfoIsAnEmptyObject() {
        XCTAssertEqual(NotificationJson.text(of: [:]), "{}")
    }

    /// In and out are not symmetric (part 2, 6.3): a date goes out as a string and comes back as one.
    func testInAndOutAreNotSymmetric() throws {
        let out = try XCTUnwrap(NotificationJson.text(of: ["d": .date(Date(timeIntervalSince1970: 0))]))
        XCTAssertEqual(parsed(out), ["d": .string("1970-01-01T00:00:00.000Z")])
    }

    /// The values as the library takes them: a property list.
    func testThePropertyListIsWhatTheLibraryAccepts() throws {
        let values = try XCTUnwrap(parsed(#"{"a":[1,2.5,true,"s",{"b":18446744073709551615}]}"#))
        XCTAssertTrue(NotificationRepositoryImpl.isPropertyList(NotificationJson.propertyList(of: values)))
        XCTAssertTrue(NotificationRepositoryImpl.isPropertyList(NotificationJson.propertyList(of: ["d": .date(Date()), "x": .data(Data([1]))])))
    }
}
