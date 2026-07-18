//
//  UnityMacShareJsonParserTests.swift
//  UnityMacPluginTests
//
import Testing
@testable import UnityMacPlugin
import MacLibrary

struct UnityMacShareJsonParserTests {

    let parser = UnityMacShareJsonParser()

    // MARK: - success

    @Test func parsesAllFourItemTypes() throws {
        let json = """
        {"items":[
            {"type":"text","value":"hello"},
            {"type":"url","value":"https://example.com"},
            {"type":"image","value":"/tmp/a.png"},
            {"type":"file","value":"/tmp/a.pdf"}
        ]}
        """
        let content = try #require(parser.parseContent(from: json))
        #expect(content.items.count == 4)

        guard case .text(let text) = content.items[0] else { Issue.record("expected .text"); return }
        #expect(text == "hello")

        guard case .url(let url) = content.items[1] else { Issue.record("expected .url"); return }
        #expect(url == "https://example.com")

        guard case .imageFile(let imagePath) = content.items[2] else { Issue.record("expected .imageFile"); return }
        #expect(imagePath == "/tmp/a.png")

        guard case .file(let filePath) = content.items[3] else { Issue.record("expected .file"); return }
        #expect(filePath == "/tmp/a.pdf")
    }

    @Test func urlItemKeepsRawStringUnvalidated() throws {
        let json = """
        {"items":[{"type":"url","value":"not-a-valid-url"}]}
        """
        let content = try #require(parser.parseContent(from: json))
        guard case .url(let raw) = content.items[0] else { Issue.record("expected .url"); return }
        #expect(raw == "not-a-valid-url")
    }

    @Test func unknownTypeIsIgnored() throws {
        let json = """
        {"items":[{"type":"unknown","value":"x"},{"type":"text","value":"kept"}]}
        """
        let content = try #require(parser.parseContent(from: json))
        #expect(content.items.count == 1)
    }

    @Test func missingValueEntryIsIgnored() throws {
        let json = """
        {"items":[{"type":"text"},{"type":"text","value":"kept"}]}
        """
        let content = try #require(parser.parseContent(from: json))
        #expect(content.items.count == 1)
    }

    @Test func allIgnoredResultsInEmptyItems() throws {
        let json = """
        {"items":[{"type":"unknown","value":"x"}]}
        """
        let content = try #require(parser.parseContent(from: json))
        #expect(content.items.isEmpty)
    }

    @Test func recipientsSubjectAndExcludedServiceTitlesAreReflected() throws {
        let json = """
        {"items":[{"type":"text","value":"hi"}],
         "recipients":["a@example.com"],
         "subject":"Hello",
         "excludedServiceTitles":["Add to Reading List"]}
        """
        let content = try #require(parser.parseContent(from: json))
        #expect(content.recipients == ["a@example.com"])
        #expect(content.subject == "Hello")
        #expect(content.excludedServiceTitles == ["Add to Reading List"])
    }

    @Test func recipientsSubjectExcludedServiceTitlesDefaultWhenAbsent() throws {
        let json = """
        {"items":[{"type":"text","value":"hi"}]}
        """
        let content = try #require(parser.parseContent(from: json))
        #expect(content.recipients.isEmpty)
        #expect(content.subject == nil)
        #expect(content.excludedServiceTitles.isEmpty)
    }

    // MARK: - failure

    @Test func malformedJsonReturnsNil() {
        #expect(parser.parseContent(from: "not json") == nil)
    }

    @Test func missingItemsKeyReturnsNil() {
        #expect(parser.parseContent(from: "{\"subject\":\"x\"}") == nil)
    }
}
