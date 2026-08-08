//
//  UnityIosClipboardJsonParser.swift
//  UnityIosPlugin
//

import Foundation
import IosLibrary

/// Parses/serializes JSON between Unity C# and Clipboard Domain types.
///
/// Unknown top-level keys are ignored (forward compatibility). Any structural problem (invalid
/// JSON, missing required field, unknown `kind`, invalid Base64) is reported by returning `nil`
/// from the relevant `parse*` method; call sites convert that into `ClipboardError.invalidRequest`.
final class UnityIosClipboardJsonParser {
    private let TAG = "UnityIosClipboardJsonParser"

    // MARK: - Request parsing

    func parseObject(from json: String?) -> [String: Any]? {
        Log.d(TAG, "[parseObject] json: \(ClipboardRedaction.json(json ?? ""))")
        guard let json, let data = json.data(using: .utf8) else { return nil }
        return try? JSONSerialization.jsonObject(with: data) as? [String: Any]
    }

    /// Parses a `scope` object.
    ///
    /// Only an **omitted** `scope` key resolves to `.general`. A present-but-malformed `scope`
    /// (null, a string, an array, …) is rejected, so a broken request intended for a named
    /// pasteboard can never silently act on the general pasteboard.
    func parseScope(_ dict: [String: Any]?) -> PasteboardScope? {
        Log.d(TAG, "[parseScope] hasScopeKey: \(dict?["scope"] != nil)")
        guard let dict else { return .general }
        guard let rawScope = dict["scope"] else { return .general }
        guard let scopeDict = rawScope as? [String: Any] else { return nil }
        guard let kind = scopeDict["kind"] as? String else { return nil }
        switch kind {
        case "general":
            return .general
        case "named":
            guard let name = scopeDict["name"] as? String, !name.isEmpty else { return nil }
            return .named(name)
        case "unique":
            guard let name = scopeDict["name"] as? String, !name.isEmpty else { return nil }
            return .unique(name)
        default:
            return nil
        }
    }

    func parseCreationRequest(_ dict: [String: Any]) -> PasteboardCreationRequest? {
        Log.d(TAG, "[parseCreationRequest] hasRequestKey: \(dict["request"] != nil)")
        guard let requestDict = dict["request"] as? [String: Any], let kind = requestDict["kind"] as? String else {
            return nil
        }
        switch kind {
        case "named":
            guard let name = requestDict["name"] as? String, !name.isEmpty else { return nil }
            return .named(name)
        case "unique":
            return .unique
        default:
            return nil
        }
    }

    func parseContent(_ dict: [String: Any]) -> ClipboardContent? {
        Log.d(TAG, "[parseContent] hasContentKey: \(dict["content"] != nil)")
        guard let contentDict = dict["content"] as? [String: Any], let kind = contentDict["kind"] as? String else {
            return nil
        }
        switch kind {
        case "plainText":
            guard let text = contentDict["text"] as? String else { return nil }
            return .plainText(text)

        case "htmlText":
            guard let plain = contentDict["plain"] as? String, let html = contentDict["html"] as? String else {
                return nil
            }
            return .htmlText(plain: plain, html: html)

        case "url":
            guard let urlString = contentDict["urlString"] as? String else { return nil }
            return .url(urlString)

        case "imageFile":
            guard let path = contentDict["path"] as? String else { return nil }
            return .imageFile(path: path)

        case "imageData":
            guard let base64 = contentDict["base64"] as? String, let utType = contentDict["utType"] as? String,
                  let data = Data(base64Encoded: base64) else {
                return nil
            }
            return .imageData(data, utType: utType)

        case "color":
            guard let red = contentDict["red"] as? Double, let green = contentDict["green"] as? Double,
                  let blue = contentDict["blue"] as? Double, let alpha = contentDict["alpha"] as? Double else {
                return nil
            }
            return .color(red: red, green: green, blue: blue, alpha: alpha)

        case "customData":
            guard let base64 = contentDict["base64"] as? String, let utType = contentDict["utType"] as? String,
                  let data = Data(base64Encoded: base64) else {
                return nil
            }
            return .customData(data, utType: utType)

        case "multipleText":
            guard let texts = contentDict["texts"] as? [String] else { return nil }
            return .multipleText(texts)

        case "multiRepresentation":
            guard let representations = contentDict["representations"] as? [String: String] else { return nil }
            var decoded: [String: Data] = [:]
            for (key, base64) in representations {
                guard let data = Data(base64Encoded: base64) else { return nil }
                decoded[key] = data
            }
            return .multiRepresentation(decoded)

        default:
            return nil
        }
    }

