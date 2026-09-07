//
//  ClipboardDetectedValues.swift
//  IosLibrary
//

import Foundation

/// The full set of values the data detection system can identify on the pasteboard.
///
/// `probableWebURL` / `probableWebSearch` are `nil` unless `detectedPatterns` contains the
/// corresponding pattern (the underlying system properties are non-optional and return an empty
/// string when nothing was detected; this type normalizes that to `nil`).
public struct ClipboardDetectedValues: Equatable, Sendable {
    public let detectedPatterns: Set<ClipboardDetectionPattern>
    public let probableWebURL: String?
    public let probableWebSearch: String?
    public let number: Double?
    public let links: [String]
    public let emailAddresses: [ClipboardLabeledValue]
    public let phoneNumbers: [ClipboardLabeledValue]
    public let postalAddresses: [ClipboardPostalAddress]
    public let calendarEvents: [ClipboardCalendarEvent]
    public let flightNumbers: [ClipboardFlightNumber]
    public let moneyAmounts: [ClipboardMoneyAmount]
    public let shipmentTrackingNumbers: [ClipboardShipmentTracking]

    public init(
        detectedPatterns: Set<ClipboardDetectionPattern>,
        probableWebURL: String?,
        probableWebSearch: String?,
        number: Double?,
        links: [String],
        emailAddresses: [ClipboardLabeledValue],
        phoneNumbers: [ClipboardLabeledValue],
        postalAddresses: [ClipboardPostalAddress],
        calendarEvents: [ClipboardCalendarEvent],
        flightNumbers: [ClipboardFlightNumber],
        moneyAmounts: [ClipboardMoneyAmount],
        shipmentTrackingNumbers: [ClipboardShipmentTracking]
    ) {
        self.detectedPatterns = detectedPatterns
        self.probableWebURL = probableWebURL
        self.probableWebSearch = probableWebSearch
        self.number = number
        self.links = links
        self.emailAddresses = emailAddresses
        self.phoneNumbers = phoneNumbers
        self.postalAddresses = postalAddresses
        self.calendarEvents = calendarEvents
        self.flightNumbers = flightNumbers
        self.moneyAmounts = moneyAmounts
        self.shipmentTrackingNumbers = shipmentTrackingNumbers
    }

    /// An empty result (no patterns detected).
    public static let empty = ClipboardDetectedValues(
        detectedPatterns: [],
        probableWebURL: nil,
        probableWebSearch: nil,
        number: nil,
        links: [],
        emailAddresses: [],
        phoneNumbers: [],
        postalAddresses: [],
        calendarEvents: [],
        flightNumbers: [],
        moneyAmounts: [],
        shipmentTrackingNumbers: []
    )
}
