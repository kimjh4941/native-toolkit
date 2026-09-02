//
//  UnityMacClipboardJsonParser.swift
//  UnityMacPlugin
//

import Foundation
import MacLibrary

/// JSON shapes exchanged with Unity across the C bridge.
///
/// There are twenty concrete types: six input only, four shared between input and output,
/// eight output only, and two events. The split is exclusive, so a type never appears in two
/// groups and the count can be checked mechanically (BT-11 / BT-17).
///
/// Two rules keep Unity and Swift from breaking each other across versions: unknown fields are
/// ignored when decoding, and never emitted when encoding.
enum ClipboardJson {

    // MARK: - Input only (6)

    struct ContentJson: Codable {
        struct Item: Codable {
            /// Uniform type identifier to Base64 bytes.
            let representations: [String: String]
        }
        let items: [Item]
    }

    struct OptionsJson: Codable {
        let localOnly: Bool?
    }

    struct CreateRequestJson: Codable {
        /// `"named"` or `"unique"`.
        let kind: String
        let name: String?
    }

    /// `null` disables filtering; an empty array is rejected downstream with 1512.
    typealias MatchingTypesJson = [String]

    // MARK: - Shared input and output (4)

    struct ScopeJson: Codable {
        /// `"general"`, `"named"` or `"unique"`.
        let kind: String
        /// Required unless `kind` is `"general"`, where it is ignored.
        let name: String?
    }

    struct OwnershipJson: Codable {
        let scope: ScopeJson
        let changeCount: Int
    }

    struct HandleJson: Codable {
        let id: String
    }

    /// Same shape for the detection request and its result.
    typealias PatternsJson = [String]

    // MARK: - Output only (8)

    struct ReadResultJson: Codable {
        let changeCount: Int
        let items: [ContentJson.Item]
    }

    /// `data` is `null` when the pasteboard has no such type, which is not an error.
    ///
    /// The field is written explicitly as `null` rather than omitted. The synthesised encoding
    /// would drop it, and "absent" and "present but null" are different things to a C# reader.
    struct ReadDataJson: Codable {
        let data: String?

        enum CodingKeys: String, CodingKey { case data }

        func encode(to encoder: any Encoder) throws {
            var container = encoder.container(keyedBy: CodingKeys.self)
            try container.encode(data, forKey: .data)
        }
    }

    struct SnapshotJson: Codable {
        let changeCount: Int
        let itemTypes: [[String]]
        let matchingItemIndexes: [Int]
    }

    struct ChangeCountJson: Codable {
        let changeCount: Int
    }

    struct BoolJson: Codable {
        let value: Bool
    }

    struct DetectedValuesJson: Codable {
        struct Link: Codable { let matchedString: String; let url: String }
        struct PhoneNumber: Codable {
            let matchedString: String; let phoneNumber: String; let label: String?
            enum CodingKeys: String, CodingKey { case matchedString, phoneNumber, label }
            func encode(to encoder: any Encoder) throws {
                var c = encoder.container(keyedBy: CodingKeys.self)
                try c.encode(matchedString, forKey: .matchedString)
                try c.encode(phoneNumber, forKey: .phoneNumber)
                try c.encode(label, forKey: .label)
            }
        }
        struct EmailAddress: Codable {
            let matchedString: String; let emailAddress: String; let label: String?
            enum CodingKeys: String, CodingKey { case matchedString, emailAddress, label }
            func encode(to encoder: any Encoder) throws {
                var c = encoder.container(keyedBy: CodingKeys.self)
                try c.encode(matchedString, forKey: .matchedString)
                try c.encode(emailAddress, forKey: .emailAddress)
                try c.encode(label, forKey: .label)
            }
        }
        struct PostalAddress: Codable {
            let matchedString: String
            let street: String?; let city: String?; let state: String?
            let postalCode: String?; let country: String?
            enum CodingKeys: String, CodingKey {
                case matchedString, street, city, state, postalCode, country
            }
            func encode(to encoder: any Encoder) throws {
                var c = encoder.container(keyedBy: CodingKeys.self)
                try c.encode(matchedString, forKey: .matchedString)
                try c.encode(street, forKey: .street)
                try c.encode(city, forKey: .city)
                try c.encode(state, forKey: .state)
                try c.encode(postalCode, forKey: .postalCode)
                try c.encode(country, forKey: .country)
            }
        }
        struct CalendarEvent: Codable {
            let matchedString: String; let isAllDay: Bool
            let startDate: String?; let startTimeZoneIdentifier: String?
            let endDate: String?; let endTimeZoneIdentifier: String?
            enum CodingKeys: String, CodingKey {
                case matchedString, isAllDay, startDate, startTimeZoneIdentifier,
                     endDate, endTimeZoneIdentifier
            }
            func encode(to encoder: any Encoder) throws {
                var c = encoder.container(keyedBy: CodingKeys.self)
                try c.encode(matchedString, forKey: .matchedString)
                try c.encode(isAllDay, forKey: .isAllDay)
                try c.encode(startDate, forKey: .startDate)
                try c.encode(startTimeZoneIdentifier, forKey: .startTimeZoneIdentifier)
                try c.encode(endDate, forKey: .endDate)
                try c.encode(endTimeZoneIdentifier, forKey: .endTimeZoneIdentifier)
            }
        }
        struct ShipmentTracking: Codable {
            let matchedString: String; let carrier: String; let trackingNumber: String
        }
        struct FlightNumber: Codable {
            let matchedString: String; let airline: String; let flightNumber: String
        }
        struct MoneyAmount: Codable {
            let matchedString: String; let currencyCode: String; let amount: Double
        }

