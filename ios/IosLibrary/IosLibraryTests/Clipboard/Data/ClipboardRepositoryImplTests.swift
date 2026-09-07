//
//  ClipboardRepositoryImplTests.swift
//  IosLibraryTests
//
//  Exercises the real `UIPasteboard` via `withUniqueName()`, never touching `.general`.
//

import Testing
import Foundation
import UIKit
@testable import IosLibrary

@MainActor
struct ClipboardRepositoryImplTests {
    private func makeScope() -> PasteboardScope {
        let pasteboard = UIPasteboard.withUniqueName()
        return .unique(pasteboard.name.rawValue)
    }

    @Test func plainTextRoundTrips() async throws {
        let repository = ClipboardRepositoryImpl()
        let scope = makeScope()
        try await repository.copy(.plainText("hello"), options: .default, scope: scope)
        let result = try repository.read(scope: scope)
        #expect(result.numberOfItems == 1)
        #expect(result.items.first?.text == "hello")
    }

    @Test func multiRepresentationProducesTwoTypeIdentifiersOnOneItem() async throws {
        let repository = ClipboardRepositoryImpl()
        let scope = makeScope()
        let content = ClipboardContent.multiRepresentation([
            "public.utf8-plain-text": Data("hi".utf8),
            "public.html": Data("<b>hi</b>".utf8)
        ])
        try await repository.copy(content, options: .default, scope: scope)
        let result = try repository.read(scope: scope)
        #expect(result.numberOfItems == 1)
        // The system may report additional, UTI-conformance-derived representations beyond the
        // two explicitly written; assert both requested types are present rather than an exact
        // count (observed 4 on iOS 26.2 simulator, presumably synthesized conforming aliases).
        let typeIdentifiers = result.items.first?.typeIdentifiers ?? []
        #expect(typeIdentifiers.contains("public.utf8-plain-text"))
        #expect(typeIdentifiers.contains("public.html"))
    }

    @Test func appendIncreasesItemCount() async throws {
        let repository = ClipboardRepositoryImpl()
        let scope = makeScope()
        try await repository.copy(.plainText("first"), options: .default, scope: scope)
        try await repository.append(.plainText("second"), scope: scope)
        let result = try repository.read(scope: scope)
        #expect(result.numberOfItems == 2)
    }

    @Test func clearEmptiesClipboard() async throws {
        let repository = ClipboardRepositoryImpl()
        let scope = makeScope()
        try await repository.copy(.plainText("hi"), options: .default, scope: scope)
        try repository.clear(scope: scope)
        #expect(try repository.read(scope: scope).numberOfItems == 0)
    }

    @Test func snapshotReflectsContent() async throws {
        let repository = ClipboardRepositoryImpl()
        let scope = makeScope()
        try await repository.copy(.plainText("hi"), options: .default, scope: scope)
        let snapshot = try repository.snapshot(matchingTypes: nil, scope: scope)
        #expect(snapshot.hasStrings == true)
        #expect(snapshot.numberOfItems == 1)
    }

    @Test func readDataReturnsMatchingUTIData() async throws {
        let repository = ClipboardRepositoryImpl()
        let scope = makeScope()
        let payload = Data("payload".utf8)
        try await repository.copy(.customData(payload, utType: "com.example.nativetoolkit.test"), options: .default, scope: scope)
        let data = try repository.readData(utType: "com.example.nativetoolkit.test", scope: scope)
        #expect(data == payload)
        let missing = try repository.readData(utType: "com.example.nativetoolkit.missing", scope: scope)
        #expect(missing == nil)
    }

    @Test func copyToUnresolvableNamedScopeThrowsPasteboardUnavailable() async {
        let repository = ClipboardRepositoryImpl()
        await #expect(throws: ClipboardError.self) {
            try await repository.copy(.plainText("hi"), options: .default, scope: .named("does-not-exist-\(UUID().uuidString)"))
        }
    }

    @Test func removeThenResolveFails() async throws {
        let repository = ClipboardRepositoryImpl()
        let pasteboard = UIPasteboard.withUniqueName()
        let scope = PasteboardScope.unique(pasteboard.name.rawValue)
        try repository.removePasteboard(scope)
        await #expect(throws: ClipboardError.self) {
            try await repository.copy(.plainText("hi"), options: .default, scope: scope)
        }
    }

    @Test func imageFileNotFoundThrows() async {
        let repository = ClipboardRepositoryImpl()
        let scope = makeScope()
        await #expect(throws: ClipboardError.self) {
            try await repository.copy(.imageFile(path: "/no/such/file-\(UUID().uuidString).png"), options: .default, scope: scope)
        }
    }
}
