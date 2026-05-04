//
//  UnityIosNotificationJsonParser.swift
//  UnityIosPlugin
//

import Foundation
import IosLibrary

/// Parses JSON strings from Unity C# into domain model objects.
final class UnityIosNotificationJsonParser {

    private let TAG = "UnityIosNotificationJsonParser"

    /// Parses a JSON string into `NotificationContent`.
    ///
    /// Expected JSON keys:
    /// - `id` (String, required)
    /// - `title` (String, required)
    /// - `subtitle` (String, optional)
    /// - `body` (String, optional)
    /// - `badge` (Int, optional)
    /// - `sound` (String: "default" | "defaultCritical" | custom name, optional)
    /// - `categoryIdentifier` (String, optional)
    /// - `interruptionLevel` (String: "passive" | "active" | "timeSensitive" | "critical", optional)
    /// - `threadIdentifier` (String, optional)
    /// - `targetContentIdentifier` (String, optional)
    /// - `relevanceScore` (Double 0.0-1.0, optional)
    /// - `filterCriteria` (String, optional)
    /// - `userInfo` (Object, optional)
    func parseContent(from json: String) -> NotificationContent? {
        Log.d(TAG, "[parseContent] json: \(json)")
        guard let data = json.data(using: .utf8),
              let dict = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let id = dict["id"] as? String,
              let title = dict["title"] as? String
        else {
            Log.e(TAG, "[parseContent] failed to parse required fields")
            return nil
        }
        let sound: NotificationSound?
        if let soundStr = dict["sound"] as? String {
            switch soundStr {
            case "default": sound = .default
            case "defaultCritical": sound = .defaultCritical
            default: sound = .named(soundStr)
            }
        } else {
            sound = .default
        }
        let interruptionLevel: NotificationInterruptionLevel?
        if let levelStr = dict["interruptionLevel"] as? String {
            switch levelStr {
            case "passive": interruptionLevel = .passive
            case "timeSensitive": interruptionLevel = .timeSensitive
            case "critical": interruptionLevel = .critical
            default: interruptionLevel = .active
            }
        } else {
            interruptionLevel = nil
        }
        let userInfo = dict["userInfo"] as? [String: Any] ?? [:]
        return NotificationContent(
            id: id,
            title: title,
            subtitle: dict["subtitle"] as? String,
            body: dict["body"] as? String,
            badge: dict["badge"] as? Int,
            sound: sound,
            categoryIdentifier: dict["categoryIdentifier"] as? String,
            interruptionLevel: interruptionLevel,
            threadIdentifier: dict["threadIdentifier"] as? String,
            targetContentIdentifier: dict["targetContentIdentifier"] as? String,
            relevanceScore: dict["relevanceScore"] as? Double,
            filterCriteria: dict["filterCriteria"] as? String,
            userInfo: userInfo
        )
    }

    /// Parses a JSON string into `NotificationTrigger`.
    ///
    /// Expected JSON keys:
    /// - `type` (String, required): "timeInterval" | "calendar" | "location"
    /// - For `timeInterval`: `interval` (Double), `repeats` (Bool)
    /// - For `calendar`: `year`, `month`, `day`, `hour`, `minute`, `second` (Int, optional), `repeats` (Bool)
    /// - For `location`: `identifier` (String), `latitude` (Double), `longitude` (Double), `radius` (Double),
    ///                    `notifyOnEntry` (Bool), `notifyOnExit` (Bool)
    func parseTrigger(from json: String?) -> NotificationTrigger? {
        Log.d(TAG, "[parseTrigger] json: \(json ?? "nil")")
        guard let json = json,
              let data = json.data(using: .utf8),
              let dict = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let type_ = dict["type"] as? String
        else { return nil }

        switch type_ {
        case "timeInterval":
            guard let interval = dict["interval"] as? Double else { return nil }
            let repeats = dict["repeats"] as? Bool ?? false
            return .timeInterval(interval, repeats: repeats)
        case "calendar":
            var components = DateComponents()
            components.year = dict["year"] as? Int
            components.month = dict["month"] as? Int
            components.day = dict["day"] as? Int
            components.hour = dict["hour"] as? Int
            components.minute = dict["minute"] as? Int
            components.second = dict["second"] as? Int
            let repeats = dict["repeats"] as? Bool ?? false
            return .calendar(components, repeats: repeats)
        case "location":
            guard let identifier = dict["identifier"] as? String,
                  let latitude = dict["latitude"] as? Double,
                  let longitude = dict["longitude"] as? Double,
                  let radius = dict["radius"] as? Double
            else { return nil }
            let notifyOnEntry = dict["notifyOnEntry"] as? Bool ?? true
            let notifyOnExit = dict["notifyOnExit"] as? Bool ?? false
            return .location(
                identifier: identifier,
                latitude: latitude,
                longitude: longitude,
                radius: radius,
                notifyOnEntry: notifyOnEntry,
                notifyOnExit: notifyOnExit
            )
        default:
            return nil
        }
    }

