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
        guard let json, let data = json.data(using: .utf8) else { return nil }
        return try? JSONSerialization.jsonObject(with: data) as? [String: Any]
    }

    /// Parses a `scope` object. Absent/omitted `scope` resolves to `.general`.
    func parseScope(_ dict: [String: Any]?) -> PasteboardScope? {
        guard let scopeDict = dict?["scope"] as? [String: Any] else { return .general }
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

    /// Returns `nil` (a hard parse failure) only if `options` is present but malformed;
    /// absent `options` yields the safe default.
    func parseOptions(_ dict: [String: Any]) -> ClipboardCopyOptions?? {
        guard let optionsDict = dict["options"] as? [String: Any] else { return .some(nil) }
        guard let localOnly = optionsDict["localOnly"] as? Bool else { return nil }
        var expirationDate: Date?
        if let raw = optionsDict["expirationDate"] {
            if raw is NSNull { expirationDate = nil }
            else if let dateString = raw as? String {
                guard let parsed = Self.iso8601Formatter.date(from: dateString) else { return nil }
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
        dict["options"] != nil
    }

    func parseMatchingTypes(_ dict: [String: Any]) -> [String]?? {
        guard let raw = dict["matchingTypes"] else { return .some(nil) }
        if raw is NSNull { return .some(nil) }
        guard let types = raw as? [String] else { return nil }
        return .some(types)
    }

    func parseUTType(_ dict: [String: Any]) -> String? {
        dict["utType"] as? String
    }

    func parsePatterns(_ dict: [String: Any]) -> Set<ClipboardDetectionPattern>? {
        guard let raw = dict["patterns"] as? [String] else { return nil }
        var result: Set<ClipboardDetectionPattern> = []
        for value in raw {
            guard let pattern = ClipboardDetectionPattern(rawValue: value) else { return nil }
            result.insert(pattern)
        }
        return result
    }

    func parseLoadRequest(_ dict: [String: Any]) -> ClipboardLoadRequest? {
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
        serialize(["ok": true, "data": data ?? NSNull()])
    }

    func serializeError(code: String, message: String, detail: ClipboardFailureDetail? = nil) -> String {
        var error: [String: Any] = ["code": code, "message": message]
        if let detail {
            error["details"] = ["domain": detail.domain, "code": detail.code]
        }
        return serialize(["ok": false, "error": error])
    }

    func serializeReadResult(_ result: ClipboardReadResult) -> Any {
        [
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
        guard let data else { return NSNull() }
        return ["utType": utType, "base64": data.base64EncodedString(), "byteCount": data.count]
    }

    func serializeSnapshot(_ snapshot: ClipboardSnapshot) -> Any {
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
        switch scope {
        case .general:
            return ["kind": "general"]
        case .named(let name):
            return ["kind": "named", "name": name]
        case .unique(let name):
            return ["kind": "unique", "name": name]
        }
    }

    func serializePatterns(_ patterns: Set<ClipboardDetectionPattern>) -> Any {
        ["patterns": patterns.map(\.rawValue)]
    }

    func serializeDetectedValues(_ values: ClipboardDetectedValues) -> Any {
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
            let startDate: Any = event.startDate.map(Self.iso8601Formatter.string(from:)) ?? NSNull()
            let endDate: Any = event.endDate.map(Self.iso8601Formatter.string(from:)) ?? NSNull()
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
        switch item {
        case .text(let value):
            return ["kind": "text", "text": value]
        case .url(let value):
            return ["kind": "url", "urlString": value]
        case .imageData(let data, let utType):
            return ["kind": "imageData", "base64": data.base64EncodedString(), "utType": utType]
        case .file(let url):
            return ["kind": "file", "path": url.path]
        }
    }

    func serializeChangeEvent(_ event: ClipboardChangeEvent) -> String {
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

    private static let iso8601Formatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()
}
