//
//  NotificationMapping.swift
//  IosLibraryCApi
//

import Foundation
import IosLibrary

/// The pure conversions of the structs of Notification.h (part 2, 6.3): the trigger and the category, on the
/// calling thread and before anything is registered. The operations that take them come with TB-7. Every struct
/// is read with `reserved:` naming all its reserved fields but `reserved0`.
enum NotificationMapping {
    private static func rejected<Value>(_ reason: StaticString) throws(EntryError) -> Value {
        CApiLog.notification.error("[rejected] \(reason, privacy: .public)")
        throw .invalidParameter
    }

    // MARK: - Trigger

    /// NULL is nil: "now" for `show` and `update`, rejected by `schedule` (TB-7).
    static func trigger(_ pointer: UnsafePointer<ntk_notification_trigger>?) throws(EntryError) -> NotificationTrigger? {
        CApiLog.notification.debug("[trigger] pointer: \(pointer == nil ? "nil" : "provided", privacy: .public)")
        guard let raw = try StructReader.readIfPresent(pointer, reserved: [\.reserved1]) else { return nil }
        return try trigger(from: raw)
    }

    /// `kind` decides which fields are read; the others are not.
    static func trigger(from raw: ntk_notification_trigger) throws(EntryError) -> NotificationTrigger {
        CApiLog.notification.debug("[trigger] kind: \(raw.kind, privacy: .public)")
        switch Int(raw.kind) {
        case Int(NTK_NOTIFICATION_TRIGGER_TIME_INTERVAL):
            // Infinity would pass `isValid` and stay pending for ever: a rule of the C input (P2-26).
            guard raw.interval_seconds.isFinite else { return try rejected("the interval is not finite") }
            let trigger = NotificationTrigger.timeInterval(raw.interval_seconds, repeats: raw.repeats != 0)
            guard trigger.isValid else { return try rejected("the interval is not valid") }
            return trigger
        case Int(NTK_NOTIFICATION_TRIGGER_CALENDAR):
            return .calendar(try dateComponents(raw), repeats: raw.repeats != 0)
        case Int(NTK_NOTIFICATION_TRIGGER_LOCATION):
            let identifier = try CApiString.required(raw.location_identifier)
            guard !identifier.isEmpty else { return try rejected("the location identifier is empty") }
            guard raw.latitude.isFinite, raw.longitude.isFinite, raw.radius.isFinite else { return try rejected("a location value is not finite") }
            guard (-90.0...90.0).contains(raw.latitude) else { return try rejected("the latitude is out of range") }
            guard (-180.0...180.0).contains(raw.longitude) else { return try rejected("the longitude is out of range") }
            guard raw.radius > 0 else { return try rejected("the radius is not above 0") }
            let notifyOnEntry = raw.not_notify_on_entry == 0
            let notifyOnExit = raw.notify_on_exit != 0
            guard notifyOnEntry || notifyOnExit else { return try rejected("the location notifies neither way") }
            return .location(identifier: identifier, latitude: raw.latitude, longitude: raw.longitude, radius: raw.radius,
                             notifyOnEntry: notifyOnEntry, notifyOnExit: notifyOnExit)
        default:
            return try rejected("the trigger kind is out of range")
        }
    }

