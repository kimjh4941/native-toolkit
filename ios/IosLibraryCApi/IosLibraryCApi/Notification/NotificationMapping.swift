//
//  NotificationMapping.swift
//  IosLibraryCApi
//

import Foundation
import IosLibrary
import UserNotifications

/// One notification of `get_scheduled_async` or `get_delivered_async`: no userInfo and no trigger (D-5).
struct NotificationListEntry: Sendable, Equatable {
    let identifier: String
    let title: String
    let subtitle: String?
    let body: String?
    let categoryIdentifier: String
    /// 0 for a scheduled notification.
    let dateMillis: Int64
}

/// What an interaction or a launch response becomes for C (part 2, 6.3, "イベントの値"). The userInfo is already
/// JSON: each registration gets a handle of its own, made from this.
struct NotificationInteractionValue: Sendable, Equatable {
    let kind: ntk_notification_event_kind
    let notificationIdentifier: String
    let actionIdentifier: String
    /// "" when the notification has no category.
    let categoryIdentifier: String
    /// Only for TEXT_INPUT.
    let userText: String?
    let userInfoJson: String
    let isLaunch: Bool
}

/// The pure conversions of Notification.h (part 2, 6.3, 11.2): the trigger and the category, on the calling
/// thread and before anything is registered; the options of a permission request; and the library's results
/// (the errors, the status, the pre-check of P2-10). Every struct is read with `reserved:` naming all its
/// reserved fields but `reserved0`.
enum NotificationMapping {
    private static func rejected<Value>(_ reason: StaticString) throws(EntryError) -> Value {
        CApiLog.notification.error("[rejected] \(reason, privacy: .public)")
        throw .invalidParameter
    }

    // MARK: - Trigger

    /// NULL is nil: "now" for `show` and `update`; `scheduledTrigger` rejects it.
    static func trigger(_ pointer: UnsafePointer<ntk_notification_trigger>?) throws(EntryError) -> NotificationTrigger? {
        CApiLog.notification.debug("[trigger] pointer: \(pointer == nil ? "nil" : "provided", privacy: .public)")
        guard let raw = try StructReader.readIfPresent(pointer, reserved: [\.reserved1]) else { return nil }
        return try trigger(from: raw)
    }

