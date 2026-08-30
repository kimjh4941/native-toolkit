//
//  ClipboardDetectionMapper.swift
//  MacLibrary
//

import AppKit
import DataDetection
import Foundation

/// Converts between domain detection patterns and the AppKit detection API.
///
/// The Swift-refined API identifies a pattern by a key path into
/// `NSPasteboard.DetectedValues` rather than by an enum, so the mapping in both directions
/// lives here. `DDMatch` subclasses never leave this file: the domain keeps its own value
/// types so that no `DataDetection` type reaches the application layer (M-7).
@available(macOS 15.4, *)
enum ClipboardDetectionMapper {

    private static let TAG = "ClipboardDetectionMapper"

    /// Domain pattern to the key path the system uses for it.
    static func keyPath(for pattern: ClipboardDetectionPattern)
    -> PartialKeyPath<NSPasteboard.DetectedValues> {
        switch pattern {
        case .probableWebURL: return \NSPasteboard.DetectedValues.probableWebURL
        case .probableWebSearch: return \NSPasteboard.DetectedValues.probableWebSearch
        case .number: return \NSPasteboard.DetectedValues.number
        case .links: return \NSPasteboard.DetectedValues.links
        case .phoneNumbers: return \NSPasteboard.DetectedValues.phoneNumbers
        case .emailAddresses: return \NSPasteboard.DetectedValues.emailAddresses
        case .postalAddresses: return \NSPasteboard.DetectedValues.postalAddresses
        case .calendarEvents: return \NSPasteboard.DetectedValues.calendarEvents
        case .shipmentTrackingNumbers: return \NSPasteboard.DetectedValues.shipmentTrackingNumbers
        case .flightNumbers: return \NSPasteboard.DetectedValues.flightNumbers
        case .moneyAmounts: return \NSPasteboard.DetectedValues.moneyAmounts
        }
    }

    static func keyPaths(for patterns: Set<ClipboardDetectionPattern>)
    -> Set<PartialKeyPath<NSPasteboard.DetectedValues>> {
        Set(patterns.map(keyPath(for:)))
    }

    /// Key paths the system reported back, as domain patterns.
    ///
    /// A key path with no domain counterpart is dropped rather than failing the call: a later
    /// macOS can add patterns this version does not know about.
    static func patterns(from keyPaths: Set<PartialKeyPath<NSPasteboard.DetectedValues>>)
    -> Set<ClipboardDetectionPattern> {
        Log.d(TAG, "[patterns] keyPaths: \(keyPaths.count)")
        return Set(ClipboardDetectionPattern.allCases.filter { keyPaths.contains(keyPath(for: $0)) })
    }

    /// Detected values as domain types.
    ///
    /// Only the fields the system actually matched are read. `DetectedValues.patterns` is the
    /// authority for that: `probableWebURL` and `probableWebSearch` are non-optional strings
    /// and would otherwise read as empty matches.
    static func values(from detected: NSPasteboard.DetectedValues) -> ClipboardDetectedValues {
        Log.d(TAG, "[values] patterns: \(detected.patterns.count)")
        let matched = patterns(from: detected.patterns)
        return ClipboardDetectedValues(
            patterns: matched,
            probableWebURL: matched.contains(.probableWebURL) ? detected.probableWebURL : nil,
            probableWebSearch: matched.contains(.probableWebSearch) ? detected.probableWebSearch : nil,
            number: matched.contains(.number) ? detected.number : nil,
            links: detected.links.map {
                // NSURL is normalised to its absolute string; no locale dependent formatting.
                ClipboardDetectedLink(matchedString: $0.matchedString,
                                      url: $0.url.absoluteString)
            },
            phoneNumbers: detected.phoneNumbers.map {
                ClipboardDetectedPhoneNumber(matchedString: $0.matchedString,
                                             phoneNumber: $0.phoneNumber, label: $0.label)
            },
            emailAddresses: detected.emailAddresses.map {
                ClipboardDetectedEmailAddress(matchedString: $0.matchedString,
                                              emailAddress: $0.emailAddress, label: $0.label)
            },
            postalAddresses: detected.postalAddresses.map {
                ClipboardDetectedPostalAddress(matchedString: $0.matchedString,
                                               street: $0.street, city: $0.city, state: $0.state,
                                               postalCode: $0.postalCode, country: $0.country)
            },
            calendarEvents: detected.calendarEvents.map {
                // Dates stay as Date and time zones as identifiers. Formatting here would bake
                // in the current locale and lose information the caller may need.
                ClipboardDetectedCalendarEvent(matchedString: $0.matchedString,
                                               isAllDay: $0.isAllDay,
                                               startDate: $0.startDate,
                                               startTimeZoneIdentifier: $0.startTimeZone?.identifier,
                                               endDate: $0.endDate,
                                               endTimeZoneIdentifier: $0.endTimeZone?.identifier)
            },
            shipmentTrackingNumbers: detected.shipmentTrackingNumbers.map {
                ClipboardDetectedShipmentTracking(matchedString: $0.matchedString,
                                                  carrier: $0.carrier,
                                                  trackingNumber: $0.trackingNumber)
            },
            flightNumbers: detected.flightNumbers.map {
                ClipboardDetectedFlightNumber(matchedString: $0.matchedString,
                                              airline: $0.airline,
                                              flightNumber: $0.flightNumber)
            },
            moneyAmounts: detected.moneyAmounts.map {
                // The ISO code and the raw amount, never a formatted string.
                ClipboardDetectedMoneyAmount(matchedString: $0.matchedString,
                                             currencyCode: $0.currency, amount: $0.amount)
            })
    }

