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
public enum ClipboardAccessBehavior: String, Sendable, Equatable, CaseIterable {
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
    /// The text exactly as it appeared on the pasteboard.
    public let matchedString: String
    /// Absolute URL string. Not re-encoded or normalised.
    public let url: String
    /// Creates a detected value from the fields the detector reported.
    public init(matchedString: String, url: String) {
        self.matchedString = matchedString
        self.url = url
    }
}

/// A phone number found on the pasteboard.
public struct ClipboardDetectedPhoneNumber: Sendable, Equatable {
    /// The text exactly as it appeared on the pasteboard.
    public let matchedString: String
    /// The number in the form the detector produced.
    public let phoneNumber: String
    /// Label the detector attached, such as a contact field name. Often absent.
    public let label: String?
    /// Creates a detected value from the fields the detector reported.
    public init(matchedString: String, phoneNumber: String, label: String?) {
        self.matchedString = matchedString
        self.phoneNumber = phoneNumber
        self.label = label
    }
}

/// An email address found on the pasteboard.
public struct ClipboardDetectedEmailAddress: Sendable, Equatable {
    /// The text exactly as it appeared on the pasteboard.
    public let matchedString: String
    /// The address in the form the detector produced.
    public let emailAddress: String
    /// Label the detector attached, such as a contact field name. Often absent.
    public let label: String?
    /// Creates a detected value from the fields the detector reported.
    public init(matchedString: String, emailAddress: String, label: String?) {
        self.matchedString = matchedString
        self.emailAddress = emailAddress
        self.label = label
    }
}

/// A postal address found on the pasteboard. Every component is optional.
public struct ClipboardDetectedPostalAddress: Sendable, Equatable {
    /// The text exactly as it appeared on the pasteboard.
    public let matchedString: String
    /// Street line, when the address included one.
    public let street: String?
    /// City, when the address included one.
    public let city: String?
    /// State or region, when the address included one.
    public let state: String?
    /// Postal code, when the address included one.
    public let postalCode: String?
    /// Country, when the address included one.
    public let country: String?
    /// Creates a detected value from the fields the detector reported.
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
    /// The text exactly as it appeared on the pasteboard.
    public let matchedString: String
    /// Whether the event covers whole days rather than a time range.
    public let isAllDay: Bool
    /// Start instant. Kept as a `Date`; never formatted, so no locale is baked in.
    public let startDate: Date?
    /// Time zone identifier such as `Asia/Tokyo`, never a localized name.
    public let startTimeZoneIdentifier: String?
    /// End instant, when the event had one.
    public let endDate: Date?
    /// Time zone identifier for the end, when the event had one.
    public let endTimeZoneIdentifier: String?
    /// Creates a detected value from the fields the detector reported.
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
    /// The text exactly as it appeared on the pasteboard.
    public let matchedString: String
    /// Carrier name as reported by the detector.
    public let carrier: String
    /// Tracking number as reported by the detector.
    public let trackingNumber: String
    /// Creates a detected value from the fields the detector reported.
    public init(matchedString: String, carrier: String, trackingNumber: String) {
        self.matchedString = matchedString
        self.carrier = carrier
        self.trackingNumber = trackingNumber
    }
}

/// A flight number found on the pasteboard.
public struct ClipboardDetectedFlightNumber: Sendable, Equatable {
    /// The text exactly as it appeared on the pasteboard.
    public let matchedString: String
    /// Airline code as reported by the detector.
    public let airline: String
    /// Flight number as reported by the detector.
    public let flightNumber: String
    /// Creates a detected value from the fields the detector reported.
    public init(matchedString: String, airline: String, flightNumber: String) {
        self.matchedString = matchedString
        self.airline = airline
        self.flightNumber = flightNumber
    }
}

/// An amount of money found on the pasteboard.
public struct ClipboardDetectedMoneyAmount: Sendable, Equatable {
    /// The text exactly as it appeared on the pasteboard.
    public let matchedString: String
    /// ISO currency code, for example `USD`.
    public let currencyCode: String
    /// Numeric amount, unformatted.
    public let amount: Double
    /// Creates a detected value from the fields the detector reported.
    public init(matchedString: String, currencyCode: String, amount: Double) {
        self.matchedString = matchedString
        self.currencyCode = currencyCode
        self.amount = amount
    }
}

/// Everything the detection system found, keeping each match's full structure.
public struct ClipboardDetectedValues: Sendable, Equatable {
    /// Patterns the system actually matched. The authority for which fields below are meaningful.
    public let patterns: Set<ClipboardDetectionPattern>
    /// Matched web URL, or `nil` when the pattern did not match.
    public let probableWebURL: String?
    /// Matched search term, or `nil` when the pattern did not match.
    public let probableWebSearch: String?
    /// Matched number, or `nil` when the pattern did not match.
    public let number: Double?
    /// Matched links. Empty when none were found.
    public let links: [ClipboardDetectedLink]
    /// Matched phone numbers. Empty when none were found.
    public let phoneNumbers: [ClipboardDetectedPhoneNumber]
    /// Matched email addresses. Empty when none were found.
    public let emailAddresses: [ClipboardDetectedEmailAddress]
    /// Matched postal addresses. Empty when none were found.
    public let postalAddresses: [ClipboardDetectedPostalAddress]
    /// Matched calendar events. Empty when none were found.
    public let calendarEvents: [ClipboardDetectedCalendarEvent]
    /// Matched tracking numbers. Empty when none were found.
    public let shipmentTrackingNumbers: [ClipboardDetectedShipmentTracking]
    /// Matched flight numbers. Empty when none were found.
    public let flightNumbers: [ClipboardDetectedFlightNumber]
    /// Matched money amounts. Empty when none were found.
    public let moneyAmounts: [ClipboardDetectedMoneyAmount]

    /// Creates a detected value from the fields the detector reported.
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
    /// Metadata types the system actually reported.
    public let metadataTypes: Set<ClipboardMetadataType>
    /// Content type of a file reference, or `nil` when there was none.
    public let contentTypeIdentifier: String?

    /// Creates a detected value from the fields the detector reported.
    public init(metadataTypes: Set<ClipboardMetadataType>, contentTypeIdentifier: String?) {
        self.metadataTypes = metadataTypes
        self.contentTypeIdentifier = contentTypeIdentifier
    }
}
