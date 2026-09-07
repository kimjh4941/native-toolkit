//
//  ClipboardDetectionMapper.swift
//  IosLibrary
//

import Foundation
import UIKit
import DataDetection

/// Converts between `ClipboardDetectionPattern` and `PartialKeyPath<UIPasteboard.DetectedValues>`,
/// and between `DDMatch*` system types and Domain entity types.
///
/// Kept out of the Application layer entirely: `PartialKeyPath` and `DDMatch*` never appear
/// outside the Data layer.
struct ClipboardDetectionMapper: Sendable {
    func keyPaths(for patterns: Set<ClipboardDetectionPattern>) -> Set<PartialKeyPath<UIPasteboard.DetectedValues>> {
        Set(patterns.map(Self.keyPath(for:)))
    }

    func patterns(for keyPaths: Set<PartialKeyPath<UIPasteboard.DetectedValues>>) -> Set<ClipboardDetectionPattern> {
        Set(keyPaths.compactMap(Self.pattern(for:)))
    }

    /// Converts a system `DetectedValues` into the Domain representation.
    ///
    /// `probableWebURL` / `probableWebSearch` are non-optional on the system type and return an
    /// empty string when nothing was detected; this normalizes that to `nil` unless the
    /// corresponding pattern is present in `values.patterns`.
    func toDomain(_ values: UIPasteboard.DetectedValues) -> ClipboardDetectedValues {
        let detected = patterns(for: values.patterns)
        return ClipboardDetectedValues(
            detectedPatterns: detected,
            probableWebURL: detected.contains(.probableWebURL) ? values.probableWebURL : nil,
            probableWebSearch: detected.contains(.probableWebSearch) ? values.probableWebSearch : nil,
            number: values.number,
            links: values.links.map { $0.url.absoluteString },
            emailAddresses: values.emailAddresses.map {
                ClipboardLabeledValue(value: $0.emailAddress, label: $0.label)
            },
            phoneNumbers: values.phoneNumbers.map {
                ClipboardLabeledValue(value: $0.phoneNumber, label: $0.label)
            },
            postalAddresses: values.postalAddresses.map {
                ClipboardPostalAddress(
                    street: $0.street, city: $0.city, state: $0.state,
                    postalCode: $0.postalCode, country: $0.country
                )
            },
            calendarEvents: values.calendarEvents.map {
                ClipboardCalendarEvent(
                    startDate: $0.startDate,
                    endDate: $0.endDate,
                    startTimeZoneIdentifier: $0.startTimeZone?.identifier,
                    endTimeZoneIdentifier: $0.endTimeZone?.identifier,
                    isAllDay: $0.isAllDay
                )
            },
            flightNumbers: values.flightNumbers.map {
                ClipboardFlightNumber(airline: $0.airline, flightNumber: $0.flightNumber)
            },
            moneyAmounts: values.moneyAmounts.map {
                ClipboardMoneyAmount(amount: $0.amount, currency: $0.currency)
            },
            shipmentTrackingNumbers: values.shipmentTrackingNumbers.map {
                ClipboardShipmentTracking(carrier: $0.carrier, trackingNumber: $0.trackingNumber)
            }
        )
    }

    private static func keyPath(for pattern: ClipboardDetectionPattern) -> PartialKeyPath<UIPasteboard.DetectedValues> {
        switch pattern {
        case .probableWebURL: return \UIPasteboard.DetectedValues.probableWebURL
        case .probableWebSearch: return \UIPasteboard.DetectedValues.probableWebSearch
        case .number: return \UIPasteboard.DetectedValues.number
        case .link: return \UIPasteboard.DetectedValues.links
        case .emailAddress: return \UIPasteboard.DetectedValues.emailAddresses
        case .phoneNumber: return \UIPasteboard.DetectedValues.phoneNumbers
        case .postalAddress: return \UIPasteboard.DetectedValues.postalAddresses
        case .calendarEvent: return \UIPasteboard.DetectedValues.calendarEvents
        case .flightNumber: return \UIPasteboard.DetectedValues.flightNumbers
        case .moneyAmount: return \UIPasteboard.DetectedValues.moneyAmounts
        case .shipmentTrackingNumber: return \UIPasteboard.DetectedValues.shipmentTrackingNumbers
        }
    }

    private static func pattern(for keyPath: PartialKeyPath<UIPasteboard.DetectedValues>) -> ClipboardDetectionPattern? {
        switch keyPath {
        case \UIPasteboard.DetectedValues.probableWebURL: return .probableWebURL
        case \UIPasteboard.DetectedValues.probableWebSearch: return .probableWebSearch
        case \UIPasteboard.DetectedValues.number: return .number
        case \UIPasteboard.DetectedValues.links: return .link
        case \UIPasteboard.DetectedValues.emailAddresses: return .emailAddress
        case \UIPasteboard.DetectedValues.phoneNumbers: return .phoneNumber
        case \UIPasteboard.DetectedValues.postalAddresses: return .postalAddress
        case \UIPasteboard.DetectedValues.calendarEvents: return .calendarEvent
        case \UIPasteboard.DetectedValues.flightNumbers: return .flightNumber
        case \UIPasteboard.DetectedValues.moneyAmounts: return .moneyAmount
        case \UIPasteboard.DetectedValues.shipmentTrackingNumbers: return .shipmentTrackingNumber
        default: return nil
        }
    }
}
