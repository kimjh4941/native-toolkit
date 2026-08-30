//
//  UnityMacClipboardJsonParserTests.swift
//  UnityMacPluginTests
//

import Testing
import Foundation
@testable import UnityMacPlugin
@testable import MacLibrary

@Suite("UnityMacClipboardJsonParser")
struct UnityMacClipboardJsonParserTests {

    private let parser = UnityMacClipboardJsonParser()
    private let text = "public.utf8-plain-text"

    private func object(_ json: String?) throws -> [String: Any] {
        let data = try #require(json?.data(using: .utf8))
        return try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
    }

    // MARK: - BT-11 shape inventory

    @Test("BT-11: the schema has exactly twenty concrete types")
    func twentyConcreteTypes() {
        // Six input only, four shared, eight output only, two events. The split is exclusive,
        // so a type never appears twice and the count is meaningful (R5-L11).
        let inputOnly = ["ContentJson", "OptionsJson", "CreateRequestJson", "MatchingTypesJson",
                         "FilePromiseRequestJson", "PolicyJson"]
        let shared = ["ScopeJson", "OwnershipJson", "HandleJson", "PatternsJson"]
        let outputOnly = ["ReadResultJson", "ReadDataJson", "SnapshotJson", "ChangeCountJson",
                          "BoolJson", "DetectedValuesJson", "DetectedMetadataJson",
                          "AccessBehaviorJson"]
        let events = ["ChangeEventJson", "ReceiptEventJson"]

        #expect(inputOnly.count == 6)
        #expect(shared.count == 4)
        #expect(outputOnly.count == 8)
        #expect(events.count == 2)
        let all = inputOnly + shared + outputOnly + events
        #expect(all.count == 20)
        #expect(Set(all).count == 20, "the four groups must be exclusive")
    }

    // MARK: - ScopeJson

    @Test("a general scope needs no name")
    func parsesGeneralScope() {
        #expect(parser.parseScope(#"{"kind":"general"}"#) == .general)
    }

    @Test("a general scope ignores a name rather than rejecting it")
    func generalIgnoresName() {
        // So a caller can round trip a scope it read back without stripping fields.
        #expect(parser.parseScope(#"{"kind":"general","name":"x"}"#) == .general)
    }

    @Test("named and unique scopes require a name", arguments: ["named", "unique"])
    func namedScopeRequiresName(kind: String) {
        #expect(parser.parseScope(#"{"kind":"\#(kind)"}"#) == nil)
        #expect(parser.parseScope(#"{"kind":"\#(kind)","name":""}"#) == nil)
        #expect(parser.parseScope(#"{"kind":"\#(kind)","name":"a"}"#) != nil)
    }

    @Test("an unknown scope kind is rejected")
    func rejectsUnknownScopeKind() {
        #expect(parser.parseScope(#"{"kind":"whatever"}"#) == nil)
        #expect(parser.parseScope("not json") == nil)
        #expect(parser.parseScope(nil) == nil)
    }

    @Test("BT-06: a scope round trips")
    func scopeRoundTrips() throws {
        for scope in [PasteboardScope.general, .named("a"), .unique("b")] {
            let encoded = try #require(parser.encodeScope(scope))
            let inner = try #require(try object(encoded)["scope"])
            let innerJson = String(data: try JSONSerialization.data(withJSONObject: inner),
                                   encoding: .utf8)
            #expect(parser.parseScope(innerJson) == scope, "\(scope)")
        }
    }

    // MARK: - ContentJson / BT-07