    /// Metadata as domain types.
    static func metadata(from detected: NSPasteboard.DetectedMetadata) -> ClipboardDetectedMetadata {
        Log.d(TAG, "[metadata] types: \(detected.metadataTypes.count)")
        var types: Set<ClipboardMetadataType> = []
        if detected.metadataTypes.contains(\NSPasteboard.DetectedMetadata.contentType) {
            types.insert(.contentType)
        }
        return ClipboardDetectedMetadata(metadataTypes: types,
                                         contentTypeIdentifier: detected.contentType?.identifier)
    }

    /// Key paths for the metadata types the caller asked for.
    static func metadataKeyPaths(for types: Set<ClipboardMetadataType>)
    -> Set<PartialKeyPath<NSPasteboard.DetectedMetadata>> {
        Set(types.map { type in
            switch type {
            case .contentType: return \NSPasteboard.DetectedMetadata.contentType
            }
        })
    }

    // MARK: - Transferring entry points

    // The detection methods are `nonisolated async`, so a main actor caller would have to move
    // the non-`Sendable` `NSPasteboard` and the non-`Sendable` key path sets across an
    // isolation boundary. These entry points avoid the crossing entirely: everything is
    // resolved and used inside one nonisolated domain, and only `PasteboardScope` (a domain
    // value type) comes in. Asserting the crossing is safe with an `@unchecked Sendable`
    // wrapper would hide a requirement rather than state it (MIGRATION.md section 6, why
    // plan C was preferred over plan B).

    /// Which of `patterns` the pasteboard matches.
    nonisolated static func detectPatterns(scope: PasteboardScope,
                                           patterns: Set<ClipboardDetectionPattern>) async throws
    -> Set<ClipboardDetectionPattern> {
        let pasteboard = try PasteboardResolver.resolve(scope)
        let detected = try await pasteboard.detectedPatterns(for: keyPaths(for: patterns))
        return self.patterns(from: detected)
    }

    /// The matched values themselves.
    nonisolated static func detectValues(scope: PasteboardScope,
                                         patterns: Set<ClipboardDetectionPattern>) async throws
    -> ClipboardDetectedValues {
        let pasteboard = try PasteboardResolver.resolve(scope)
        let detected = try await pasteboard.detectedValues(for: keyPaths(for: patterns))
        return values(from: detected)
    }

    /// Metadata for the first pasteboard item.
    nonisolated static func detectMetadata(scope: PasteboardScope,
                                           types: Set<ClipboardMetadataType>) async throws
    -> ClipboardDetectedMetadata {
        let pasteboard = try PasteboardResolver.resolve(scope)
        let detected = try await pasteboard.detectedMetadata(for: metadataKeyPaths(for: types))
        return metadata(from: detected)
    }
}
