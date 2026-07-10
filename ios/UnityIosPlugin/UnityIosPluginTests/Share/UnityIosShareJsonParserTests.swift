//
//  UnityIosShareJsonParserTests.swift
//  UnityIosPluginTests
//

import Testing
import IosLibrary
@testable import UnityIosPlugin

struct UnityIosShareJsonParserTests {

    private let parser = UnityIosShareJsonParser()

    @Test func parseContentInvalidJsonReturnsNil() {
        #expect(parser.parseContent(from: "not-json") == nil)
    }

    @Test func parseContentMissingItemsReturnsNil() {
        #expect(parser.parseContent(from: #"{"subject":"s"}"#) == nil)
    }

    @Test func parseContentParsesAllFourTypes() {
        let json = #"""
        {
          "items": [
            {"type":"text","value":"hello"},
            {"type":"url","value":"https://example.com"},
            {"type":"image","value":"/path/to.png"},
            {"type":"file","value":"/path/to.pdf"}
          ]
        }
        """#
        let content = parser.parseContent(from: json)
        #expect(content?.items.count == 4)

        guard let items = content?.items, items.count == 4 else { return }

        if case .text(let value) = items[0] { #expect(value == "hello") } else { Issue.record("expected .text") }
        if case .url(let value) = items[1] { #expect(value == "https://example.com") } else { Issue.record("expected .url") }
        if case .imageFile(let path) = items[2] { #expect(path == "/path/to.png") } else { Issue.record("expected .imageFile") }
        if case .file(let path) = items[3] { #expect(path == "/path/to.pdf") } else { Issue.record("expected .file") }
    }

    @Test func parseContentKeepsUnvalidatedUrlString() {
        let json = #"{"items":[{"type":"url","value":"not-a-valid-url"}]}"#
        let content = parser.parseContent(from: json)
        guard let item = content?.items.first else {
            Issue.record("expected one item")
            return
        }
        if case .url(let value) = item {
            #expect(value == "not-a-valid-url")
        } else {
            Issue.record("expected .url")
        }
    }

    @Test func parseContentIgnoresUnknownTypeAndMissingValue() {
        let json = #"""
        {
          "items": [
            {"type":"unknown","value":"x"},
            {"type":"text"},
            {"type":"text","value":"kept"}
          ]
        }
        """#
        let content = parser.parseContent(from: json)
        #expect(content?.items.count == 1)
        if case .text(let value) = content?.items.first {
            #expect(value == "kept")
        } else {
            Issue.record("expected .text")
        }
    }

    @Test func parseContentReturnsEmptyItemsWhenAllIgnored() {
        let json = #"{"items":[{"type":"unknown","value":"x"}]}"#
        let content = parser.parseContent(from: json)
        #expect(content?.items.isEmpty == true)
    }

    @Test func parseContentWithOptionalFields() {
        let json = #"""
        {
          "items": [{"type":"text","value":"hello"}],
          "subject": "Subject",
          "previewTitle": "Preview",
          "excludedActivityTypes": ["com.apple.UIKit.activity.PostToFacebook"]
        }
        """#
        let content = parser.parseContent(from: json)
        #expect(content?.subject == "Subject")
        #expect(content?.previewTitle == "Preview")
        #expect(content?.excludedActivityTypes == ["com.apple.UIKit.activity.PostToFacebook"])
    }
}
