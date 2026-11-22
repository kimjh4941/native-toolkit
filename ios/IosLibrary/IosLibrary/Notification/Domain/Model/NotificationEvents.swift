//
//  NotificationEvents.swift
//  IosLibrary
//

import Foundation
import os

private let logger = Logger(subsystem: "com.jonghyunkim.nativetoolkit.IosLibrary", category: "NotificationUserInfoValue")
private let responseEventLogger = Logger(subsystem: "com.jonghyunkim.nativetoolkit.IosLibrary", category: "NotificationResponseEvent")
private let settingsRequestLogger = Logger(subsystem: "com.jonghyunkim.nativetoolkit.IosLibrary", category: "NotificationSettingsRequest")

// MARK: - Value tree of a userInfo (design S-P11)

/// One value of a notification's `userInfo`, as a `Sendable` tree.
///
/// The system keeps only property-list values in a notification's `userInfo`, so every value
/// is one of these cases. A number is told apart in this order: a Boolean (`CFBoolean`) is
/// ``bool(_:)``, a floating-point number is ``double(_:)``, an integer that fits `Int64` is
/// ``integer(_:)``, and a larger positive integer is ``unsignedInteger(_:)``.
///
/// The values of a userInfo are the user's content: the library never logs them (only the
/// number of keys).
public indirect enum NotificationUserInfoValue: Sendable, Equatable {
    /// A string.
    case string(String)
    /// An integer that fits `Int64`.
    case integer(Int64)
    /// A positive integer larger than `Int64.max`.
    case unsignedInteger(UInt64)
    /// A floating-point number.
    case double(Double)
    /// A Boolean.
    case bool(Bool)
    /// A date.
    case date(Date)
    /// Bytes.
    case data(Data)
    /// An array of values.
    case array([NotificationUserInfoValue])
    /// A dictionary with string keys.
    case dictionary([String: NotificationUserInfoValue])
}

extension NotificationUserInfoValue {

    /// The value tree of a userInfo, and how many keys or values were left out.
    struct Conversion: Sendable, Equatable {
        /// The values with string keys.
        let values: [String: NotificationUserInfoValue]
        /// Keys that are not strings, and values (also inside arrays and dictionaries) that are
        /// not property-list values. The system never delivers them.
        let droppedCount: Int
    }

    /// Converts `userInfo` (a delivered notification's, or one a user passed) into the value tree.
    /// Never fails: what cannot be converted is left out and counted.
    static func tree(of userInfo: [AnyHashable: Any]) -> Conversion {
        logger.log(level: .libraryDebug, "[tree(of:)] keyCount: \(userInfo.count, privacy: .public)")
        var dropped = 0
        var values: [String: NotificationUserInfoValue] = [:]
        for (key, item) in userInfo {
            guard let name = key.base as? String else {
                dropped += 1
                continue
            }
            guard let value = make(from: item, dropped: &dropped) else {
                dropped += 1
                continue
            }
            values[name] = value
        }
        if dropped > 0 {
            logger.info("[tree(of:)] left out \(dropped, privacy: .public) keys or values that are not property-list values")
        }
        return Conversion(values: values, droppedCount: dropped)
    }

    /// The tree of one value, or `nil` when it is not a property-list value. Values left out
    /// inside an array or a dictionary are added to `dropped`.
    static func make(from item: Any, dropped: inout Int) -> NotificationUserInfoValue? {
        let droppedSoFar = dropped
        logger.log(level: .libraryDebug, "[make(from:dropped:)] item: \(String(describing: type(of: item)), privacy: .public), dropped: \(droppedSoFar, privacy: .public)")
        if let string = item as? String {
            return .string(string)
        }
        if let number = item as? NSNumber {
            return make(from: number)
        }
        if let date = item as? Date {
            return .date(date)
        }
        if let data = item as? Data {
            return .data(data)
        }
        if let array = item as? [Any] {
            var elements: [NotificationUserInfoValue] = []
            for element in array {
                if let value = make(from: element, dropped: &dropped) {
                    elements.append(value)
                } else {
                    dropped += 1
                }
            }
            return .array(elements)
        }
        if let dictionary = item as? [AnyHashable: Any] {
            var entries: [String: NotificationUserInfoValue] = [:]
            for (key, element) in dictionary {
                guard let name = key.base as? String, let value = make(from: element, dropped: &dropped) else {
                    dropped += 1
                    continue
                }
                entries[name] = value
            }
            return .dictionary(entries)
        }
        return nil
    }

    /// A number in the order of S-P11: Boolean, floating point, `Int64`, then `UInt64`.
    static func make(from number: NSNumber) -> NotificationUserInfoValue {
        logger.log(level: .libraryDebug, "[make(from: number)] number: \(String(describing: type(of: number)), privacy: .public)")
        if CFGetTypeID(number) == CFBooleanGetTypeID() {
            return .bool(number.boolValue)
        }
        if CFNumberIsFloatType(number) {
            return .double(number.doubleValue)
        }
        if number.compare(NSNumber(value: Int64.max)) == .orderedDescending {
            return .unsignedInteger(number.uint64Value)
        }
        return .integer(number.int64Value)
    }