    /// Parses a JSON string into `NotificationCategory`.
    ///
    /// Expected JSON keys:
    /// - `identifier` (String, required)
    /// - `actions` (Array of action objects, optional)
    ///   - `identifier`, `title` (String, required), `sfSymbolName` (String, optional), `options` ([String], optional)
    /// - `textInputActions` (Array, optional)
    ///   - `identifier`, `title`, `buttonTitle`, `textInputPlaceholder` (String, required)
    /// - `options` ([String], optional): "customDismissAction" | "allowInCarPlay" | "hiddenPreviewsShowTitle" | "allowAnnouncement"
    func parseCategory(from json: String) -> NotificationCategory? {
        Log.d(TAG, "[parseCategory] json: \(json)")
        guard let data = json.data(using: .utf8),
              let dict = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let identifier = dict["identifier"] as? String
        else {
            Log.e(TAG, "[parseCategory] failed to parse identifier")
            return nil
        }
        let actionsRaw = dict["actions"] as? [[String: Any]] ?? []
        let actions: [NotificationAction] = actionsRaw.compactMap { raw in
            guard let id = raw["identifier"] as? String,
                  let title = raw["title"] as? String
            else { return nil }
            var opts: NotificationActionOptions = []
            if let optStrings = raw["options"] as? [String] {
                if optStrings.contains("authenticationRequired") { opts.insert(.authenticationRequired) }
                if optStrings.contains("destructive") { opts.insert(.destructive) }
                if optStrings.contains("foreground") { opts.insert(.foreground) }
            }
            return NotificationAction(identifier: id, title: title, sfSymbolName: raw["sfSymbolName"] as? String, options: opts)
        }
        let textInputRaw = dict["textInputActions"] as? [[String: Any]] ?? []
        let textInputActions: [TextInputNotificationAction] = textInputRaw.compactMap { raw in
            guard let id = raw["identifier"] as? String,
                  let title = raw["title"] as? String,
                  let buttonTitle = raw["buttonTitle"] as? String,
                  let placeholder = raw["textInputPlaceholder"] as? String
            else { return nil }
            return TextInputNotificationAction(
                identifier: id,
                title: title,
                buttonTitle: buttonTitle,
                textInputPlaceholder: placeholder
            )
        }
        var categoryOpts: NotificationCategoryOptions = []
        if let optStrings = dict["options"] as? [String] {
            if optStrings.contains("customDismissAction") { categoryOpts.insert(.customDismissAction) }
            if optStrings.contains("allowInCarPlay") { categoryOpts.insert(.allowInCarPlay) }
            if optStrings.contains("hiddenPreviewsShowTitle") { categoryOpts.insert(.hiddenPreviewsShowTitle) }
            if optStrings.contains("allowAnnouncement") { categoryOpts.insert(.allowAnnouncement) }
        }
        return NotificationCategory(
            identifier: identifier,
            actions: actions,
            textInputActions: textInputActions,
            options: categoryOpts
        )
    }
}
