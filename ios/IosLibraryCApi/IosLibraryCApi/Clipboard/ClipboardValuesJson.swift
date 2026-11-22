//
//  ClipboardValuesJson.swift
//  IosLibraryCApi
//

import Foundation
import IosLibrary

/// What `ntk_clipboard_detect_values_async` gives: a JSON object whose form is part of the ABI (part 2,
/// 6.1, P2-8). Every key is always there. Keys may be added, never changed. The values may be secrets, so
/// only their number is logged.
enum ClipboardValuesJson {
    /// Nil only if `JSONSerialization` refuses, which what is built here does not make it do.
    static func text(of values: ClipboardDetectedValues) -> String? {
        CApiLog.clipboard.debug("[text] detected patterns: \(values.detectedPatterns.count, privacy: .public)")
        let object = object(of: values)
        guard JSONSerialization.isValidJSONObject(object),
              let data = try? JSONSerialization.data(withJSONObject: object, options: [.sortedKeys, .withoutEscapingSlashes]) else {
            CApiLog.clipboard.error("[text] not a JSON object")
            return nil
        }
        return String(decoding: data, as: UTF8.self)
    }

    private static func object(of values: ClipboardDetectedValues) -> [String: Any] {
        [
            "detectedPatterns": values.detectedPatterns.map(\.rawValue).sorted().map(text),
            "probableWebURL": orNull(values.probableWebURL),
            "probableWebSearch": orNull(values.probableWebSearch),
            "number": number(values.number),
            "links": values.links.map(text),
            "emailAddresses": values.emailAddresses.map(labeled),
            "phoneNumbers": values.phoneNumbers.map(labeled),
            "postalAddresses": values.postalAddresses.map {
                ["street": orNull($0.street), "city": orNull($0.city), "state": orNull($0.state),
                 "postalCode": orNull($0.postalCode), "country": orNull($0.country)]
            },
            "calendarEvents": values.calendarEvents.map {
                ["startDate": date($0.startDate), "endDate": date($0.endDate),
                 "startTimeZone": orNull($0.startTimeZoneIdentifier), "endTimeZone": orNull($0.endTimeZoneIdentifier),
                 "isAllDay": $0.isAllDay]
            },
            "flightNumbers": values.flightNumbers.map { ["airline": text($0.airline), "flightNumber": text($0.flightNumber)] },
            "moneyAmounts": values.moneyAmounts.map { ["amount": number($0.amount), "currency": text($0.currency)] },
            "shipmentTrackingNumbers": values.shipmentTrackingNumbers.map {
                ["carrier": text($0.carrier), "trackingNumber": text($0.trackingNumber)]
            },
        ]
    }

    private static func labeled(_ value: ClipboardLabeledValue) -> [String: Any] {
        ["value": text(value.value), "label": orNull(value.label)]
    }

    /// As every text of the C ABI: U+0000 becomes U+FFFD (part 1, 5.9), here before JSON would escape it.
    private static func text(_ value: String) -> String {
        String(decoding: CApiString.outputUTF8(value), as: UTF8.self)
    }

    private static func orNull(_ value: String?) -> Any {
        value.map(text) ?? NSNull()
    }

    /// JSON has no value for what is not finite, and `JSONSerialization` refuses it.
    private static func number(_ value: Double?) -> Any {
        guard let value, value.isFinite else { return NSNull() }
        return value
    }

    /// ISO 8601 with fractional seconds, in UTC (P2-8).
    private static func date(_ value: Date?) -> Any {
        guard let value else { return NSNull() }
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.string(from: value)
    }
}
