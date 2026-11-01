//
//  NotificationUserInfoValueTests.swift
//  IosLibraryTests
//
//  UT-18 (design 13.1), the value tree part (S-P11, S-P25): a userInfo becomes the tree with the
//  numbers told apart in the designed order, the tree comes back with Foundation types so that
//  the existing readers (`as? Int`, `as? Bool`, ...) read the same values, and what is not a
//  property-list value is left out without a crash. The list types' part is C6 (T-17).
//

import Foundation
import Testing
@testable import IosLibrary

struct NotificationUserInfoValueTests {

    private static let date = Date(timeIntervalSince1970: 1_700_000_000.25)

    /// A userInfo with every kind of value, as an app passes it.
    private static var everyKind: [AnyHashable: Any] {
        [
            "string": "s",
            "int": 42,
            "negative": Int64.min,
            "int64Max": Int64.max,
            "aboveInt64": UInt64(Int64.max) + 1,
            "uint64Max": UInt64.max,
            "double": 1.5,
            "wholeDouble": 2.0,
            "true": true,
            "false": false,
            "date": date,
            "data": Data([1, 2, 3]),
            "array": [1, "two", [true]] as [Any],
            "dictionary": ["nested": ["deeper": 3.25]],
        ]
    }

    private static let everyKindTree: [String: NotificationUserInfoValue] = [
        "string": .string("s"),
        "int": .integer(42),
        "negative": .integer(.min),
        "int64Max": .integer(.max),
        "aboveInt64": .unsignedInteger(UInt64(Int64.max) + 1),
        "uint64Max": .unsignedInteger(.max),
        "double": .double(1.5),
        "wholeDouble": .double(2.0),
        "true": .bool(true),
        "false": .bool(false),
        "date": .date(date),
        "data": .data(Data([1, 2, 3])),
        "array": .array([.integer(1), .string("two"), .array([.bool(true)])]),
        "dictionary": .dictionary(["nested": .dictionary(["deeper": .double(3.25)])]),
    ]

    // MARK: To the tree

    @Test func everyKindBecomesItsCase() {
        let conversion = NotificationUserInfoValue.tree(of: Self.everyKind)
        #expect(conversion.values == Self.everyKindTree)
        #expect(conversion.droppedCount == 0)
    }

    /// The system stores a userInfo as a property list: what comes back from a binary property
    /// list gives the same tree (an XML property list keeps dates to the second only).
    @Test func aPropertyListRoundTripGivesTheSameTree() throws {
        let data = try PropertyListSerialization.data(fromPropertyList: Self.everyKind, format: .binary, options: 0)
        let stored = try #require(try PropertyListSerialization.propertyList(from: data, format: nil) as? [AnyHashable: Any])
        #expect(NotificationUserInfoValue.tree(of: stored).values == Self.everyKindTree)
    }

    /// The order of S-P11: a Boolean before a number, a floating-point number before an integer.
    @Test func numbersAreToldApartInTheDesignedOrder() {
        #expect(NotificationUserInfoValue.make(from: NSNumber(value: true)) == .bool(true))
        #expect(NotificationUserInfoValue.make(from: NSNumber(value: 1)) == .integer(1))
        #expect(NotificationUserInfoValue.make(from: NSNumber(value: 0)) == .integer(0))
        #expect(NotificationUserInfoValue.make(from: NSNumber(value: 1.0)) == .double(1.0))
        #expect(NotificationUserInfoValue.make(from: NSNumber(value: Float(0.5))) == .double(0.5))
        #expect(NotificationUserInfoValue.make(from: NSNumber(value: UInt64.max)) == .unsignedInteger(.max))
        #expect(NotificationUserInfoValue.make(from: NSNumber(value: UInt64(Int64.max))) == .integer(.max))
    }