        let patterns: [String]
        let probableWebURL: String?
        let probableWebSearch: String?
        let number: Double?
        let links: [Link]
        let phoneNumbers: [PhoneNumber]
        let emailAddresses: [EmailAddress]
        let postalAddresses: [PostalAddress]
        let calendarEvents: [CalendarEvent]
        let shipmentTrackingNumbers: [ShipmentTracking]
        let flightNumbers: [FlightNumber]
        let moneyAmounts: [MoneyAmount]

        enum CodingKeys: String, CodingKey {
            case patterns, probableWebURL, probableWebSearch, number, links, phoneNumbers,
                 emailAddresses, postalAddresses, calendarEvents, shipmentTrackingNumbers,
                 flightNumbers, moneyAmounts
        }

        /// Optionals are written as explicit `null`. A pattern that did not match must be
        /// visibly absent-with-a-value rather than a missing key, so the C# side can tell
        /// "not requested" from "requested and not found".
        func encode(to encoder: any Encoder) throws {
            var c = encoder.container(keyedBy: CodingKeys.self)
            try c.encode(patterns, forKey: .patterns)
            try c.encode(probableWebURL, forKey: .probableWebURL)
            try c.encode(probableWebSearch, forKey: .probableWebSearch)
            try c.encode(number, forKey: .number)
            try c.encode(links, forKey: .links)
            try c.encode(phoneNumbers, forKey: .phoneNumbers)
            try c.encode(emailAddresses, forKey: .emailAddresses)
            try c.encode(postalAddresses, forKey: .postalAddresses)
            try c.encode(calendarEvents, forKey: .calendarEvents)
            try c.encode(shipmentTrackingNumbers, forKey: .shipmentTrackingNumbers)
            try c.encode(flightNumbers, forKey: .flightNumbers)
            try c.encode(moneyAmounts, forKey: .moneyAmounts)
        }
    }

    struct DetectedMetadataJson: Codable {
        let metadataTypes: [String]
        let contentTypeIdentifier: String?

        enum CodingKeys: String, CodingKey { case metadataTypes, contentTypeIdentifier }

        func encode(to encoder: any Encoder) throws {
            var c = encoder.container(keyedBy: CodingKeys.self)
            try c.encode(metadataTypes, forKey: .metadataTypes)
            try c.encode(contentTypeIdentifier, forKey: .contentTypeIdentifier)
        }
    }

    /// `"default"`, `"ask"`, `"alwaysAllow"`, `"alwaysDeny"` or `"unavailable"`.
    struct AccessBehaviorJson: Codable {
        let value: String
    }

    struct ScopeResultJson: Codable {
        let scope: ScopeJson
    }

    // MARK: - Events (2)