    /// Returns `nil` (a hard parse failure) if `options` is present but malformed — including a
    /// present-but-non-object value. Only an omitted `options` key yields the safe default.
    func parseOptions(_ dict: [String: Any]) -> ClipboardCopyOptions?? {
        Log.d(TAG, "[parseOptions] hasOptionsKey: \(dict["options"] != nil)")
        guard let rawOptions = dict["options"] else { return .some(nil) }
        guard let optionsDict = rawOptions as? [String: Any] else { return nil }
        // `localOnly` defaults to `true` (the privacy-preserving choice) when the key is omitted;
        // only a present-but-non-bool value is a hard parse failure.
        let localOnly: Bool
        if let rawLocalOnly = optionsDict["localOnly"] {
            guard let value = rawLocalOnly as? Bool else { return nil }
            localOnly = value
        } else {
            localOnly = true
        }
        var expirationDate: Date?
        if let raw = optionsDict["expirationDate"] {
            if raw is NSNull { expirationDate = nil }
            else if let dateString = raw as? String {
                guard let parsed = Self.parseISO8601(dateString) else { return nil }
                expirationDate = parsed
            } else {
                return nil
            }
        }
        return .some(ClipboardCopyOptions(localOnly: localOnly, expirationDate: expirationDate))
    }

    /// `true` if the request explicitly included an `options` key (used to reject
    /// `clipboardAppend` requests that attempt to pass options).
    func containsOptionsKey(_ dict: [String: Any]) -> Bool {
        Log.d(TAG, "[containsOptionsKey] hasOptionsKey: \(dict["options"] != nil)")
        return dict["options"] != nil
    }

    func parseMatchingTypes(_ dict: [String: Any]) -> [String]?? {
        Log.d(TAG, "[parseMatchingTypes] hasMatchingTypesKey: \(dict["matchingTypes"] != nil)")
        guard let raw = dict["matchingTypes"] else { return .some(nil) }
        if raw is NSNull { return .some(nil) }
        guard let types = raw as? [String] else { return nil }
        return .some(types)
    }

    func parseUTType(_ dict: [String: Any]) -> String? {
        Log.d(TAG, "[parseUTType] hasUTTypeKey: \(dict["utType"] != nil)")
        return dict["utType"] as? String
    }

    func parsePatterns(_ dict: [String: Any]) -> Set<ClipboardDetectionPattern>? {
        Log.d(TAG, "[parsePatterns] hasPatternsKey: \(dict["patterns"] != nil)")
        guard let raw = dict["patterns"] as? [String] else { return nil }
        var result: Set<ClipboardDetectionPattern> = []
        for value in raw {
            guard let pattern = ClipboardDetectionPattern(rawValue: value) else { return nil }
            result.insert(pattern)
        }
        return result
    }

    func parseLoadRequest(_ dict: [String: Any]) -> ClipboardLoadRequest? {
        Log.d(TAG, "[parseLoadRequest] hasRequestKey: \(dict["request"] != nil)")
        guard let requestDict = dict["request"] as? [String: Any], let kind = requestDict["kind"] as? String else {
            return nil
        }
        switch kind {
        case "text": return .text
        case "url": return .url
        case "image": return .image
        case "file":
            guard let utType = requestDict["utType"] as? String else { return nil }
            return .file(utType: utType)
        default:
            return nil
        }
    }

    // MARK: - Response serialization

    func serializeSuccess(_ data: Any?) -> String {
        Log.d(TAG, "[serializeSuccess] hasData: \(data != nil)")
        return serialize(["ok": true, "data": data ?? NSNull()])
    }

