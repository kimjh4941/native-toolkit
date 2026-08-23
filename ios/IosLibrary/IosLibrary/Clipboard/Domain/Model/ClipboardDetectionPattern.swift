//
//  ClipboardDetectionPattern.swift
//  IosLibrary
//

import Foundation

/// A content pattern that the data detection system can identify on the pasteboard, without
/// reading (and thus without triggering a user prompt or notification for) the clipboard body.
public enum ClipboardDetectionPattern: String, CaseIterable, Sendable {
    case probableWebURL
    case probableWebSearch
    case number
    case link
    case emailAddress
    case phoneNumber
    case postalAddress
    case calendarEvent
    case flightNumber
    case moneyAmount
    case shipmentTrackingNumber
}
