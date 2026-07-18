//
//  UnityMacShareJsonParser.swift
//  UnityMacPlugin
//

import Foundation
import MacLibrary

/// Parses JSON strings from Unity C# into `ShareContent`.
final class UnityMacShareJsonParser {

    private let TAG = "UnityMacShareJsonParser"

    /// Parses a JSON string into `ShareContent`.
    ///
    /// Expected JSON keys:
    /// - `items` (Array, required): each entry has `type` (String: "text" | "url" | "image" | "file")
    ///   and `value` (String). Unknown `type` values and entries missing `value` are ignored
    ///   (this is not an error; only JSON syntax errors cause this method to return `nil`).
    /// - `recipients` (Array of String, optional)
    /// - `subject` (String, optional)
    /// - `excludedServiceTitles` (Array of String, optional): best-effort match against
    ///   `NSSharingService.title`.
    ///
    /// URL validity is not checked here; invalid URL strings are held as-is in `.url` and
    /// surfaced as `ShareError.invalidURL` by the Data layer.
    func parseContent(from json: String) -> ShareContent? {
        Log.d(TAG, "[parseContent] json: \(json)")
        guard let data = json.data(using: .utf8),
              let dict = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let rawItems = dict["items"] as? [[String: Any]]
        else {
            Log.e(TAG, "[parseContent] failed to parse JSON")
            return nil
        }

        let items: [ShareItem] = rawItems.compactMap { entry in
            guard let type = entry["type"] as? String, let value = entry["value"] as? String else {
                return nil
            }
            switch type {
            case "text": return .text(value)
            case "url": return .url(value)
            case "image": return .imageFile(path: value)
            case "file": return .file(path: value)
            default: return nil
            }
        }

        let recipients = dict["recipients"] as? [String] ?? []
        let subject = dict["subject"] as? String
        let excludedServiceTitles = dict["excludedServiceTitles"] as? [String] ?? []

        return ShareContent(items: items,
                            recipients: recipients,
                            subject: subject,
                            excludedServiceTitles: excludedServiceTitles)
    }
}
