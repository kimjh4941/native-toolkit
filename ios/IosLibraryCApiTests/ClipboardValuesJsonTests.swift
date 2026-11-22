//
//  ClipboardValuesJsonTests.swift
//  IosLibraryCApiTests
//

import IosLibrary
import XCTest
@testable import IosLibraryCApi

/// The form of `ntk_clipboard_detect_values_async`'s JSON, which is part of the ABI (part 2, 6.1, P2-8): the
/// text below is what bindings read. Keys may be added to it, never changed.
final class ClipboardValuesJsonTests: XCTestCase {
    func testTheFormWithNothingDetected() {
        XCTAssertEqual(ClipboardValuesJson.text(of: .empty), """
        {"calendarEvents":[],"detectedPatterns":[],"emailAddresses":[],"flightNumbers":[],"links":[],"moneyAmounts":[],"number":null,"phoneNumbers":[],"postalAddresses":[],"probableWebSearch":null,"probableWebURL":null,"shipmentTrackingNumbers":[]}
        """)
    }

    func testTheFormWithEveryValue() throws {
        let values = ClipboardDetectedValues(
            detectedPatterns: [.number, .link, .probableWebURL],
            probableWebURL: "https://a.example/b",
            probableWebSearch: "search",
            number: 12.5,
            links: ["https://c.example"],
            emailAddresses: [ClipboardLabeledValue(value: "a@b.example", label: "work"), ClipboardLabeledValue(value: "c@d.example", label: nil)],
            phoneNumbers: [ClipboardLabeledValue(value: "+1 555", label: nil)],
            postalAddresses: [ClipboardPostalAddress(street: "s", city: "c", state: nil, postalCode: "p", country: nil)],
            calendarEvents: [ClipboardCalendarEvent(startDate: Date(timeIntervalSince1970: 1_000_000_000.5), endDate: nil,
                                                    startTimeZoneIdentifier: "Asia/Tokyo", endTimeZoneIdentifier: nil, isAllDay: true)],
            flightNumbers: [ClipboardFlightNumber(airline: "NH", flightNumber: "1")],
            moneyAmounts: [ClipboardMoneyAmount(amount: 3.25, currency: "JPY")],
            shipmentTrackingNumbers: [ClipboardShipmentTracking(carrier: "UPS", trackingNumber: "1Z")])
        XCTAssertEqual(ClipboardValuesJson.text(of: values), """
        {"calendarEvents":[{"endDate":null,"endTimeZone":null,"isAllDay":true,"startDate":"2001-09-09T01:46:40.500Z","startTimeZone":"Asia/Tokyo"}],"detectedPatterns":["link","number","probableWebURL"],"emailAddresses":[{"label":"work","value":"a@b.example"},{"label":null,"value":"c@d.example"}],"flightNumbers":[{"airline":"NH","flightNumber":"1"}],"links":["https://c.example"],"moneyAmounts":[{"amount":3.25,"currency":"JPY"}],"number":12.5,"phoneNumbers":[{"label":null,"value":"+1 555"}],"postalAddresses":[{"city":"c","country":null,"postalCode":"p","state":null,"street":"s"}],"probableWebSearch":"search","probableWebURL":"https://a.example/b","shipmentTrackingNumbers":[{"carrier":"UPS","trackingNumber":"1Z"}]}
        """)
    }

    /// Why the values below are written `null`: `JSONSerialization` does not take them. `text(of:)` asks it
    /// first, so with one of them kept it would give nil and the completion UNKNOWN, losing everything else.
    func testJSONSerializationDoesNotTakeWhatIsNotFinite() {
        for number in [Double.nan, .infinity, -.infinity] {
            XCTAssertFalse(JSONSerialization.isValidJSONObject(["number": number]))
        }
    }

    func testWhatIsNotFiniteIsNull() throws {
        for number in [Double.nan, .infinity, -.infinity] {
            let values = ClipboardDetectedValues(detectedPatterns: [], probableWebURL: nil, probableWebSearch: nil, number: number, links: [],
                                                 emailAddresses: [], phoneNumbers: [], postalAddresses: [], calendarEvents: [], flightNumbers: [],
                                                 moneyAmounts: [ClipboardMoneyAmount(amount: number, currency: "JPY")], shipmentTrackingNumbers: [])
            let text = try XCTUnwrap(ClipboardValuesJson.text(of: values))
            XCTAssertTrue(text.contains("\"number\":null"), text)
            XCTAssertTrue(text.contains("{\"amount\":null,\"currency\":\"JPY\"}"), text)
        }
    }

    func testUnicodeAndU0000() throws {
        let values = ClipboardDetectedValues(detectedPatterns: [], probableWebURL: "a\0b", probableWebSearch: "\u{65E5}\u{1F600}\"", number: nil,
                                             links: ["c\0d"], emailAddresses: [], phoneNumbers: [], postalAddresses: [], calendarEvents: [],
                                             flightNumbers: [], moneyAmounts: [], shipmentTrackingNumbers: [])
        let text = try XCTUnwrap(ClipboardValuesJson.text(of: values))
        XCTAssertTrue(text.contains("\"probableWebURL\":\"a\u{FFFD}b\""), text)
        XCTAssertTrue(text.contains("\"links\":[\"c\u{FFFD}d\"]"), text)
        XCTAssertTrue(text.contains("\"probableWebSearch\":\"\u{65E5}\u{1F600}\\\"\""), text)
        XCTAssertFalse(text.contains("\\u0000"), text)
    }
}
