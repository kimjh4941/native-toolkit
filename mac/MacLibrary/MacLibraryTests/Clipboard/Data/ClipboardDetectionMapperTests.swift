//
//  ClipboardDetectionMapperTests.swift
//  MacLibraryTests
//

import Testing
import AppKit
import Foundation
@testable import MacLibrary

@Suite("Clipboard detection")
@MainActor
struct ClipboardDetectionMapperTests {

    private let text = "public.utf8-plain-text"

    private func makeRepository() -> ClipboardRepositoryImpl {
        ClipboardRepositoryImpl(validator: ClipboardTypeIdentifierValidator())
    }

    private func withScratchPasteboard(
        _ body: (ClipboardRepositoryImpl, PasteboardScope) async throws -> Void
    ) async throws {
        let repository = makeRepository()
        let scope = try repository.createPasteboard(.unique)
        defer { try? repository.removePasteboard(scope) }
        try await body(repository, scope)
    }

    // MARK: - Pattern mapping

    @available(macOS 15.4, *)
    @Test("every domain pattern maps to a distinct key path")
    func patternsMapOneToOne() {
        let keyPaths = ClipboardDetectionMapper.keyPaths(
            for: Set(ClipboardDetectionPattern.allCases))
        // A collision would silently merge two patterns into one request.
        #expect(keyPaths.count == ClipboardDetectionPattern.allCases.count)
    }

    @available(macOS 15.4, *)
    @Test("the mapping round trips")
    func patternRoundTrip() {
        for pattern in ClipboardDetectionPattern.allCases {
            let back = ClipboardDetectionMapper.patterns(
                from: [ClipboardDetectionMapper.keyPath(for: pattern)])
            #expect(back == [pattern], "\(pattern)")
        }
    }

    @available(macOS 15.4, *)
    @Test("an unknown key path is ignored rather than failing")
    func unknownKeyPathIsIgnored() {
        // A later macOS can report a pattern this version has no case for.
        let unknown: PartialKeyPath<NSPasteboard.DetectedValues> = \NSPasteboard.DetectedValues.patterns
        let mapped = ClipboardDetectionMapper.patterns(
            from: [unknown, ClipboardDetectionMapper.keyPath(for: .links)])
        #expect(mapped == [.links])
    }

    @available(macOS 15.4, *)
    @Test("metadata key paths cover every domain type")
    func metadataKeyPaths() {
        let keyPaths = ClipboardDetectionMapper.metadataKeyPaths(
            for: Set(ClipboardMetadataType.allCases))
        #expect(keyPaths.count == ClipboardMetadataType.allCases.count)
    }

    // MARK: - Against a real pasteboard

    @Test("detecting on an empty pasteboard reports no patterns")
    func detectOnEmptyPasteboard() async throws {
        try await withScratchPasteboard { repository, scope in
            guard #available(macOS 15.4, *) else { return }
            let found = try await repository.detectPatterns([.emailAddresses, .links], scope: scope)
            #expect(found.isEmpty)
        }
    }

    @Test("an email address is detected without reading the contents")
    func detectsEmailAddress() async throws {
        try await withScratchPasteboard { repository, scope in
            guard #available(macOS 15.4, *) else { return }
            _ = try repository.write(
                ClipboardContent(items: [ClipboardItemData(
                    representations: [self.text: Data("write to team@example.com today".utf8)])]),
                options: .default, scope: scope)

            let found = try await repository.detectPatterns([.emailAddresses], scope: scope)
            #expect(found.contains(.emailAddresses))
        }
    }

    @Test("detected values keep every field of the match")
    func detectedValuesKeepFields() async throws {
        try await withScratchPasteboard { repository, scope in
            guard #available(macOS 15.4, *) else { return }
            _ = try repository.write(
                ClipboardContent(items: [ClipboardItemData(
                    representations: [self.text: Data("mail team@example.com now".utf8)])]),
                options: .default, scope: scope)

            let values = try await repository.detectValues([.emailAddresses], scope: scope)

            // M-7: the match is kept as a structured value, not flattened to a string.
            let match = try #require(values.emailAddresses.first)
            #expect(match.emailAddress == "team@example.com")
            #expect(!match.matchedString.isEmpty)
            #expect(values.patterns.contains(.emailAddresses))
        }
    }

    @Test("a pattern that did not match leaves its field nil")
    func unmatchedPatternIsNil() async throws {
        try await withScratchPasteboard { repository, scope in
            guard #available(macOS 15.4, *) else { return }
            _ = try repository.write(
                ClipboardContent(items: [ClipboardItemData(
                    representations: [self.text: Data("plain words only".utf8)])]),
                options: .default, scope: scope)

            let values = try await repository.detectValues([.probableWebURL], scope: scope)

            // probableWebURL is a non-optional String on the system type, so without checking
            // `patterns` an empty string would read as a match.
            #expect(values.probableWebURL == nil)
            #expect(values.patterns.isEmpty)
        }
    }

    @Test("metadata reports the content type of a file reference")
    func detectsMetadataForFileReference() async throws {
        try await withScratchPasteboard { repository, scope in
            guard #available(macOS 15.4, *) else { return }
            // Measured on macOS 26.3: metadata detection answers for a file reference. The
            // header describes exactly this case.
            _ = try repository.write(
                ClipboardContent(items: [ClipboardItemData(
                    representations: ["public.file-url": Data("file:///tmp/a.txt".utf8)])]),
                options: .default, scope: scope)

            let metadata = try await repository.detectMetadata(scope: scope)
            #expect(metadata.contentTypeIdentifier != nil)
            #expect(metadata.metadataTypes.contains(.contentType))
        }
    }

    @Test("metadata detection on plain text fails rather than returning nothing")
    func metadataFailsForPlainText() async throws {
        try await withScratchPasteboard { repository, scope in
            guard #available(macOS 15.4, *) else { return }
            _ = try repository.write(
                ClipboardContent(items: [ClipboardItemData(
                    representations: [self.text: Data("hello".utf8)])]),
                options: .default, scope: scope)

            // Measured on macOS 26.3: the system reports NSCocoaErrorDomain 67587
            // "Pasteboard content detection failed" instead of empty metadata (RK-25). The
            // error is surfaced rather than reinterpreted, because the causes of that code are
            // not documented and guessing would swallow real failures.
            await #expect(throws: ClipboardError.self) {
                _ = try await repository.detectMetadata(scope: scope)
            }
        }
    }

    // MARK: - accessBehavior

    @Test("accessBehavior reports a value rather than throwing")
    func accessBehaviorReturnsValue() throws {
        let repository = makeRepository()
        let behavior = try repository.accessBehavior(scope: .general)
        #expect(ClipboardAccessBehavior.allCases.contains(behavior))
    }

    @Test("accessBehavior rejects an unresolvable scope even before 15.4")
    func accessBehaviorRejectsBadScope() {
        let repository = makeRepository()
        // The scope is resolved first, so the error does not depend on the OS version.
        #expect(throws: ClipboardError.invalidPasteboardName("")) {
            _ = try repository.accessBehavior(scope: .named(""))
        }
    }
}
