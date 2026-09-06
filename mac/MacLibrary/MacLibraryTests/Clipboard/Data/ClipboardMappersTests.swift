//
//  ClipboardMappersTests.swift
//  MacLibraryTests
//

import Testing
import AppKit
import Foundation
@testable import MacLibrary

@Suite("ClipboardMappers")
@MainActor
struct ClipboardMappersTests {

    private let text = "public.utf8-plain-text"
    private let rtf = "public.rtf"

    private func content(_ representations: [String: Data]...) -> ClipboardContent {
        ClipboardContent(items: representations.map { ClipboardItemData(representations: $0) })
    }

    @Test("every representation reaches the pasteboard item")
    func writesEveryRepresentation() throws {
        let source = content([text: Data("hello".utf8), rtf: Data("{\\rtf1}".utf8)])
        let items = try ClipboardMappers.makeItems(from: source)

        #expect(items.count == 1)
        #expect(Set(items[0].types.map(\.rawValue)) == [text, rtf])
        #expect(items[0].data(forType: .init(text)) == Data("hello".utf8))
    }

    @Test("item order is preserved")
    func preservesItemOrder() throws {
        let source = content([text: Data("first".utf8)], [text: Data("second".utf8)])
        let items = try ClipboardMappers.makeItems(from: source)

        #expect(items.count == 2)
        #expect(items[0].data(forType: .init(text)) == Data("first".utf8))
        #expect(items[1].data(forType: .init(text)) == Data("second".utf8))
    }

    @Test("each call produces fresh items")
    func producesFreshItems() throws {
        // An NSPasteboardItem belongs to the pasteboard once written, so reusing one across
        // writes is what RK-14 forbids. Identity is the only observable proof.
        let source = content([text: Data("value".utf8)])
        let first = try ClipboardMappers.makeItems(from: source)
        let second = try ClipboardMappers.makeItems(from: source)
        #expect(first[0] !== second[0])
    }

    @Test("an empty content maps to no items")
    func emptyContent() throws {
        #expect(try ClipboardMappers.makeItems(from: ClipboardContent(items: [])).isEmpty)
    }

    @Test("an item with no representations maps to an empty pasteboard item")
    func emptyRepresentations() throws {
        // Rejecting this is the validator's job, not the mapper's; the mapper stays total.
        let items = try ClipboardMappers.makeItems(from: content([:]))
        #expect(items.count == 1)
        #expect(items[0].types.isEmpty)
    }

    @Test("a malformed identifier is reported rather than silently dropped")
    func rejectsMalformedIdentifier() {
        // setData returns false for an identifier NSPasteboardItem cannot use. Without this
        // check the representation would vanish and the write would look successful.
        let source = content(["not a uti": Data("value".utf8)])
        #expect(throws: ClipboardError.invalidTypeIdentifier("not a uti")) {
            _ = try ClipboardMappers.makeItems(from: source)
        }
    }

    @Test("reading returns every representation of every item")
    func readsEveryRepresentation() throws {
        let source = content([text: Data("a".utf8), rtf: Data("b".utf8)], [text: Data("c".utf8)])
        let items = try ClipboardMappers.makeItems(from: source)

        let mapped = ClipboardMappers.makeItemData(from: items)
        #expect(mapped.count == 2)
        #expect(mapped[0].representations == [text: Data("a".utf8), rtf: Data("b".utf8)])
        #expect(mapped[1].representations == [text: Data("c".utf8)])
    }

    @Test("a write followed by a read round trips")
    func roundTrips() throws {
        let source = content([text: Data("round".utf8)], [rtf: Data("trip".utf8)])
        let mapped = ClipboardMappers.makeItemData(from: try ClipboardMappers.makeItems(from: source))
        #expect(ClipboardContent(items: mapped) == source)
    }

    @Test("reading no items yields no data")
    func readsEmpty() {
        #expect(ClipboardMappers.makeItemData(from: []).isEmpty)
    }

    @Test("types are reported without reading any payload")
    func reportsTypesOnly() throws {
        let source = content([text: Data("a".utf8), rtf: Data("b".utf8)], [text: Data("c".utf8)])
        let items = try ClipboardMappers.makeItems(from: source)

        let types = ClipboardMappers.makeItemTypes(from: items)
        #expect(types.count == 2)
        #expect(Set(types[0]) == [text, rtf])
        #expect(types[1] == [text])
    }
}