    func serializeError(code: String, message: String, detail: ClipboardFailureDetail? = nil) -> String {
        Log.d(TAG, "[serializeError] code: \(code), hasDetail: \(detail != nil)")
        var error: [String: Any] = ["code": code, "message": message]
        if let detail {
            error["details"] = ["domain": detail.domain, "code": detail.code]
        }
        return serialize(["ok": false, "error": error])
    }

    func serializeReadResult(_ result: ClipboardReadResult) -> Any {
        Log.d(TAG, "[serializeReadResult] numberOfItems: \(result.numberOfItems)")
        return [
            "numberOfItems": result.numberOfItems,
            "items": result.items.map { item in
                [
                    "typeIdentifiers": item.typeIdentifiers,
                    "text": item.text as Any? ?? NSNull(),
                    "urlString": item.urlString as Any? ?? NSNull(),
                    "imageDataUTType": item.imageDataUTType as Any? ?? NSNull()
                ] as [String: Any]
            }
        ]
    }

    func serializeReadData(utType: String, data: Data?) -> Any {
        Log.d(TAG, "[serializeReadData] utType: \(utType), byteCount: \(data?.count ?? 0)")
        guard let data else { return NSNull() }
        return ["utType": utType, "base64": data.base64EncodedString(), "byteCount": data.count]
    }

    func serializeSnapshot(_ snapshot: ClipboardSnapshot) -> Any {
        Log.d(TAG, "[serializeSnapshot] numberOfItems: \(snapshot.numberOfItems)")
        var dict: [String: Any] = [
            "hasStrings": snapshot.hasStrings,
            "hasURLs": snapshot.hasURLs,
            "hasImages": snapshot.hasImages,
            "hasColors": snapshot.hasColors,
            "numberOfItems": snapshot.numberOfItems,
            "typeIdentifiers": snapshot.typeIdentifiers,
            "allTypeIdentifiers": snapshot.allTypeIdentifiers
        ]
        dict["matchingItemIndexes"] = snapshot.matchingItemIndexes ?? NSNull()
        return dict
    }

    func serializeScope(_ scope: PasteboardScope) -> Any {
        Log.d(TAG, "[serializeScope]")
        switch scope {
        case .general:
            return ["kind": "general"]
        case .named(let name):
            return ["kind": "named", "name": name]
        case .unique(let name):
            return ["kind": "unique", "name": name]
        @unknown default:
            return ["kind": "general"]
        }
    }

    func serializePatterns(_ patterns: Set<ClipboardDetectionPattern>) -> Any {
        Log.d(TAG, "[serializePatterns] count: \(patterns.count)")
        return ["patterns": patterns.map(\.rawValue)]
    }

    func serializeDetectedValues(_ values: ClipboardDetectedValues) -> Any {
        Log.d(TAG, "[serializeDetectedValues] patternCount: \(values.detectedPatterns.count)")
        let postalAddresses: [[String: Any]] = values.postalAddresses.map { address in
            let entry: [String: Any] = [
                "street": address.street as Any? ?? NSNull(),
                "city": address.city as Any? ?? NSNull(),
                "state": address.state as Any? ?? NSNull(),
                "postalCode": address.postalCode as Any? ?? NSNull(),
                "country": address.country as Any? ?? NSNull()
            ]
            return entry
        }
        let calendarEvents: [[String: Any]] = values.calendarEvents.map { event in
            let startDate: Any = event.startDate.map { Self.iso8601Style.format($0) } ?? NSNull()
            let endDate: Any = event.endDate.map { Self.iso8601Style.format($0) } ?? NSNull()
            let entry: [String: Any] = [
                "startDate": startDate,
                "endDate": endDate,
                "startTimeZone": event.startTimeZoneIdentifier as Any? ?? NSNull(),
                "endTimeZone": event.endTimeZoneIdentifier as Any? ?? NSNull(),
                "isAllDay": event.isAllDay
            ]
            return entry
        }
        let flightNumbers: [[String: Any]] = values.flightNumbers.map { entry in
            ["airline": entry.airline, "flightNumber": entry.flightNumber]
        }
        let moneyAmounts: [[String: Any]] = values.moneyAmounts.map { entry in
            ["amount": entry.amount, "currency": entry.currency]
        }
        let shipmentTrackingNumbers: [[String: Any]] = values.shipmentTrackingNumbers.map { entry in
            ["carrier": entry.carrier, "trackingNumber": entry.trackingNumber]
        }
        let result: [String: Any] = [
            "detectedPatterns": values.detectedPatterns.map(\.rawValue),
            "probableWebURL": values.probableWebURL as Any? ?? NSNull(),
            "probableWebSearch": values.probableWebSearch as Any? ?? NSNull(),
            "number": values.number as Any? ?? NSNull(),
            "links": values.links,
            "emailAddresses": values.emailAddresses.map { serializeLabeledValue($0) },
            "phoneNumbers": values.phoneNumbers.map { serializeLabeledValue($0) },
            "postalAddresses": postalAddresses,
            "calendarEvents": calendarEvents,
            "flightNumbers": flightNumbers,
            "moneyAmounts": moneyAmounts,
            "shipmentTrackingNumbers": shipmentTrackingNumbers
        ]
        return result
    }