    /// The trigger of `schedule`, which must be there (part 2, 6.3).
    static func scheduledTrigger(_ pointer: UnsafePointer<ntk_notification_trigger>?) throws(EntryError) -> NotificationTrigger {
        CApiLog.notification.debug("[scheduledTrigger] pointer: \(pointer == nil ? "nil" : "provided", privacy: .public)")
        guard let trigger = try trigger(pointer) else { return try rejected("the trigger of schedule is NULL") }
        return trigger
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

    /// NULL and "" are rejected: an empty identifier leaves nothing (M5; the rules of the C input, part 2, chapter 6).
    static func requiredIdentifier(_ text: UnsafePointer<CChar>?) throws(EntryError) -> String {
        CApiLog.notification.debug("[requiredIdentifier] text: \(text == nil ? "nil" : "provided", privacy: .public)")
        let value = try CApiString.required(text)
        guard !value.isEmpty else { return try rejected("an identifier is empty") }
        return value
    }

    // MARK: - Permission

    /// The bits of `NTK_NOTIFICATION_AUTH_*`, which are the `rawValue`s of `UNAuthorizationOptions` (P2-27).
    static let permissionBits: UInt32 = UInt32(NTK_NOTIFICATION_AUTH_BADGE) | UInt32(NTK_NOTIFICATION_AUTH_SOUND)
        | UInt32(NTK_NOTIFICATION_AUTH_ALERT) | UInt32(NTK_NOTIFICATION_AUTH_CAR_PLAY) | UInt32(NTK_NOTIFICATION_AUTH_CRITICAL_ALERT)
        | UInt32(NTK_NOTIFICATION_AUTH_PROVIDES_APP_SETTINGS)

    /// 0 is the library's default, `[.alert, .sound, .badge]`; an unknown bit, `provisional` among them, is rejected (P2-27).
    static func permissionOptions(_ bits: UInt32) throws(EntryError) -> UNAuthorizationOptions {
        CApiLog.notification.debug("[permissionOptions] bits: \(bits, privacy: .public)")
        guard bits & ~permissionBits == 0 else { return try rejected("an unknown permission bit") }
        guard bits != 0 else { return [.alert, .sound, .badge] }
        return UNAuthorizationOptions(rawValue: UInt(bits))
    }

    /// The pre-check of `show`, `update` and `schedule` (P2-10): the statuses that `add` delivers for. `unknown`
    /// and a status this version does not know are not among them.
    static func allowsAdding(_ status: NotificationAuthorizationStatus) -> Bool {
        CApiLog.notification.debug("[allowsAdding] status: \(status.rawValue, privacy: .public)")
        switch status {
        case .authorized, .provisional, .ephemeral:
            return true
        case .notDetermined, .denied, .unknown:
            return false
        @unknown default:
            CApiLog.notification.error("[allowsAdding] a status this version does not know")
            return false
        }
    }

    /// A status this version does not know is `UNKNOWN`, which the header declares for what cannot be said.
    static func status(of status: NotificationAuthorizationStatus) -> ntk_notification_authorization_status {
        CApiLog.notification.debug("[status] status: \(status.rawValue, privacy: .public)")
        switch status {
        case .notDetermined: return ntk_notification_authorization_status(NTK_NOTIFICATION_STATUS_NOT_DETERMINED)
        case .denied: return ntk_notification_authorization_status(NTK_NOTIFICATION_STATUS_DENIED)
        case .authorized: return ntk_notification_authorization_status(NTK_NOTIFICATION_STATUS_AUTHORIZED)
        case .provisional: return ntk_notification_authorization_status(NTK_NOTIFICATION_STATUS_PROVISIONAL)
        case .ephemeral: return ntk_notification_authorization_status(NTK_NOTIFICATION_STATUS_EPHEMERAL)
        case .unknown: return ntk_notification_authorization_status(NTK_NOTIFICATION_STATUS_UNKNOWN)
        @unknown default:
            CApiLog.notification.error("[status] a status this version does not know")
            return ntk_notification_authorization_status(NTK_NOTIFICATION_STATUS_UNKNOWN)
        }
    }

    // MARK: - Errors

    /// 11.2. A failure that is not a `NotificationError` is `UNKNOWN` (P2-14). Only the value is logged: the
    /// payloads hold an attachment's identifier and the system's text.
    static func error(for failure: any Error) -> ntk_notification_error {
        guard let failure = failure as? NotificationError else {
            CApiLog.notification.error("[error] not a NotificationError: UNKNOWN")
            return ntk_notification_error(NTK_NOTIFICATION_ERROR_UNKNOWN)
        }
        let error = error(for: failure)
        CApiLog.notification.debug("[error] error: \(error, privacy: .public)")
        return error
    }

    static func error(for failure: NotificationError) -> ntk_notification_error {
        switch failure {
        case .reservedUserInfoKey, .invalidUserInfo, .invalidTrigger:
            // The entry checks all three: from a completion they are not expected.
            return ntk_notification_error(NTK_NOTIFICATION_ERROR_INVALID_PARAMETER)
        case .delegateNotInstalled:
            return ntk_notification_error(NTK_NOTIFICATION_ERROR_NOT_INITIALIZED)
        case .permissionDenied:
            // Only the deprecated helper throws it; the C ABI's own denial is the pre-check (P2-10).
            return ntk_notification_error(NTK_NOTIFICATION_ERROR_UNKNOWN)
        case .notForeground:
            return ntk_notification_error(NTK_NOTIFICATION_ERROR_NOT_FOREGROUND)
        case .openSettingsFailed:
            return ntk_notification_error(NTK_NOTIFICATION_ERROR_SETTINGS_NOT_OPENED)
        case .attachmentLoadFailed:
            return ntk_notification_error(NTK_NOTIFICATION_ERROR_ATTACHMENT_LOAD_FAILED)
        case .addRequestFailed:
            return ntk_notification_error(NTK_NOTIFICATION_ERROR_ADD_REQUEST_FAILED)
        case .setBadgeCountFailed:
            return ntk_notification_error(NTK_NOTIFICATION_ERROR_SET_BADGE_COUNT_FAILED)
        case .authorizationFailed:
            return ntk_notification_error(NTK_NOTIFICATION_ERROR_AUTHORIZATION_FAILED)
        @unknown default:
            CApiLog.notification.error("[error] a case this version does not know")
            return ntk_notification_error(NTK_NOTIFICATION_ERROR_UNKNOWN)
        }
    }

    // MARK: - Lists

    /// Unix milliseconds, rounded down; 0 for a date that `Int64` cannot hold.
    static func millis(of date: Date) -> Int64 {
        let value = (date.timeIntervalSince1970 * 1000).rounded(.down)
        return Int64(exactly: value) ?? 0
    }

    static func entries(of notifications: [ScheduledNotification]) -> [NotificationListEntry] {
        CApiLog.notification.debug("[entries] scheduled count: \(notifications.count, privacy: .public)")
        return notifications.map {
            NotificationListEntry(identifier: $0.identifier, title: $0.title, subtitle: $0.subtitle, body: $0.body,
                                  categoryIdentifier: $0.categoryIdentifier, dateMillis: 0)
        }
    }

    static func entries(of notifications: [ActiveNotification]) -> [NotificationListEntry] {
        CApiLog.notification.debug("[entries] delivered count: \(notifications.count, privacy: .public)")
        return notifications.map {
            NotificationListEntry(identifier: $0.identifier, title: $0.title, subtitle: $0.subtitle, body: $0.body,
                                  categoryIdentifier: $0.categoryIdentifier, dateMillis: millis(of: $0.date))
        }
    }

    // MARK: - Events

    /// `TEXT_INPUT` when there is a reply, `BODY_TAP` and `DISMISS` for the system's two identifiers, `ACTION`
    /// for any other (part 2, 6.3).
    static func kind(actionIdentifier: String, userText: String?) -> ntk_notification_event_kind {
        CApiLog.notification.debug("[kind] actionIdentifier length: \(actionIdentifier.utf8.count, privacy: .public), userText: \(userText == nil ? "nil" : "provided", privacy: .public)")
        if userText != nil {
            return ntk_notification_event_kind(NTK_NOTIFICATION_EVENT_KIND_TEXT_INPUT)
        }
        switch actionIdentifier {
        case UNNotificationDefaultActionIdentifier: return ntk_notification_event_kind(NTK_NOTIFICATION_EVENT_KIND_BODY_TAP)
        case UNNotificationDismissActionIdentifier: return ntk_notification_event_kind(NTK_NOTIFICATION_EVENT_KIND_DISMISS)
        default: return ntk_notification_event_kind(NTK_NOTIFICATION_EVENT_KIND_ACTION)
        }
    }

    /// The library has already taken out its marker (part 2, 6.3). A userInfo the JSON writer refused would be
    /// "{}"; the conversion makes every value writable, so that is not expected and is logged.
    static func interaction(of event: NotificationResponseEvent) -> NotificationInteractionValue {
        CApiLog.notification.debug("[interaction] userInfo keys: \(event.userInfo.count, privacy: .public), isLaunch: \(event.isLaunchResponse, privacy: .public)")
        let json: String
        if let text = NotificationJson.text(of: event.userInfo) {
            json = text
        } else {
            CApiLog.notification.error("[interaction] the userInfo could not be written as JSON: {}")
            json = "{}"
        }
        return NotificationInteractionValue(kind: kind(actionIdentifier: event.actionIdentifier, userText: event.userText),
                                            notificationIdentifier: event.notificationIdentifier,
                                            actionIdentifier: event.actionIdentifier, categoryIdentifier: event.categoryIdentifier,
                                            userText: event.userText, userInfoJson: json, isLaunch: event.isLaunchResponse)
    }
}