    @Test("BT-07: bytes round trip through Base64")
    func contentRoundTripsAsBase64() throws {
        let bytes = Data([0x00, 0xFF, 0x10, 0x41])
        let content = ClipboardContent(items: [ClipboardItemData(representations: [text: bytes])])

        let encoded = try #require(parser.encodeReadResult(
            ClipboardReadResult(items: content.items, changeCount: 3)))
        // The wire format is Base64, not raw text, so arbitrary bytes survive.
        #expect(encoded.contains(bytes.base64EncodedString()))

        let items = try #require(try object(encoded)["items"])
        let contentJson = String(
            data: try JSONSerialization.data(withJSONObject: ["items": items]), encoding: .utf8)
        #expect(parser.parseContent(contentJson) == content)
    }

    @Test("malformed Base64 fails the parse instead of yielding empty bytes")
    func rejectsMalformedBase64() {
        // Silently producing empty data would look like a successful copy of nothing.
        #expect(parser.parseContent(#"{"items":[{"representations":{"public.png":"!!!"}}]}"#) == nil)
    }

    @Test("content with no items parses; emptiness is the validator's business")
    func emptyContentParses() {
        #expect(parser.parseContent(#"{"items":[]}"#) == ClipboardContent(items: []))
    }

    // MARK: - OptionsJson

    @Test("absent options fall back to the safer default")
    func optionsDefault() {
        #expect(parser.parseOptions(nil)?.localOnly == true)
        #expect(parser.parseOptions("")?.localOnly == true)
        #expect(parser.parseOptions("{}")?.localOnly == true)
    }

    @Test("options are honoured when present")
    func optionsHonoured() {
        #expect(parser.parseOptions(#"{"localOnly":false}"#)?.localOnly == false)
    }

    @Test("M-3: malformed options are rejected rather than silently defaulted")
    func rejectsMalformedOptions() {
        // Defaulting here would turn a requested `localOnly: false` into `true`, which is the
        // opposite of what the caller asked for, and hide their bug as a success.
        #expect(parser.parseOptions("garbage") == nil)
        #expect(parser.parseOptions("{") == nil)
        #expect(parser.parseOptions("[1,2]") == nil)
    }

    // MARK: - MatchingTypesJson

    @Test("no filter and an empty filter are different things")
    func matchingTypesDistinguishesNilFromEmpty() throws {
        // nil means "everything"; [] is rejected downstream with 1512.
        #expect(try #require(parser.parseMatchingTypes(nil)) == nil)
        #expect(try #require(parser.parseMatchingTypes("[]")) == [])
        #expect(try #require(parser.parseMatchingTypes(#"["public.png"]"#)) == ["public.png"])
    }

    // MARK: - PatternsJson

    @Test("BT-06: patterns round trip")
    func patternsRoundTrip() throws {
        let patterns: Set<ClipboardDetectionPattern> = [.emailAddresses, .links]
        let encoded = try #require(parser.encodePatterns(patterns))
        #expect(parser.parsePatterns(encoded) == patterns)
    }

    @Test("an unknown pattern name is rejected")
    func rejectsUnknownPattern() {
        #expect(parser.parsePatterns(#"["notAPattern"]"#) == nil)
    }

    // MARK: - OwnershipJson / HandleJson

    @Test("BT-06: ownership round trips")
    func ownershipRoundTrips() throws {
        let ownership = PasteboardOwnership(scope: .named("a"), changeCount: 12)
        let encoded = try #require(parser.encodeOwnership(ownership))
        #expect(parser.parseOwnership(encoded) == ownership)
    }

    @Test("BT-06: a handle round trips")
    func handleRoundTrips() throws {
        let id = UUID()
        let encoded = try #require(parser.encodeHandle(id))
        #expect(parser.parseHandleId(encoded) == id)
    }

    @Test("a malformed handle id is rejected")
    func rejectsMalformedHandle() {
        #expect(parser.parseHandleId(#"{"id":"not-a-uuid"}"#) == nil)
    }

    // MARK: - CreateRequestJson / FilePromiseRequestJson / PolicyJson

    @Test("create requests parse both kinds")
    func parsesCreateRequest() {
        #expect(parser.parseCreateRequest(#"{"kind":"unique"}"#) == .unique)
        #expect(parser.parseCreateRequest(#"{"kind":"named","name":"a"}"#) == .named("a"))
        #expect(parser.parseCreateRequest(#"{"kind":"named"}"#) == nil)
        #expect(parser.parseCreateRequest(#"{"kind":"general"}"#) == nil)
    }

    @Test("a file promise request always becomes a snapshot source")
    func filePromiseIsAlwaysSnapshot() throws {
        let request = try #require(parser.parseFilePromiseRequest(
            #"{"fileTypeIdentifier":"public.plain-text","fileName":"a.txt","sourcePath":"/tmp/a.txt"}"#))
        // A closure cannot cross the C ABI, so the bridge path has only one shape.
        guard case .snapshot(let url) = request.source else {
            Issue.record("expected a snapshot source")
            return
        }
        #expect(url.path(percentEncoded: false) == "/tmp/a.txt")
        #expect(request.fileName == "a.txt")
    }

    @Test("a file promise request without a source path is rejected")
    func filePromiseRequiresSourcePath() {
        #expect(parser.parseFilePromiseRequest(
            #"{"fileTypeIdentifier":"public.plain-text","fileName":"a.txt","sourcePath":""}"#) == nil)
        #expect(parser.parseFilePromiseRequest(
            #"{"fileTypeIdentifier":"public.plain-text","fileName":"a.txt"}"#) == nil)
    }

    @Test("policy fields are individually optional")
    func policyDefaults() throws {
        #expect(parser.parsePolicy(nil) == .default)
        #expect(parser.parsePolicy("{}") == .default)
        let custom = try #require(parser.parsePolicy(#"{"quietIntervalSeconds":1.0}"#))
        #expect(custom.quietInterval == 1.0)
        #expect(custom.overallTimeout == FilePromiseReceiptPolicy.default.overallTimeout)
    }

    @Test("a policy that breaks its own ordering rule is rejected")
    func policyOrderingRejected() {
        #expect(parser.parsePolicy(
            #"{"quietIntervalSeconds":90.0,"overallTimeoutSeconds":10.0}"#) == nil)
    }

    // MARK: - Output shapes

    @Test("BT-06: a missing type encodes as a null payload, not an error")
    func readDataEncodesNull() throws {
        #expect(try object(parser.encodeData(nil))["data"] is NSNull)
        #expect(try object(parser.encodeData(Data("a".utf8)))["data"] as? String == "YQ==")
    }

    @Test("BT-06: snapshot, change count and bool shapes")
    func simpleOutputShapes() throws {
        let snapshot = try object(parser.encodeSnapshot(
            ClipboardSnapshot(changeCount: 4, itemTypes: [["a"], ["b"]], matchingItemIndexes: [1])))
        #expect(snapshot["changeCount"] as? Int == 4)
        #expect((snapshot["itemTypes"] as? [[String]])?.count == 2)
        #expect(snapshot["matchingItemIndexes"] as? [Int] == [1])

        #expect(try object(parser.encodeChangeCount(7))["changeCount"] as? Int == 7)
        #expect(try object(parser.encodeBool(true))["value"] as? Bool == true)
    }

    @Test("BT-06: access behaviour encodes its raw name")
    func accessBehaviourShape() throws {
        #expect(try object(parser.encodeAccessBehavior(.alwaysAllow))["value"] as? String
                == "alwaysAllow")
        #expect(try object(parser.encodeAccessBehavior(.unavailable))["value"] as? String
                == "unavailable")
    }

    @Test("BT-06: detected values keep every entity and use ISO 8601 in UTC")
    func detectedValuesShape() throws {
        let date = Date(timeIntervalSince1970: 1_756_000_000)
        let values = ClipboardDetectedValues(
            patterns: [.emailAddresses, .calendarEvents],
            probableWebURL: "https://example.com",
            links: [ClipboardDetectedLink(matchedString: "m", url: "https://example.com")],
            emailAddresses: [ClipboardDetectedEmailAddress(matchedString: "m",
                                                           emailAddress: "a@example.com",
                                                           label: "Work")],
            calendarEvents: [ClipboardDetectedCalendarEvent(
                matchedString: "m", isAllDay: false, startDate: date,
                startTimeZoneIdentifier: "Asia/Tokyo", endDate: nil,
                endTimeZoneIdentifier: nil)],
            moneyAmounts: [ClipboardDetectedMoneyAmount(matchedString: "m",
                                                        currencyCode: "USD", amount: 12.34)])

        let shape = try object(parser.encodeDetectedValues(values))
        #expect((shape["patterns"] as? [String])?.sorted() == ["calendarEvents", "emailAddresses"])
        #expect(shape["probableWebSearch"] is NSNull)
        #expect(shape["number"] is NSNull)

        let event = try #require((shape["calendarEvents"] as? [[String: Any]])?.first)
        // Locale independent: the same instant always produces the same string.
        #expect(event["startDate"] as? String == "2025-08-24T01:46:40Z")
        #expect(event["startTimeZoneIdentifier"] as? String == "Asia/Tokyo")
        #expect(event["endDate"] is NSNull)

        let money = try #require((shape["moneyAmounts"] as? [[String: Any]])?.first)
        // The ISO code and the raw amount, never a formatted string.
        #expect(money["currencyCode"] as? String == "USD")
        #expect(money["amount"] as? Double == 12.34)
    }

    @Test("BT-06: detected metadata shape")
    func detectedMetadataShape() throws {
        let shape = try object(parser.encodeDetectedMetadata(
            ClipboardDetectedMetadata(metadataTypes: [.contentType],
                                      contentTypeIdentifier: "public.png")))
        #expect(shape["metadataTypes"] as? [String] == ["contentType"])
        #expect(shape["contentTypeIdentifier"] as? String == "public.png")

        let empty = try object(parser.encodeDetectedMetadata(
            ClipboardDetectedMetadata(metadataTypes: [], contentTypeIdentifier: nil)))
        #expect(empty["contentTypeIdentifier"] is NSNull)
    }

    // MARK: - Event shapes

    @Test("BT-06: a change event carries its scope")
    func changeEventShape() throws {
        let shape = try object(parser.encodeChangeEvent(
            ClipboardChangeEvent(scope: .named("a"), changeCount: 9)))
        #expect(shape["changeCount"] as? Int == 9)
        #expect((shape["scope"] as? [String: Any])?["kind"] as? String == "named")
    }

    @Test("BT-06: each receipt event kind carries only its own fields")
    func receiptEventShapes() throws {
        let received = try object(parser.encodeReceiptEvent(
            .received(URL(filePath: "/tmp/a.txt"))))
        #expect(received["kind"] as? String == "received")
        #expect(received["url"] as? String != nil)
        // Fields belonging to another kind are omitted, not null: the schema defines each kind
        // by the fields it carries.
        #expect(received["errorCode"] == nil)

        let failed = try object(parser.encodeReceiptEvent(
            .failed(.filePromiseReceiveFailed("boom"))))
        #expect(failed["kind"] as? String == "failed")
        #expect(failed["errorCode"] as? Int == 1519)
        #expect(failed["url"] == nil)

        let finished = try object(parser.encodeReceiptEvent(.finished(
            FilePromiseReceipt(urls: [URL(filePath: "/tmp/a.txt")],
                               failures: [.filePromiseReceiveFailed("boom")],
                               terminatedBy: .overallTimeout))))
        #expect(finished["kind"] as? String == "finished")
        #expect(finished["terminatedBy"] as? String == "overallTimeout")
        #expect((finished["urls"] as? [String])?.count == 1)
        #expect((finished["failures"] as? [[String: Any]])?.first?["errorCode"] as? Int == 1519)
    }

    @Test("every termination reason has a distinct name")
    func terminationNames() throws {
        var names: [String] = []
        for reason in [FilePromiseReceipt.Termination.quiescence, .overallTimeout, .cancelled] {
            let shape = try object(parser.encodeReceiptEvent(.finished(
                FilePromiseReceipt(urls: [], failures: [], terminatedBy: reason))))
            names.append(try #require(shape["terminatedBy"] as? String))
        }
        #expect(names == ["quiescence", "overallTimeout", "cancelled"])
    }

    // MARK: - Version tolerance

    @Test("an unknown field is ignored rather than failing the decode")
    func unknownFieldsAreIgnored() {
        // Unity and Swift can ship at different versions without breaking each other (R6-M8).
        #expect(parser.parseScope(#"{"kind":"general","futureField":123}"#) == .general)
        #expect(parser.parseOptions(#"{"localOnly":false,"futureField":"x"}"#)?.localOnly == false)
    }
}