    /// Keys that are not strings and values that are not property-list values are left out and
    /// counted; nothing crashes.
    @Test func whatIsNotAPropertyListIsLeftOutAndCounted() {
        let userInfo: [AnyHashable: Any] = [
            1: "number key",
            "object": NSObject(),
            "null": NSNull(),
            "url": URL(string: "https://example.com")!,
            "array": [1, NSObject()] as [Any],
            "dictionary": ["ok": 1, "bad": NSObject(), 2: "number key"] as [AnyHashable: Any],
            "kept": "v",
        ]
        let conversion = NotificationUserInfoValue.tree(of: userInfo)
        #expect(conversion.values == [
            "array": .array([.integer(1)]),
            "dictionary": .dictionary(["ok": .integer(1)]),
            "kept": .string("v"),
        ])
        #expect(conversion.droppedCount == 7)
    }

    // MARK: Back to Foundation

    /// The readers of the existing APIs read the same values as before (`as? Int` and so on).
    @Test func theFoundationFormReadsAsBefore() throws {
        let back = NotificationUserInfoValue.foundationDictionary(Self.everyKindTree)

        #expect(back["string"] as? String == "s")
        #expect(back["int"] as? Int == 42)
        #expect(back["negative"] as? Int64 == .min)
        #expect(back["int64Max"] as? Int == .max)
        #expect((back["aboveInt64"] as? NSNumber)?.uint64Value == UInt64(Int64.max) + 1)
        #expect((back["uint64Max"] as? NSNumber)?.uint64Value == .max)
        #expect(back["double"] as? Double == 1.5)
        #expect(back["wholeDouble"] as? Double == 2.0)
        #expect(back["true"] as? Bool == true)
        #expect(back["false"] as? Bool == false)
        #expect(back["date"] as? Date == Self.date)
        #expect(back["data"] as? Data == Data([1, 2, 3]))
        let array = try #require(back["array"] as? [Any])
        #expect(array.count == 3)
        #expect(array.first as? Int == 1)
        #expect(array[1] as? String == "two")
        #expect((array[2] as? [Any])?.first as? Bool == true)
        let dictionary = try #require(back["dictionary"] as? [String: Any])
        #expect((dictionary["nested"] as? [String: Any])?["deeper"] as? Double == 3.25)
        #expect(back.count == Self.everyKindTree.count)
    }

    /// Foundation types, not Swift ones: a Boolean is a `CFBoolean`, a number an `NSNumber`.
    /// Rebuilt with Swift's `Int64` or `Bool`, `as? Int` would read `nil` (design SR2-4).
    @Test func theFoundationFormUsesFoundationTypes() {
        let back = NotificationUserInfoValue.foundationDictionary(Self.everyKindTree)
        let boolean = back["true"] as AnyObject
        #expect(CFGetTypeID(boolean) == CFBooleanGetTypeID())
        #expect(back["int"] is NSNumber)
        #expect(back["string"] is NSString)
        #expect(back["array"] is NSArray)
        #expect(back["dictionary"] is NSDictionary)
    }

    /// Tree -> Foundation -> tree gives the same tree.
    @Test func theFoundationFormGivesTheSameTreeBack() {
        let back = NotificationUserInfoValue.foundationDictionary(Self.everyKindTree)
        #expect(NotificationUserInfoValue.tree(of: back).values == Self.everyKindTree)
    }

    /// The conversions are pure: userInfos converted on 8 threads at once (TSan run).
    @Test func conversionsOnManyThreadsAgree() async {
        let results = await withTaskGroup(of: Bool.self) { group in
            for _ in 0..<8 {
                group.addTask {
                    var same = true
                    for _ in 0..<25 {
                        let userInfo = NotificationUserInfoValue.foundationDictionary(Self.everyKindTree)
                        let tree = NotificationUserInfoValue.tree(of: userInfo).values
                        let again = NotificationUserInfoValue.tree(of: NotificationUserInfoValue.foundationDictionary(tree)).values
                        same = same && tree == Self.everyKindTree && again == tree
                    }
                    return same
                }
            }
            var all: [Bool] = []
            for await result in group { all.append(result) }
            return all
        }
        #expect(results == Array(repeating: true, count: 8))
    }
}

/// UT-17 (design 13.1), the marker's own part (8.3.3): the key is reserved, added to what the
/// library adds, and removed from what it hands back.
struct NotificationMarkerTests {

    @Test func theKeyIsReservedWhateverItsValue() {
        #expect(NotificationMarker.isReserved(in: [NotificationMarker.key: 1]))
        #expect(NotificationMarker.isReserved(in: [NotificationMarker.key: "x", "k": "v"]))
        #expect(!NotificationMarker.isReserved(in: ["k": "v"]))
        #expect(!NotificationMarker.isReserved(in: ["com.jonghyunkim.nativetoolkit.other": 1]))
        #expect(!NotificationMarker.isReserved(in: [:]))
    }

    @Test func attachingAddsTheMarkerAndKeepsTheRest() {
        let marked = NotificationMarker.attaching(to: ["k": "v", "n": 2])
        #expect(marked.count == 3)
        #expect(marked[NotificationMarker.key] as? Int == NotificationMarker.value)
        #expect(marked["k"] as? String == "v")
        #expect(marked["n"] as? Int == 2)
        #expect(NotificationMarker.isPresent(in: marked))
    }

    @Test func removingTakesOnlyTheMarkerOut() {
        let unmarked = NotificationMarker.removing(from: [NotificationMarker.key: 1, "k": "v"])
        #expect(unmarked.count == 1)
        #expect(unmarked["k"] as? String == "v")
        #expect(!NotificationMarker.isPresent(in: unmarked))
        #expect(NotificationMarker.removing(from: ["k": "v"]).count == 1)
    }

    /// The system hands the key back as an `NSString`; it is still found and removed.
    @Test func theKeyIsFoundAsAnNSString() {
        let userInfo: [AnyHashable: Any] = [NSString(string: NotificationMarker.key): 1]
        #expect(NotificationMarker.isPresent(in: userInfo))
        #expect(NotificationMarker.removing(from: userInfo).isEmpty)
    }
}