    /// The fields whose bit is set, and only those: 0 o'clock and "not set" differ.
    private static func dateComponents(_ raw: ntk_notification_trigger) throws(EntryError) -> DateComponents {
        CApiLog.notification.debug("[dateComponents] fields: \(raw.calendar_fields, privacy: .public)")
        let fields = raw.calendar_fields
        guard fields != 0 else { return try rejected("no calendar field") }
        let known = UInt32(NTK_NOTIFICATION_CALENDAR_YEAR) | UInt32(NTK_NOTIFICATION_CALENDAR_MONTH) | UInt32(NTK_NOTIFICATION_CALENDAR_DAY)
            | UInt32(NTK_NOTIFICATION_CALENDAR_HOUR) | UInt32(NTK_NOTIFICATION_CALENDAR_MINUTE) | UInt32(NTK_NOTIFICATION_CALENDAR_SECOND)
        guard fields & ~known == 0 else { return try rejected("an unknown calendar bit") }
        func value(_ bit: Int, _ field: Int32) -> Int? {
            fields & UInt32(bit) != 0 ? Int(field) : nil
        }
        return DateComponents(year: value(Int(NTK_NOTIFICATION_CALENDAR_YEAR), raw.year), month: value(Int(NTK_NOTIFICATION_CALENDAR_MONTH), raw.month),
                              day: value(Int(NTK_NOTIFICATION_CALENDAR_DAY), raw.day), hour: value(Int(NTK_NOTIFICATION_CALENDAR_HOUR), raw.hour),
                              minute: value(Int(NTK_NOTIFICATION_CALENDAR_MINUTE), raw.minute), second: value(Int(NTK_NOTIFICATION_CALENDAR_SECOND), raw.second))
    }

    // MARK: - Category

    private static let actionBits: UInt32 = UInt32(NTK_NOTIFICATION_ACTION_AUTHENTICATION_REQUIRED) | UInt32(NTK_NOTIFICATION_ACTION_DESTRUCTIVE)
        | UInt32(NTK_NOTIFICATION_ACTION_FOREGROUND)
    private static let categoryBits: UInt32 = UInt32(NTK_NOTIFICATION_CATEGORY_CUSTOM_DISMISS_ACTION) | UInt32(NTK_NOTIFICATION_CATEGORY_ALLOW_IN_CAR_PLAY)
        | UInt32(NTK_NOTIFICATION_CATEGORY_HIDDEN_PREVIEWS_SHOW_TITLE) | UInt32(NTK_NOTIFICATION_CATEGORY_ALLOW_ANNOUNCEMENT)

    /// The values of the bits are the `rawValue`s of the library's option sets (part 2, 6.3).
    static func category(_ pointer: UnsafePointer<ntk_notification_category>?) throws(EntryError) -> NotificationCategory {
        CApiLog.notification.debug("[category] pointer: \(pointer == nil ? "nil" : "provided", privacy: .public)")
        let raw = try StructReader.read(pointer, reserved: [\.reserved1])
        let identifier = try requiredIdentifier(raw.identifier)
        guard raw.options & ~categoryBits == 0 else { return try rejected("an unknown category bit") }
        var actions: [NotificationAction] = []
        for element in try StructReader.readArray(raw.actions, count: raw.action_count, reserved: [\.reserved1]) {
            guard element.options & ~actionBits == 0 else { return try rejected("an unknown action bit") }
            actions.append(NotificationAction(identifier: try requiredIdentifier(element.identifier), title: try CApiString.required(element.title),
                                              sfSymbolName: try CApiString.optional(element.sf_symbol_name),
                                              options: NotificationActionOptions(rawValue: UInt(element.options))))
        }
        var textInputActions: [TextInputNotificationAction] = []
        for element in try StructReader.readArray(raw.text_input_actions, count: raw.text_input_action_count, reserved: []) {
            textInputActions.append(TextInputNotificationAction(identifier: try requiredIdentifier(element.identifier),
                                                                title: try CApiString.required(element.title),
                                                                buttonTitle: try CApiString.required(element.button_title),
                                                                textInputPlaceholder: try CApiString.required(element.placeholder)))
        }
        return NotificationCategory(identifier: identifier, actions: actions, textInputActions: textInputActions,
                                    options: NotificationCategoryOptions(rawValue: UInt(raw.options)))
    }

    private static func requiredIdentifier(_ text: UnsafePointer<CChar>?) throws(EntryError) -> String {
        CApiLog.notification.debug("[requiredIdentifier] text: \(text == nil ? "nil" : "provided", privacy: .public)")
        let value = try CApiString.required(text)
        guard !value.isEmpty else { return try rejected("an identifier is empty") }
        return value
    }
}