    func serializeLoadedItem(_ item: ClipboardLoadedItem) -> Any {
        Log.d(TAG, "[serializeLoadedItem]")
        switch item {
        case .text(let value):
            return ["kind": "text", "text": value]
        case .url(let value):
            return ["kind": "url", "urlString": value]
        case .imageData(let data, let utType):
            return ["kind": "imageData", "base64": data.base64EncodedString(), "utType": utType]
        case .file(let url):
            return ["kind": "file", "path": url.path]
        @unknown default:
            return ["kind": "unknown"]
        }
    }

    func serializeChangeEvent(_ event: ClipboardChangeEvent) -> String {
        Log.d(TAG, "[serializeChangeEvent]")
        var dict: [String: Any] = ["scope": serializeScope(event.scope)]
        switch event.kind {
        case .changed(let typesAdded, let typesRemoved):
            dict["kind"] = "changed"
            dict["typesAdded"] = typesAdded
            dict["typesRemoved"] = typesRemoved
        case .changedDetectedOnForeground:
            dict["kind"] = "changedDetectedOnForeground"
        case .removed:
            dict["kind"] = "removed"
        @unknown default:
            dict["kind"] = "unknown"
        }
        return serialize(dict)
    }

    // MARK: - Private

    private func serializeLabeledValue(_ value: ClipboardLabeledValue) -> [String: Any] {
        ["value": value.value, "label": value.label as Any? ?? NSNull()]
    }

    private func serialize(_ object: Any) -> String {
        guard let data = try? JSONSerialization.data(withJSONObject: object),
              let string = String(data: data, encoding: .utf8) else {
            return "{\"ok\":false,\"error\":{\"code\":\"CLIPBOARD_UNKNOWN\",\"message\":\"An unknown error occurred.\"}}"
        }
        return string
    }

    /// Used for **serialization**, so emitted timestamps always carry fractional seconds.
    ///
    /// `Date.ISO8601FormatStyle` is a `Sendable` value type. `ISO8601DateFormatter` is a reference
    /// type with mutable state, so sharing one from a `nonisolated` Manager that Unity may call on
    /// any thread is not concurrency-safe.
    private static let iso8601Style = Date.ISO8601FormatStyle(includingFractionalSeconds: true)

    private static let iso8601StyleWithoutFractionalSeconds = Date.ISO8601FormatStyle()

    /// Accepts an ISO 8601 internet date-time with or without fractional seconds. The schema only
    /// requires "ISO 8601", so `2026-08-08T00:00:00Z` must not be rejected as an invalid request
    /// just because it omits the fractional part.
    private static func parseISO8601(_ value: String) -> Date? {
        (try? iso8601Style.parse(value)) ?? (try? iso8601StyleWithoutFractionalSeconds.parse(value))
    }
}