    struct ChangeEventJson: Codable {
        let scope: ScopeJson
        let changeCount: Int
    }

}

/// Converts between the JSON shapes and domain values.
///
/// Errors are reported as `nil` rather than thrown: the bridge answers a malformed request
/// through the operation callback with a `BridgeError` code, and a Swift error cannot cross
/// the C ABI anyway.
/// The façade is callable from any thread, so the parser holds no shared coder.
///
/// `JSONEncoder` and `JSONDecoder` are not documented as safe for concurrent use, and a single
/// instance shared by every bridge call would be used from several threads at once. Creating
/// them per call costs far less than the encoding itself. Dates use `Date.ISO8601FormatStyle`,
/// a `Sendable` value type, rather than a shared `ISO8601DateFormatter` — the same change the
/// iOS clipboard bridge already made (`MIGRATION.md` section 4.2).
struct UnityMacClipboardJsonParser: Sendable {

    private let TAG = "UnityMacClipboardJsonParser"

    /// ISO 8601 in UTC, locale independent, so Unity parses the same string everywhere.
    private static let dateStyle = Date.ISO8601FormatStyle(timeZone: TimeZone(identifier: "UTC")!)

    init() {}

    // MARK: - Decoding

    private func decode<T: Decodable>(_ type: T.Type, from json: String?) -> T? {
        guard let json, let data = json.data(using: .utf8) else { return nil }
        // Unknown keys are ignored by JSONDecoder, which is what keeps Unity and Swift able to
        // ship at different versions (R6-M8).
        return try? JSONDecoder().decode(type, from: data)
    }

    func parseScope(_ json: String?) -> PasteboardScope? {
        Log.d(TAG, "[parseScope] \(ClipboardLog.scopeJson(json))")
        guard let shape = decode(ClipboardJson.ScopeJson.self, from: json) else { return nil }
        switch shape.kind {
        case "general":
            // `name` is ignored here rather than rejected, so a caller can round trip a scope
            // it read back without stripping the field.
            return .general
        case "named":
            guard let name = shape.name, !name.isEmpty else { return nil }
            return .named(name)
        case "unique":
            guard let name = shape.name, !name.isEmpty else { return nil }
            return .unique(name)
        default:
            return nil
        }
    }

    func parseContent(_ json: String?) -> ClipboardContent? {
        Log.d(TAG, "[parseContent] length: \(json?.count ?? 0)")
        guard let shape = decode(ClipboardJson.ContentJson.self, from: json) else { return nil }
        var items: [ClipboardItemData] = []
        for item in shape.items {
            var representations: [String: Data] = [:]
            for (identifier, base64) in item.representations {
                // A representation that is not valid Base64 is a malformed request, not an
                // empty one; failing the whole parse keeps that distinction.
                guard let data = Data(base64Encoded: base64) else { return nil }
                representations[identifier] = data
            }
            items.append(ClipboardItemData(representations: representations))
        }
        return ClipboardContent(items: items)
    }

    /// - Returns: `nil` only when a non-empty string was supplied but could not be decoded,
    ///   which the caller reports as 1301. An absent payload yields the defaults.
    ///
    /// Absent options mean "use the defaults"; malformed options mean the caller has a bug.
    /// Treating the second as the first would silently turn a requested `localOnly: false`
    /// into `true`, which is the opposite of what was asked for.
    func parseOptions(_ json: String?) -> ClipboardCopyOptions? {
        Log.d(TAG, "[parseOptions] \(ClipboardLog.json(json))")
        // Absent means "use the defaults". Only a supplied-but-undecodable payload is nil.
        guard let json, !json.isEmpty else { return .default }
        guard let shape = decode(ClipboardJson.OptionsJson.self, from: json) else { return nil }
        return ClipboardCopyOptions(localOnly: shape.localOnly ?? true)
    }

    func parseOwnership(_ json: String?) -> PasteboardOwnership? {
        Log.d(TAG, "[parseOwnership] \(ClipboardLog.json(json))")
        guard let shape = decode(ClipboardJson.OwnershipJson.self, from: json),
              let scope = parseScope(encodeScopeShape(shape.scope)) else { return nil }
        return PasteboardOwnership(scope: scope, changeCount: shape.changeCount)
    }

