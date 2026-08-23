//
//  ClipboardLogRedactionTests.swift
//  IosLibraryTests
//

import Testing
import Foundation
@testable import IosLibrary

struct ClipboardLogRedactionTests {

    @Test func redactionNeverEchoesTheOriginalValue() {
        #expect(!ClipboardRedaction.text("super-secret-text").contains("secret"))
        #expect(!ClipboardRedaction.json("{\"secret\":\"value\"}").contains("secret"))
        #expect(!ClipboardRedaction.path("/private/secret/photo.png").contains("secret"))
    }

    @Test func redactionKeepsOnlyNonSensitiveMetadata() {
        #expect(ClipboardRedaction.text("abcd") == "<text:4>")
        #expect(ClipboardRedaction.dataByteCount(2048) == "<data:2048>")
        // The extension is retained because it is a type hint, not caller data.
        #expect(ClipboardRedaction.path("/a/b/photo.png").contains("ext=png"))
    }

    @Test func pasteboardScopeLogDescriptionNeverContainsTheName() {
        let named = PasteboardScope.named("group.com.example.secret-app")
        let unique = PasteboardScope.unique("secret-unique-name")
        #expect(!named.redactedDescription.contains("secret"))
        #expect(!unique.redactedDescription.contains("secret"))
        #expect(named.redactedDescription.hasPrefix("named"))
        #expect(unique.redactedDescription.hasPrefix("unique"))
        #expect(PasteboardScope.general.redactedDescription == "general")
    }

    @Test func pasteboardCreationRequestLogDescriptionNeverContainsTheName() {
        #expect(!PasteboardCreationRequest.named("secret-name").redactedDescription.contains("secret"))
        #expect(PasteboardCreationRequest.unique.redactedDescription == "unique")
    }

    @Test func failureDetailDescriptionExcludesDebugMessage() {
        let detail = ClipboardFailureDetail(domain: "d", code: 7, debugMessage: "secret debug text")
        let described = ClipboardLog.describe(detail)
        #expect(!described.contains("secret"))
        #expect(described.contains("code=7"))
    }
}
