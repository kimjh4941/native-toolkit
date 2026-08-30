//
//  ClipboardDetection.swift
//  MacLibrary
//

import Foundation

/// A pattern the data detection system can look for on the pasteboard.
public enum ClipboardDetectionPattern: String, Sendable, CaseIterable, Equatable {
    case probableWebURL
    case probableWebSearch
    case number
    case links
    case phoneNumbers
    case emailAddresses
    case postalAddresses
    case calendarEvents
    case shipmentTrackingNumbers
    case flightNumbers
    case moneyAmounts
}

/// A metadata type the detection system can report without reading the contents.
public enum ClipboardMetadataType: String, Sendable, CaseIterable, Equatable {
    case contentType
}

/// Current pasteboard access behaviour for this app.
public enum ClipboardAccessBehavior: String, Sendable, Equatable {
    /// Never triggered an access alert; not listed in System Settings.
    case `default`
    /// The system asks before granting programmatic access.
    case ask
    /// All access is allowed without notifying.
    case alwaysAllow
    /// All access is denied without notifying.
    case alwaysDeny
    /// The reporting API is unavailable on this OS version.
    case unavailable
}

// MARK: - Detected entities
//
// Every `DDMatch` subclass inherits `matchedString`, so it is required on all of these.
// Values are normalised in a locale independent way: URLs become `absoluteString`, time
// zones become identifiers, and money keeps an ISO currency code plus a raw amount.

/// A web link found on the pasteboard.
public struct ClipboardDetectedLink: Sendable, Equatable {
    public let matchedString: String
    public let url: String
    public init(matchedString: String, url: String) {
        self.matchedString = matchedString
        self.url = url
    }
}

/// A phone number found on the pasteboard.
public struct ClipboardDetectedPhoneNumber: Sendable, Equatable {
    public let matchedString: String
    public let phoneNumber: String
    public let label: String?
    public init(matchedString: String, phoneNumber: String, label: String?) {
        self.matchedString = matchedString
        self.phoneNumber = phoneNumber
        self.label = label
    }
}

/// An email address found on the pasteboard.
public struct ClipboardDetectedEmailAddress: Sendable, Equatable {
    public let matchedString: String
    public let emailAddress: String
    public let label: String?
    public init(matchedString: String, emailAddress: String, label: String?) {
        self.matchedString = matchedString
        self.emailAddress = emailAddress
        self.label = label
    }
}

/// A postal address found on the pasteboard. Every component is optional.
public struct ClipboardDetectedPostalAddress: Sendable, Equatable {
    public let matchedString: String
    public let street: String?
    public let city: String?
    public let state: String?
    public let postalCode: String?
    public let country: String?
    public init(matchedString: String, street: String?, city: String?,
                state: String?, postalCode: String?, country: String?) {
        self.matchedString = matchedString
        self.street = street
        self.city = city
        self.state = state
        self.postalCode = postalCode
        self.country = country
    }
}

/// A calendar event found on the pasteboard.
public struct ClipboardDetectedCalendarEvent: Sendable, Equatable {
    public let matchedString: String
    public let isAllDay: Bool
    public let startDate: Date?
    /// Time zone identifier such as `Asia/Tokyo`, never a localized name.
    public let startTimeZoneIdentifier: String?
    public let endDate: Date?
    public let endTimeZoneIdentifier: String?
    public init(matchedString: String, isAllDay: Bool,
                startDate: Date?, startTimeZoneIdentifier: String?,
                endDate: Date?, endTimeZoneIdentifier: String?) {
        self.matchedString = matchedString
        self.isAllDay = isAllDay
        self.startDate = startDate
        self.startTimeZoneIdentifier = startTimeZoneIdentifier
        self.endDate = endDate
        self.endTimeZoneIdentifier = endTimeZoneIdentifier
    }
}

/// A parcel tracking number found on the pasteboard.
public struct ClipboardDetectedShipmentTracking: Sendable, Equatable {
    public let matchedString: String
    public let carrier: String
    public let trackingNumber: String
    public init(matchedString: String, carrier: String, trackingNumber: String) {
        self.matchedString = matchedString
        self.carrier = carrier
        self.trackingNumber = trackingNumber
    }
}

/// A flight number found on the pasteboard.
public struct ClipboardDetectedFlightNumber: Sendable, Equatable {
    public let matchedString: String
    public let airline: String
    public let flightNumber: String
    public init(matchedString: String, airline: String, flightNumber: String) {
        self.matchedString = matchedString
        self.airline = airline
        self.flightNumber = flightNumber
    }
}

/// An amount of money found on the pasteboard.
public struct ClipboardDetectedMoneyAmount: Sendable, Equatable {
    public let matchedString: String
    /// ISO currency code, for example `USD`.
    public let currencyCode: String
    public let amount: Double
    public init(matchedString: String, currencyCode: String, amount: Double) {
        self.matchedString = matchedString
        self.currencyCode = currencyCode
        self.amount = amount
    }
}

/// Everything the detection system found, keeping each match's full structure.
public struct ClipboardDetectedValues: Sendable, Equatable {
    public let patterns: Set<ClipboardDetectionPattern>
    public let probableWebURL: String?
    public let probableWebSearch: String?
    public let number: Double?
    public let links: [ClipboardDetectedLink]
    public let phoneNumbers: [ClipboardDetectedPhoneNumber]
    public let emailAddresses: [ClipboardDetectedEmailAddress]
    public let postalAddresses: [ClipboardDetectedPostalAddress]
    public let calendarEvents: [ClipboardDetectedCalendarEvent]
    public let shipmentTrackingNumbers: [ClipboardDetectedShipmentTracking]
    public let flightNumbers: [ClipboardDetectedFlightNumber]
    public let moneyAmounts: [ClipboardDetectedMoneyAmount]

    public init(patterns: Set<ClipboardDetectionPattern>,
                probableWebURL: String? = nil,
                probableWebSearch: String? = nil,
                number: Double? = nil,
                links: [ClipboardDetectedLink] = [],
                phoneNumbers: [ClipboardDetectedPhoneNumber] = [],
                emailAddresses: [ClipboardDetectedEmailAddress] = [],
                postalAddresses: [ClipboardDetectedPostalAddress] = [],
                calendarEvents: [ClipboardDetectedCalendarEvent] = [],
                shipmentTrackingNumbers: [ClipboardDetectedShipmentTracking] = [],
                flightNumbers: [ClipboardDetectedFlightNumber] = [],
                moneyAmounts: [ClipboardDetectedMoneyAmount] = []) {
        self.patterns = patterns
        self.probableWebURL = probableWebURL
        self.probableWebSearch = probableWebSearch
        self.number = number
        self.links = links
        self.phoneNumbers = phoneNumbers
        self.emailAddresses = emailAddresses
        self.postalAddresses = postalAddresses
        self.calendarEvents = calendarEvents
        self.shipmentTrackingNumbers = shipmentTrackingNumbers
        self.flightNumbers = flightNumbers
        self.moneyAmounts = moneyAmounts
    }
}

/// Metadata the detection system can report without reading the contents.
public struct ClipboardDetectedMetadata: Sendable, Equatable {
    public let metadataTypes: Set<ClipboardMetadataType>
    public let contentTypeIdentifier: String?

    public init(metadataTypes: Set<ClipboardMetadataType>, contentTypeIdentifier: String?) {
        self.metadataTypes = metadataTypes
        self.contentTypeIdentifier = contentTypeIdentifier
    }
}