    /// The value with Foundation types, as the existing APIs hand a userInfo: `NSString`,
    /// `NSNumber` (a Boolean is a `CFBoolean`), `NSDate`, `NSData`, `NSArray`, `NSDictionary`. So
    /// `as? Int`, `as? Double`, `as? Bool`, `as? String` and the others read it as before (design
    /// S-P25).
    var foundationValue: Any {
        logger.log(level: .libraryDebug, "[foundationValue] case: \(LogRedaction.caseName(self), privacy: .public)")
        switch self {
        case .string(let string): return string as NSString
        case .integer(let integer): return NSNumber(value: integer)
        case .unsignedInteger(let integer): return NSNumber(value: integer)
        case .double(let double): return NSNumber(value: double)
        case .bool(let bool): return NSNumber(value: bool)
        case .date(let date): return date as NSDate
        case .data(let data): return data as NSData
        case .array(let array): return array.map(\.foundationValue) as NSArray
        case .dictionary(let dictionary): return Self.foundationDictionary(dictionary) as NSDictionary
        }
    }

    /// A userInfo dictionary with Foundation types (see ``foundationValue``).
    static func foundationDictionary(_ values: [String: NotificationUserInfoValue]) -> [AnyHashable: Any] {
        logger.log(level: .libraryDebug, "[foundationDictionary] keyCount: \(values.count, privacy: .public)")
        var dictionary: [AnyHashable: Any] = [:]
        for (key, value) in values {
            dictionary[key] = value.foundationValue
        }
        return dictionary
    }
}

// MARK: - Events (design 8.4.1)

/// A response to a notification the library handles: a tap on the body, an action button, a text
/// input reply, or dismissing it with the custom dismiss action.
///
/// Delivered by ``IosNotificationManager/responses`` on the main actor, after the system's
/// `userNotificationCenter(_:didReceive:withCompletionHandler:)` call has returned and before
/// the library calls the system's completion handler.
///
/// The reply and the userInfo values are the user's content: ``description`` shows only the
/// length of the reply and the number of userInfo keys.
public struct NotificationResponseEvent: Sendable, Equatable, CustomStringConvertible {
    /// The identifier of the notification request.
    public let notificationIdentifier: String
    /// The identifier of the action: the category's action, or the system's
    /// `UNNotificationDefaultActionIdentifier` (a tap on the body) and
    /// `UNNotificationDismissActionIdentifier` (the custom dismiss action).
    public let actionIdentifier: String
    /// The category identifier of the notification (empty when it has none).
    public let categoryIdentifier: String
    /// The reply of a text input action; `nil` for any other response. An empty reply is `""`.
    public let userText: String?
    /// The notification's userInfo, without the library's own key.
    public let userInfo: [String: NotificationUserInfoValue]
    /// Whether this is the response that launched the app (see
    /// ``IosNotificationManager/launchResponse()``).
    public let isLaunchResponse: Bool

    init(
        notificationIdentifier: String,
        actionIdentifier: String,
        categoryIdentifier: String,
        userText: String?,
        userInfo: [String: NotificationUserInfoValue],
        isLaunchResponse: Bool
    ) {
        responseEventLogger.log(level: .libraryDebug, "[init] notificationIdentifier: \(notificationIdentifier, privacy: .public), actionIdentifier: \(actionIdentifier, privacy: .public), categoryIdentifier: \(categoryIdentifier, privacy: .public), userText: \(LogRedaction.length(userText), privacy: .public), userInfoKeys: \(userInfo.count, privacy: .public), isLaunchResponse: \(isLaunchResponse, privacy: .public)")
        self.notificationIdentifier = notificationIdentifier
        self.actionIdentifier = actionIdentifier
        self.categoryIdentifier = categoryIdentifier
        self.userText = userText
        self.userInfo = userInfo
        self.isLaunchResponse = isLaunchResponse
    }

    /// Identifiers, the length of the reply and the number of userInfo keys; never the reply or
    /// the userInfo values.
    public var description: String {
        let reply = userText.map { "length \($0.utf8.count)" } ?? "nil"
        return "NotificationResponseEvent(notificationIdentifier: \(notificationIdentifier), actionIdentifier: \(actionIdentifier), "
            + "categoryIdentifier: \(categoryIdentifier), userText: \(reply), userInfo: \(userInfo.count) keys, isLaunchResponse: \(isLaunchResponse))"
    }
}

/// A request from the system to show the app's own notification settings
/// (`userNotificationCenter(_:openSettingsFor:)`), delivered by
/// ``IosNotificationManager/settingsRequests`` on the main actor.
///
/// The system sends it when the user opens the app's notification settings from Settings or
/// from a notification, for an app that asked for `UNAuthorizationOptions.providesAppNotificationSettings`.
/// The library delivers a request for one of its own notifications always, and a request without
/// a notification (from Settings) or for another notification only when the delegate set before
/// ``IosNotificationManager/installDelegate()`` does not implement
/// `userNotificationCenter(_:openSettingsFor:)`; otherwise that delegate receives it instead.
/// The library does not open anything: show your settings screen.
public struct NotificationSettingsRequest: Sendable, Equatable {
    /// The identifier of the notification the request came from, or `nil` when it came from
    /// Settings.
    public let notificationIdentifier: String?

    init(notificationIdentifier: String?) {
        settingsRequestLogger.log(level: .libraryDebug, "[init] notificationIdentifier: \(notificationIdentifier ?? "nil", privacy: .public)")
        self.notificationIdentifier = notificationIdentifier
    }
}

// MARK: - Log forms

/// What the event hub logs of an event: identifiers, flags and counts only.
protocol NotificationEventLogSummary {
    var logSummary: String { get }
}

extension NotificationResponseEvent: NotificationEventLogSummary {
    var logSummary: String { description }
}

extension NotificationSettingsRequest: NotificationEventLogSummary {
    var logSummary: String { "NotificationSettingsRequest(notificationIdentifier: \(notificationIdentifier ?? "nil"))" }
}
