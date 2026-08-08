//
//  UnityIosClipboardJsonParserTests.swift
//  UnityIosPluginTests
//

import Testing
import Foundation
@testable import IosLibrary
@testable import UnityIosPlugin

struct UnityIosClipboardJsonParserTests {
    private let parser = UnityIosClipboardJsonParser()

    @Test func scopeDefaultsToGeneralWhenOmitted() {
        let dict = parser.parseObject(from: "{}")
        #expect(parser.parseScope(dict) == .general)
    }

    @Test func scopeRoundTripsForAllThreeKinds() {
        #expect(parser.parseScope(["scope": ["kind": "general"]]) == .general)
        #expect(parser.parseScope(["scope": ["kind": "named", "name": "g"]]) == .named("g"))
        #expect(parser.parseScope(["scope": ["kind": "unique", "name": "u"]]) == .unique("u"))
    }

    @Test func unknownScopeKindIsRejected() {
        #expect(parser.parseScope(["scope": ["kind": "bogus"]]) == nil)
    }

    @Test(arguments: [
        "{\"scope\": null}",
        "{\"scope\": \"general\"}",
        "{\"scope\": []}",
        "{\"scope\": 1}"
    ])
    func malformedScopeIsRejectedRatherThanTreatedAsGeneral(_ json: String) {
        // A broken request meant for a named pasteboard must never silently act on `general`.
        let dict = parser.parseObject(from: json)!
        #expect(parser.parseScope(dict) == nil)
    }

    @Test(arguments: ["{\"options\": null}", "{\"options\": \"localOnly\"}", "{\"options\": []}"])
    func malformedOptionsIsRejectedRatherThanTreatedAsAbsent(_ json: String) {
        let dict = parser.parseObject(from: json)!
        #expect(parser.parseOptions(dict) == nil)
    }

    @Test(arguments: [
        "{\"options\": {}}",
        "{\"options\": {\"expirationDate\": \"2026-08-08T00:00:00Z\"}}"
    ])
    func omittedLocalOnlyFallsBackToTheDocumentedDefault(_ json: String) {
        // Schema default: `localOnly` is `true`. Omitting it must not make the request invalid.
        let dict = parser.parseObject(from: json)!
        let parsed = parser.parseOptions(dict)
        #expect(parsed != nil)
        #expect(parsed??.localOnly == true)
    }

    @Test(arguments: ["2026-08-08T00:00:00Z", "2026-08-08T00:00:00.000Z"])
    func expirationDateAcceptsISO8601WithAndWithoutFractionalSeconds(_ value: String) {
        let dict = parser.parseObject(from: "{\"options\": {\"expirationDate\": \"\(value)\"}}")!
        #expect(parser.parseOptions(dict)??.expirationDate != nil)
    }

    @Test func malformedExpirationDateIsRejected() {
        let dict = parser.parseObject(from: "{\"options\": {\"expirationDate\": \"not-a-date\"}}")!
        #expect(parser.parseOptions(dict) == nil)
    }

    @Test func presentButNonBoolLocalOnlyIsRejected() {
        let dict = parser.parseObject(from: "{\"options\": {\"localOnly\": \"true\"}}")!
        #expect(parser.parseOptions(dict) == nil)
    }

    @Test func nullRequestJsonIsRejected() {
        #expect(parser.parseObject(from: nil) == nil)
    }

    @Test func malformedJsonIsRejected() {
        #expect(parser.parseObject(from: "{not json") == nil)
    }

    @Test func plainTextContentRoundTrips() {
        let dict = parser.parseObject(from: "{\"content\":{\"kind\":\"plainText\",\"text\":\"hi\"}}")!
        #expect(parser.parseContent(dict) == .plainText("hi"))
    }

    @Test func imageDataContentDecodesBase64() {
        let base64 = Data([1, 2, 3]).base64EncodedString()
        let json = "{\"content\":{\"kind\":\"imageData\",\"base64\":\"\(base64)\",\"utType\":\"public.png\"}}"
        let dict = parser.parseObject(from: json)!
        #expect(parser.parseContent(dict) == .imageData(Data([1, 2, 3]), utType: "public.png"))
    }