    func parseCreateRequest(_ json: String?) -> PasteboardCreationRequest? {
        Log.d(TAG, "[parseCreateRequest] \(ClipboardLog.json(json))")
        guard let shape = decode(ClipboardJson.CreateRequestJson.self, from: json) else { return nil }
        switch shape.kind {
        case "named":
            guard let name = shape.name, !name.isEmpty else { return nil }
            return .named(name)
        case "unique":
            return .unique
        default:
            return nil
        }
    }

    /// `nil` json means "no filter", which is different from an empty array.
    func parseMatchingTypes(_ json: String?) -> [String]?? {
        Log.d(TAG, "[parseMatchingTypes] \(ClipboardLog.json(json))")
        guard let json, !json.isEmpty else { return .some(nil) }
        guard let types = decode(ClipboardJson.MatchingTypesJson.self, from: json) else { return nil }
        return .some(types)
    }

    func parsePatterns(_ json: String?) -> Set<ClipboardDetectionPattern>? {
        Log.d(TAG, "[parsePatterns] \(ClipboardLog.json(json))")
        guard let raw = decode(ClipboardJson.PatternsJson.self, from: json) else { return nil }
        var patterns: Set<ClipboardDetectionPattern> = []
        for value in raw {
            guard let pattern = ClipboardDetectionPattern(rawValue: value) else { return nil }
            patterns.insert(pattern)
        }
        return patterns
    }


    func parseHandleId(_ json: String?) -> UUID? {
        Log.d(TAG, "[parseHandleId] \(ClipboardLog.json(json))")
        guard let shape = decode(ClipboardJson.HandleJson.self, from: json) else { return nil }
        return UUID(uuidString: shape.id)
    }

    // MARK: - Encoding

    private func encode<T: Encodable>(_ value: T) -> String? {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        guard let data = try? encoder.encode(value) else { return nil }
        return String(data: data, encoding: .utf8)
    }

    private func scopeShape(_ scope: PasteboardScope) -> ClipboardJson.ScopeJson {
        switch scope {
        case .general: return ClipboardJson.ScopeJson(kind: "general", name: nil)
        case .named(let name): return ClipboardJson.ScopeJson(kind: "named", name: name)
        case .unique(let name): return ClipboardJson.ScopeJson(kind: "unique", name: name)
        @unknown default: return ClipboardJson.ScopeJson(kind: "general", name: nil)
        }
    }

    private func encodeScopeShape(_ shape: ClipboardJson.ScopeJson) -> String? {
        encode(shape)
    }

    func encodeScope(_ scope: PasteboardScope) -> String? {
        Log.d(TAG, "[encodeScope] scope: \(ClipboardLog.scope(scope))")
        return encode(ClipboardJson.ScopeResultJson(scope: scopeShape(scope)))
    }

    func encodeOwnership(_ ownership: PasteboardOwnership) -> String? {
        Log.d(TAG, "[encodeOwnership] changeCount: \(ownership.changeCount)")
        return encode(ClipboardJson.OwnershipJson(scope: scopeShape(ownership.scope),
                                                  changeCount: ownership.changeCount))
    }

    func encodeReadResult(_ result: ClipboardReadResult) -> String? {
        Log.d(TAG, "[encodeReadResult] items: \(result.items.count)")
        return encode(ClipboardJson.ReadResultJson(
            changeCount: result.changeCount,
            items: result.items.map { item in
                ClipboardJson.ContentJson.Item(
                    representations: item.representations.mapValues { $0.base64EncodedString() })
            }))
    }

    func encodeData(_ data: Data?) -> String? {
        Log.d(TAG, "[encodeData] \(ClipboardLog.data(data))")
        return encode(ClipboardJson.ReadDataJson(data: data?.base64EncodedString()))
    }

    func encodeSnapshot(_ snapshot: ClipboardSnapshot) -> String? {
        Log.d(TAG, "[encodeSnapshot] items: \(snapshot.itemTypes.count)")
        return encode(ClipboardJson.SnapshotJson(changeCount: snapshot.changeCount,
                                                 itemTypes: snapshot.itemTypes,
                                                 matchingItemIndexes: snapshot.matchingItemIndexes))
    }

