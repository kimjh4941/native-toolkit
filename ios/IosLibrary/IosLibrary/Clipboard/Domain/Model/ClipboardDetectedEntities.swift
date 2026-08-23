//
//  ClipboardDetectedEntities.swift
//  IosLibrary
//

import Foundation

/// A detected value with an optional label (e.g. an email address or phone number).
public struct ClipboardLabeledValue: Equatable, Sendable {
    public let value: String
    public let label: String?

    public init(value: String, label: String?) {
        self.value = value
        self.label = label
    }
}

/// Mirrors `DDMatchPostalAddress`.
public struct ClipboardPostalAddress: Equatable, Sendable {
    public let street: String?
    public let city: String?
    public let state: String?
    public let postalCode: String?
    public let country: String?

    public init(street: String?, city: String?, state: String?, postalCode: String?, country: String?) {
        self.street = street
        self.city = city
        self.state = state
        self.postalCode = postalCode
        self.country = country
    }
}

/// Mirrors `DDMatchCalendarEvent`. Time zones are represented as identifier strings; `TimeZone`
/// itself is not brought into the Domain layer.
public struct ClipboardCalendarEvent: Equatable, Sendable {
    public let startDate: Date?
    public let endDate: Date?
    public let startTimeZoneIdentifier: String?
    public let endTimeZoneIdentifier: String?
    public let isAllDay: Bool

    public init(
        startDate: Date?,
        endDate: Date?,
        startTimeZoneIdentifier: String?,
        endTimeZoneIdentifier: String?,
        isAllDay: Bool
    ) {
        self.startDate = startDate
        self.endDate = endDate
        self.startTimeZoneIdentifier = startTimeZoneIdentifier
        self.endTimeZoneIdentifier = endTimeZoneIdentifier
        self.isAllDay = isAllDay
    }
}

/// Mirrors `DDMatchFlightNumber`.
public struct ClipboardFlightNumber: Equatable, Sendable {
    public let airline: String
    public let flightNumber: String

    public init(airline: String, flightNumber: String) {
        self.airline = airline
        self.flightNumber = flightNumber
    }
}

/// Mirrors `DDMatchMoneyAmount`.
public struct ClipboardMoneyAmount: Equatable, Sendable {
    public let amount: Double
    public let currency: String

    public init(amount: Double, currency: String) {
        self.amount = amount
        self.currency = currency
    }
}

/// Mirrors `DDMatchShipmentTrackingNumber`.
public struct ClipboardShipmentTracking: Equatable, Sendable {
    public let carrier: String
    public let trackingNumber: String

    public init(carrier: String, trackingNumber: String) {
        self.carrier = carrier
        self.trackingNumber = trackingNumber
    }
}