    @Test func invalidBase64IsRejected() {
        let dict = parser.parseObject(from: "{\"content\":{\"kind\":\"imageData\",\"base64\":\"not base64!!\",\"utType\":\"public.png\"}}")!
        #expect(parser.parseContent(dict) == nil)
    }

    @Test func unknownContentKindIsRejected() {
        let dict = parser.parseObject(from: "{\"content\":{\"kind\":\"bogus\"}}")!
        #expect(parser.parseContent(dict) == nil)
    }

    @Test func appendRequestWithOptionsKeyIsDetected() {
        let dict = parser.parseObject(from: "{\"content\":{\"kind\":\"plainText\",\"text\":\"hi\"},\"options\":{\"localOnly\":true}}")!
        #expect(parser.containsOptionsKey(dict) == true)
    }

    @Test func absentOptionsYieldsDefault() {
        let dict = parser.parseObject(from: "{}")!
        let result = parser.parseOptions(dict)
        #expect(result != nil)
        #expect((result!) == nil)
    }

    @Test func patternsRoundTrip() {
        let dict = parser.parseObject(from: "{\"patterns\":[\"probableWebURL\",\"number\"]}")!
        #expect(parser.parsePatterns(dict) == [.probableWebURL, .number])
    }

    @Test func unknownPatternIsRejected() {
        let dict = parser.parseObject(from: "{\"patterns\":[\"bogus\"]}")!
        #expect(parser.parsePatterns(dict) == nil)
    }

    @Test func emptyPatternsArrayParsesToEmptySet() {
        let dict = parser.parseObject(from: "{\"patterns\":[]}")!
        #expect(parser.parsePatterns(dict) == [])
    }

    @Test func loadRequestFileKindRequiresUTType() {
        let dict = parser.parseObject(from: "{\"request\":{\"kind\":\"file\"}}")!
        #expect(parser.parseLoadRequest(dict) == nil)
        let validDict = parser.parseObject(from: "{\"request\":{\"kind\":\"file\",\"utType\":\"public.png\"}}")!
        #expect(parser.parseLoadRequest(validDict) == .file(utType: "public.png"))
    }

    @Test func successEnvelopeShape() {
        let json = parser.serializeSuccess(["a": 1])
        let object = try? JSONSerialization.jsonObject(with: Data(json.utf8)) as? [String: Any]
        #expect(object?["ok"] as? Bool == true)
        #expect(object?["data"] != nil)
    }

    @Test func errorEnvelopeShape() {
        let json = parser.serializeError(code: "CLIPBOARD_UNKNOWN", message: "boom")
        let object = try? JSONSerialization.jsonObject(with: Data(json.utf8)) as? [String: Any]
        #expect(object?["ok"] as? Bool == false)
        let error = object?["error"] as? [String: Any]
        #expect(error?["code"] as? String == "CLIPBOARD_UNKNOWN")
        #expect(error?["message"] as? String == "boom")
    }

    @Test func loadedItemSerializesAllFourKinds() {
        #expect((try? JSONSerialization.jsonObject(with: Data(parser.serializeSuccess(parser.serializeLoadedItem(.text("t"))).utf8))) != nil)
        #expect((try? JSONSerialization.jsonObject(with: Data(parser.serializeSuccess(parser.serializeLoadedItem(.url("u"))).utf8))) != nil)
        #expect((try? JSONSerialization.jsonObject(with: Data(parser.serializeSuccess(parser.serializeLoadedItem(.imageData(Data([1]), utType: "public.png"))).utf8))) != nil)
        #expect((try? JSONSerialization.jsonObject(with: Data(parser.serializeSuccess(parser.serializeLoadedItem(.file(URL(fileURLWithPath: "/tmp/x")))).utf8))) != nil)
    }
}
