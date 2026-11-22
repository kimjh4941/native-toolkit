//
//  NotificationJson.swift
//  IosLibraryCApi
//

import Foundation
import IosLibrary

/// The userInfo of a notification as JSON (part 2, 6.3, P2-7). In: one JSON object, read once into
/// `NotificationUserInfoValue`. Out: the same values as one JSON object, which is not the input again:
/// a date is an ISO 8601 string, data is Base64, and a number that is not finite is `null`. The values may
/// be secrets, so only counts are logged.
enum NotificationJson {
    /// The top-level key the library keeps for itself (its `NotificationMarker.key`, which is internal there).
    static let reservedKey = "com.jonghyunkim.nativetoolkit"

    /// `NULL` is not here: the setter turns it into an empty userInfo before this.
    static func userInfo(_ text: String) throws(EntryError) -> [String: NotificationUserInfoValue] {
        CApiLog.notification.debug("[userInfo] length: \(text.utf8.count, privacy: .public)")
        guard let object = try? JSONSerialization.jsonObject(with: Data(text.utf8), options: []) else {
            CApiLog.notification.error("[userInfo] rejected: not JSON")
            throw .invalidParameter
        }
        guard let dictionary = object as? [String: Any] else {
            CApiLog.notification.error("[userInfo] rejected: not an object")
            throw .invalidParameter
        }
        // Only at the top, as in the library: the same key further in is the user's.
        guard dictionary[reservedKey] == nil else {
            CApiLog.notification.error("[userInfo] rejected: the reserved key")
            throw .invalidParameter
        }
        var values: [String: NotificationUserInfoValue] = [:]
        for (key, item) in dictionary {
            values[key] = try value(of: item)
        }
        CApiLog.notification.debug("[userInfo] keys: \(values.count, privacy: .public)")
        return values
    }

    private static func value(of item: Any) throws(EntryError) -> NotificationUserInfoValue {
        CApiLog.notification.debug("[value] item: \(String(describing: type(of: item)), privacy: .public)")
        switch item {
        case let text as String:
            return .string(text)
        case let number as NSNumber:
            return try value(of: number)
        case let array as [Any]:
            var values: [NotificationUserInfoValue] = []
            for element in array {
                values.append(try value(of: element))
            }
            return .array(values)
        case let dictionary as [String: Any]:
            var values: [String: NotificationUserInfoValue] = [:]
            for (key, element) in dictionary {
                values[key] = try value(of: element)
            }
            return .dictionary(values)
        default:
            // JSON's null, nested or not (P2-7).
            CApiLog.notification.error("[value] rejected: null")
            throw .invalidParameter
        }
    }

    /// A Boolean is its own type in JSON; an integer stays one when it fits `Int64`, or `UInt64` when it is positive
    /// and fits that. What fits neither comes from `JSONSerialization` as an `NSDecimalNumber`, and is a double:
    /// never an integer clamped to the edge. It must be finite (`1e400` is not a number here).
    private static func value(of number: NSNumber) throws(EntryError) -> NotificationUserInfoValue {
        CApiLog.notification.debug("[value] number type: \(String(cString: number.objCType), privacy: .public), decimal: \(number is NSDecimalNumber, privacy: .public)")
        if CFGetTypeID(number) == CFBooleanGetTypeID() {
            return .bool(number.boolValue)
        }
        if !(number is NSDecimalNumber) {
            switch String(cString: number.objCType) {
            case "c", "s", "i", "l", "q":
                return .integer(number.int64Value)
            case "C", "S", "I", "L", "Q":
                return .unsignedInteger(number.uint64Value)
            default:
                break
            }
        }
        let double = number.doubleValue
        guard double.isFinite else {
            CApiLog.notification.error("[value] rejected: a number that is not finite")
            throw .invalidParameter
        }
        return .double(double)
    }

    /// The values as the `[String: Any]` of `NotificationContent.userInfo`.
    static func propertyList(of values: [String: NotificationUserInfoValue]) -> [String: Any] {
        CApiLog.notification.debug("[propertyList] keys: \(values.count, privacy: .public)")
        return values.mapValues(anyValue)
    }

    private static func anyValue(_ value: NotificationUserInfoValue) -> Any {
        CApiLog.notification.debug("[anyValue] value: provided")
        switch value {
        case .string(let text): return text
        case .integer(let integer): return NSNumber(value: integer)
        case .unsignedInteger(let integer): return NSNumber(value: integer)
        case .double(let double): return NSNumber(value: double)
        case .bool(let flag): return NSNumber(value: flag)
        case .date(let date): return date
        case .data(let data): return data
        case .array(let values): return values.map(anyValue)
        case .dictionary(let values): return values.mapValues(anyValue)
        @unknown default:
            CApiLog.notification.error("[anyValue] a value this version does not know")
            return NSNull()
        }
    }

    /// The JSON object of the output (part 2, 6.3), with the keys sorted. Nil only if `JSONSerialization` refuses
    /// what is built here, which it does not.
    static func text(of values: [String: NotificationUserInfoValue]) -> String? {
        CApiLog.notification.debug("[text] keys: \(values.count, privacy: .public)")
        let object = values.mapValues(jsonValue)
        guard JSONSerialization.isValidJSONObject(object),
              let data = try? JSONSerialization.data(withJSONObject: object, options: [.sortedKeys, .withoutEscapingSlashes]) else {
            CApiLog.notification.error("[text] not a JSON object")
            return nil
        }
        return String(decoding: data, as: UTF8.self)
    }

    /// A value this version does not know has no JSON form either: `null`, as a number that is not finite.
    private static func jsonValue(_ value: NotificationUserInfoValue) -> Any {
        CApiLog.notification.debug("[jsonValue] value: provided")
        switch value {
        case .string(let text): return text
        case .integer(let integer): return NSNumber(value: integer)
        case .unsignedInteger(let integer): return NSNumber(value: integer)
        case .double(let double): return double.isFinite ? NSNumber(value: double) : NSNull()
        case .bool(let flag): return NSNumber(value: flag)
        case .date(let date):
            let formatter = ISO8601DateFormatter()
            formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            return formatter.string(from: date)
        case .data(let data): return data.base64EncodedString()
        case .array(let values): return values.map(jsonValue)
        case .dictionary(let values): return values.mapValues(jsonValue)
        @unknown default:
            CApiLog.notification.error("[jsonValue] a value this version does not know")
            return NSNull()
        }
    }
}