    func encodeChangeCount(_ changeCount: Int) -> String? {
        Log.d(TAG, "[encodeChangeCount] changeCount: \(changeCount)")
        return encode(ClipboardJson.ChangeCountJson(changeCount: changeCount))
    }

    func encodeBool(_ value: Bool) -> String? {
        Log.d(TAG, "[encodeBool] value: \(value)")
        return encode(ClipboardJson.BoolJson(value: value))
    }

    func encodePatterns(_ patterns: Set<ClipboardDetectionPattern>) -> String? {
        Log.d(TAG, "[encodePatterns] count: \(patterns.count)")
        // Sorted so the same match always produces the same string.
        return encode(patterns.map(\.rawValue).sorted())
    }

    func encodeHandle(_ id: UUID) -> String? {
        Log.d(TAG, "[encodeHandle] id: \(id)")
        return encode(ClipboardJson.HandleJson(id: id.uuidString))
    }

    func encodeAccessBehavior(_ behavior: ClipboardAccessBehavior) -> String? {
        Log.d(TAG, "[encodeAccessBehavior] value: \(behavior.rawValue)")
        return encode(ClipboardJson.AccessBehaviorJson(value: behavior.rawValue))
    }

    func encodeDetectedValues(_ values: ClipboardDetectedValues) -> String? {
        Log.d(TAG, "[encodeDetectedValues] patterns: \(values.patterns.count)")
        return encode(ClipboardJson.DetectedValuesJson(
            patterns: values.patterns.map(\.rawValue).sorted(),
            probableWebURL: values.probableWebURL,
            probableWebSearch: values.probableWebSearch,
            number: values.number,
            links: values.links.map { .init(matchedString: $0.matchedString, url: $0.url) },
            phoneNumbers: values.phoneNumbers.map {
                .init(matchedString: $0.matchedString, phoneNumber: $0.phoneNumber, label: $0.label)
            },
            emailAddresses: values.emailAddresses.map {
                .init(matchedString: $0.matchedString, emailAddress: $0.emailAddress, label: $0.label)
            },
            postalAddresses: values.postalAddresses.map {
                .init(matchedString: $0.matchedString, street: $0.street, city: $0.city,
                      state: $0.state, postalCode: $0.postalCode, country: $0.country)
            },
            calendarEvents: values.calendarEvents.map {
                .init(matchedString: $0.matchedString, isAllDay: $0.isAllDay,
                      startDate: $0.startDate.map { $0.formatted(Self.dateStyle) },
                      startTimeZoneIdentifier: $0.startTimeZoneIdentifier,
                      endDate: $0.endDate.map { $0.formatted(Self.dateStyle) },
                      endTimeZoneIdentifier: $0.endTimeZoneIdentifier)
            },
            shipmentTrackingNumbers: values.shipmentTrackingNumbers.map {
                .init(matchedString: $0.matchedString, carrier: $0.carrier,
                      trackingNumber: $0.trackingNumber)
            },
            flightNumbers: values.flightNumbers.map {
                .init(matchedString: $0.matchedString, airline: $0.airline,
                      flightNumber: $0.flightNumber)
            },
            moneyAmounts: values.moneyAmounts.map {
                .init(matchedString: $0.matchedString, currencyCode: $0.currencyCode,
                      amount: $0.amount)
            }))
    }

    func encodeDetectedMetadata(_ metadata: ClipboardDetectedMetadata) -> String? {
        Log.d(TAG, "[encodeDetectedMetadata] types: \(metadata.metadataTypes.count)")
        return encode(ClipboardJson.DetectedMetadataJson(
            metadataTypes: metadata.metadataTypes.map(\.rawValue).sorted(),
            contentTypeIdentifier: metadata.contentTypeIdentifier))
    }

    func encodeChangeEvent(_ event: ClipboardChangeEvent) -> String? {
        Log.d(TAG, "[encodeChangeEvent] changeCount: \(event.changeCount)")
        return encode(ClipboardJson.ChangeEventJson(scope: scopeShape(event.scope),
                                                    changeCount: event.changeCount))
    }
}
