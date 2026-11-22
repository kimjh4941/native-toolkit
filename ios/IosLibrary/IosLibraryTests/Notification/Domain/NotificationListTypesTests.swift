//
//  NotificationListTypesTests.swift
//  IosLibraryTests
//
//  UT-18 (design 13.1, S-P25), the list part: `ScheduledNotification` and `ActiveNotification`
//  keep the userInfo as a value tree (`Sendable`), and `userInfo` rebuilds it with Foundation
//  types, so that it reads as before. `init` leaves out what is not a property-list value and
//  does not trap.
//

import Foundation
import Testing
@testable import IosLibrary

struct NotificationListTypesTests {

    private static let date = Date(timeIntervalSince1970: 1_700_000_000)

    /// A userInfo as the system hands it back (Foundation types).
    private static var systemUserInfo: [AnyHashable: Any] {
        [
            "int": NSNumber(value: 42),
            "negative": NSNumber(value: Int64.min),
            "big": NSNumber(value: UInt64.max),
            "double": NSNumber(value: 2.5),
            "true": kCFBooleanTrue as Any,
            "false": kCFBooleanFalse as Any,
            "string": "text" as NSString,
            "date": date as NSDate,
            "data": Data([0, 1, 2]) as NSData,
            "array": [NSNumber(value: 1), "two" as NSString] as NSArray,
            "dictionary": ["inner": NSNumber(value: true)] as NSDictionary,
        ]
    }

    /// Reads every kind with `as?`, as code written before 2.0.0 does.
    private func expectReadsAsBefore(_ userInfo: [AnyHashable: Any], sourceLocation: SourceLocation = #_sourceLocation) {
        #expect(userInfo["int"] as? Int == 42, sourceLocation: sourceLocation)
        #expect(userInfo["int"] as? Double == 42, sourceLocation: sourceLocation)
        #expect(userInfo["negative"] as? Int64 == Int64.min, sourceLocation: sourceLocation)
        #expect(userInfo["big"] as? UInt64 == UInt64.max, sourceLocation: sourceLocation)
        #expect(userInfo["double"] as? Double == 2.5, sourceLocation: sourceLocation)
        #expect(userInfo["true"] as? Bool == true, sourceLocation: sourceLocation)
        #expect(userInfo["false"] as? Bool == false, sourceLocation: sourceLocation)
        #expect(userInfo["string"] as? String == "text", sourceLocation: sourceLocation)
        #expect(userInfo["date"] as? Date == Self.date, sourceLocation: sourceLocation)
        #expect(userInfo["data"] as? Data == Data([0, 1, 2]), sourceLocation: sourceLocation)
        let array = userInfo["array"] as? [Any]
        #expect(array?.count == 2, sourceLocation: sourceLocation)
        #expect(array?.first as? Int == 1, sourceLocation: sourceLocation)
        #expect(array?.last as? String == "two", sourceLocation: sourceLocation)
        #expect((userInfo["dictionary"] as? [String: Any])?["inner"] as? Bool == true, sourceLocation: sourceLocation)
        // A Boolean stays a CFBoolean, as the system gives it.
        #expect(CFGetTypeID(userInfo["true"] as AnyObject) == CFBooleanGetTypeID(), sourceLocation: sourceLocation)
    }

    @Test func aScheduledNotificationReadsAsBefore() {
        let scheduled = ScheduledNotification(identifier: "s", title: "t", subtitle: nil, body: "b",
                                              categoryIdentifier: "c", userInfo: Self.systemUserInfo)
        expectReadsAsBefore(scheduled.userInfo)
        #expect(scheduled.userInfo.count == 11)
        #expect(scheduled.userInfoValues["int"] == .integer(42))
        #expect(scheduled.userInfoValues["true"] == .bool(true))
        #expect(scheduled.userInfoValues["big"] == .unsignedInteger(UInt64.max))
        #expect(scheduled.userInfoValues["dictionary"] == .dictionary(["inner": .bool(true)]))
    }

    @Test func anActiveNotificationReadsAsBefore() {
        let active = ActiveNotification(identifier: "a", title: "t", subtitle: "s", body: nil,
                                        categoryIdentifier: "c", date: Self.date, userInfo: Self.systemUserInfo)
        expectReadsAsBefore(active.userInfo)
        #expect(active.date == Self.date)
        #expect(active.userInfoValues["double"] == .double(2.5))
        #expect(active.userInfoValues["array"] == .array([.integer(1), .string("two")]))
    }

    /// Swift values passed to `init` read the same way (they are bridged first).
    @Test func swiftValuesPassedToInitReadAsBefore() {
        let scheduled = ScheduledNotification(identifier: "s", title: "t", subtitle: nil, body: nil, categoryIdentifier: "",
                                              userInfo: ["int": 7, "flag": true, "ratio": 0.25, "name": "n", "list": [1, 2]])
        #expect(scheduled.userInfo["int"] as? Int == 7)
        #expect(scheduled.userInfo["flag"] as? Bool == true)
        #expect(scheduled.userInfo["ratio"] as? Double == 0.25)
        #expect(scheduled.userInfo["name"] as? String == "n")
        #expect(scheduled.userInfo["list"] as? [Int] == [1, 2])
        #expect(scheduled.userInfoValues["flag"] == .bool(true))
    }

    /// What is not a property-list value, and a key that is not a string, is left out; nothing traps.
    @Test func initLeavesOutWhatIsNotAPropertyList() {
        let userInfo: [AnyHashable: Any] = [
            "kept": "yes",
            "object": NSObject(),
            "null": NSNull(),
            7: "integer key",
            "nested": ["kept": 1, "object": NSObject()] as [String: Any],
        ]
        let scheduled = ScheduledNotification(identifier: "s", title: "t", subtitle: nil, body: nil, categoryIdentifier: "", userInfo: userInfo)
        let active = ActiveNotification(identifier: "a", title: "t", subtitle: nil, body: nil, categoryIdentifier: "", date: Self.date, userInfo: userInfo)

        for values in [scheduled.userInfoValues, active.userInfoValues] {
            #expect(values == ["kept": .string("yes"), "nested": .dictionary(["kept": .integer(1)])])
        }
        #expect(scheduled.userInfo["object"] == nil)
        #expect(active.userInfo[AnyHashable(7)] == nil)
    }

    /// `Sendable` (S-P25, SR-2): the lists cross from a background task to the main actor.
    @MainActor
    @Test func theListsCrossToTheMainActor() async {
        let scheduled = await Task.detached {
            [ScheduledNotification(identifier: "s", title: "t", subtitle: nil, body: nil, categoryIdentifier: "", userInfo: ["k": 1])]
        }.value
        let active = await Task.detached {
            [ActiveNotification(identifier: "a", title: "t", subtitle: nil, body: nil, categoryIdentifier: "", date: Date(), userInfo: ["k": 2])]
        }.value
        #expect(scheduled.first?.userInfo["k"] as? Int == 1)
        #expect(active.first?.userInfo["k"] as? Int == 2)
    }
}
