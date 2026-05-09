//
//  UnityMacNotificationJsonParser.swift
//  UnityMacPlugin
//
//  Created by Kim Jong Hyun on 2026/05/09.
//
import Foundation
import MacLibrary

/// Parses JSON strings from the C Bridge layer into MacLibrary domain types.
///
/// All methods return `Result` so callers can surface `BridgeError.parseFailed`
/// without throwing exceptions across the C boundary.
public final class UnityMacNotificationJsonParser {

    private let TAG = "UnityMacNotificationJsonParser"

    public init() {
        Log.d(TAG, "init")
    }

    // MARK: - NotificationContent

    /// Parses a `NotificationContent` from a JSON string.
    ///
    /// Expected JSON shape:
    /// ```json
    /// {
    ///   "id": "notif-001",
    ///   "title": "Hello",
    ///   "body": "World",
    ///   "subtitle": "Sub",
    ///   "badge": 1,
    ///   "userInfo": { "key": "value" }
    /// }
    /// ```
    public func parseContent(_ json: String) -> Result<NotificationContent, BridgeError> {
        Log.d(TAG, "parseContent called")
        guard let data = json.data(using: .utf8),
              let dict = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return .failure(.parseFailed(reason: "invalid JSON for NotificationContent"))
        }
        guard let id = dict["id"] as? String, !id.isEmpty else {
            return .failure(.parseFailed(reason: "missing or empty 'id' in NotificationContent"))
        }
        guard let title = dict["title"] as? String, !title.isEmpty else {
            return .failure(.parseFailed(reason: "missing or empty 'title' in NotificationContent"))
        }
        let body = dict["body"] as? String
        let subtitle = dict["subtitle"] as? String
        let badge = dict["badge"] as? Int
        let userInfo = dict["userInfo"] as? [String: String]
        return .success(NotificationContent(
            id: id,
            title: title,
            body: body,
            subtitle: subtitle,
            userInfo: userInfo,
            badge: badge
        ))
    }

    // MARK: - NotificationTrigger

    /// Parses a `NotificationTrigger` from a JSON string.
    ///
    /// Expected JSON shape (timeInterval):
    /// ```json
    /// { "type": "timeInterval", "seconds": 5.0, "repeats": false }
    /// ```
    /// Calendar:
    /// ```json
    /// { "type": "calendar", "hour": 9, "minute": 0, "repeats": true }
    /// ```
    /// Immediate:
    /// ```json
    /// { "type": "immediate" }
    /// ```
    public func parseTrigger(_ json: String) -> Result<NotificationTrigger, BridgeError> {
        Log.d(TAG, "parseTrigger called")
        guard let data = json.data(using: .utf8),
              let dict = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return .failure(.parseFailed(reason: "invalid JSON for NotificationTrigger"))
        }
        let type = dict["type"] as? String ?? "immediate"
        switch type {
        case "immediate":
            return .success(.immediate)
        case "timeInterval":
            guard let seconds = dict["seconds"] as? Double else {
                return .failure(.parseFailed(reason: "'seconds' required for timeInterval trigger"))
            }
            let repeats = dict["repeats"] as? Bool ?? false
            return .success(.timeInterval(seconds: seconds, repeats: repeats))
        case "calendar":
            var components = DateComponents()
            components.year   = dict["year"]   as? Int
            components.month  = dict["month"]  as? Int
            components.day    = dict["day"]    as? Int
            components.hour   = dict["hour"]   as? Int
            components.minute = dict["minute"] as? Int
            components.second = dict["second"] as? Int
            let repeats = dict["repeats"] as? Bool ?? false
            return .success(.calendar(dateComponents: components, repeats: repeats))
        default:
            return .failure(.parseFailed(reason: "unknown trigger type: \(type)"))
        }
    }

    // MARK: - NotificationCategory

    /// Parses a `NotificationCategory` from a JSON string.
    ///
    /// Expected JSON shape:
    /// ```json
    /// {
    ///   "id": "cat-001",
    ///   "actions": [
    ///     { "id": "act-ok", "title": "OK", "isForeground": false, "isTextInput": false }
    ///   ]
    /// }
    /// ```
    public func parseCategory(_ json: String) -> Result<NotificationCategory, BridgeError> {
        Log.d(TAG, "parseCategory called")
        guard let data = json.data(using: .utf8),
              let dict = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return .failure(.parseFailed(reason: "invalid JSON for NotificationCategory"))
        }
        guard let id = dict["id"] as? String, !id.isEmpty else {
            return .failure(.parseFailed(reason: "missing or empty 'id' in NotificationCategory"))
        }
        var actions: [NotificationAction] = []
        if let actionsArray = dict["actions"] as? [[String: Any]] {
            for actionDict in actionsArray {
                guard let actionId = actionDict["id"] as? String,
                      let actionTitle = actionDict["title"] as? String else { continue }
                let isForeground = actionDict["isForeground"] as? Bool ?? false
                let isTextInput = actionDict["isTextInput"] as? Bool ?? false
                let placeholder = actionDict["textInputPlaceholder"] as? String
                actions.append(NotificationAction(
                    id: actionId,
                    title: actionTitle,
                    isForeground: isForeground,
                    isTextInput: isTextInput,
                    textInputPlaceholder: placeholder
                ))
            }
        }
        return .success(NotificationCategory(id: id, actions: actions))
    }

    // MARK: - JSON Serialization Helpers

    /// Serializes an array of `ScheduledNotification` to a UTF-8 JSON string.
    public func toJson(scheduled notifications: [ScheduledNotification]) -> String {
        Log.d(TAG, "toJson(scheduled:) called with count: \(notifications.count)")
        let array = notifications.map { n -> [String: Any] in
            var dict: [String: Any] = [
                "identifier": n.identifier,
                "title": n.title
            ]
            if let body = n.body { dict["body"] = body }
            return dict
        }
        guard let data = try? JSONSerialization.data(withJSONObject: array),
              let json = String(data: data, encoding: .utf8) else {
            return "[]"
        }
        return json
    }

    /// Serializes an array of `ActiveNotification` to a UTF-8 JSON string.
    public func toJson(delivered notifications: [ActiveNotification]) -> String {
        Log.d(TAG, "toJson(delivered:) called with count: \(notifications.count)")
        let array = notifications.map { n -> [String: Any] in
            var dict: [String: Any] = [
                "identifier": n.identifier,
                "title": n.title,
                "date": ISO8601DateFormatter().string(from: n.date)
            ]
            if let body = n.body { dict["body"] = body }
            return dict
        }
        guard let data = try? JSONSerialization.data(withJSONObject: array),
              let json = String(data: data, encoding: .utf8) else {
            return "[]"
        }
        return json
    }

    /// Serializes a `NotificationAuthorizationStatus` to a JSON string.
    public func toJson(status: NotificationAuthorizationStatus) -> String {
        Log.d(TAG, "toJson(status:) called")
        let value: String
        switch status {
        case .notDetermined: value = "notDetermined"
        case .denied:        value = "denied"
        case .authorized:    value = "authorized"
        case .provisional:   value = "provisional"
        case .unsupported:   value = "unsupported"
        }
        guard let data = try? JSONSerialization.data(withJSONObject: ["status": value]),
              let json = String(data: data, encoding: .utf8) else {
            return "{\"status\":\"unsupported\"}"
        }
        return json
    }
}
