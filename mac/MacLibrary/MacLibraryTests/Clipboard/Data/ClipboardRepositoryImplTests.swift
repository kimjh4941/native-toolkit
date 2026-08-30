//
//  ClipboardRepositoryImplTests.swift
//  MacLibraryTests
//

import Testing
import AppKit
import Foundation
@testable import MacLibrary

/// Integration tests against a real `NSPasteboard`.
///
/// Every test uses a pasteboard it creates and releases itself. The general pasteboard is only
/// ever inspected, never written, so running the suite does not disturb the user's clipboard.
@Suite("ClipboardRepositoryImpl")
@MainActor
struct ClipboardRepositoryImplTests {

    private let text = "public.utf8-plain-text"
    private let rtf = "public.rtf"

    private func makeRepository() -> ClipboardRepositoryImpl {
        ClipboardRepositoryImpl(validator: ClipboardTypeIdentifierValidator())
    }

    /// Creates a scratch pasteboard and releases it once `body` returns.
    private func withScratchPasteboard(_ body: (ClipboardRepositoryImpl, PasteboardScope) throws -> Void) throws {
        let repository = makeRepository()
        let scope = try repository.createPasteboard(.unique)
        defer { try? repository.removePasteboard(scope) }
        try body(repository, scope)
    }

    private func content(_ representations: [String: Data]...) -> ClipboardContent {
        ClipboardContent(items: representations.map { ClipboardItemData(representations: $0) })
    }

    // MARK: - IT-01

    @Test("IT-01: a write round trips through a read")
    func writeReadRoundTrip() throws {
        try withScratchPasteboard { repository, scope in
            let source = content([text: Data("hello".utf8), "public.png": Data("png".utf8)])
            _ = try repository.write(source, options: .default, scope: scope)

            let result = try repository.read(scope: scope)
            #expect(ClipboardContent(items: result.items) == source)
        }
    }

    @Test("a read can report more representations than were written")
    func readReportsDerivedRepresentations() throws {
        try withScratchPasteboard { repository, scope in
            // Measured on macOS 26.3: writing public.rtf makes the pasteboard derive
            // public.utf8-plain-text and public.utf16-external-plain-text. A read is therefore
            // a superset of the write, and callers cannot assume byte-for-byte symmetry.
            _ = try repository.write(content([rtf: Data("{\\rtf1}".utf8)]), options: .default, scope: scope)

            let representations = try repository.read(scope: scope).items[0].representations
            #expect(representations[self.rtf] == Data("{\\rtf1}".utf8))
            #expect(representations.keys.contains(self.text))
            #expect(representations.count > 1)
        }
    }

    @Test("IT-01: readData returns the bytes for one type")
    func readDataReturnsBytes() throws {
        try withScratchPasteboard { repository, scope in
            _ = try repository.write(content([text: Data("hello".utf8)]), options: .default, scope: scope)
            #expect(try repository.readData(utType: text, scope: scope) == Data("hello".utf8))
        }
    }

    @Test("readData reports a missing type as nil rather than an error")
    func readDataMissingTypeIsNil() throws {
        try withScratchPasteboard { repository, scope in
            _ = try repository.write(content([text: Data("hello".utf8)]), options: .default, scope: scope)
            #expect(try repository.readData(utType: rtf, scope: scope) == nil)
        }
    }

    // MARK: - IT-02 / IT-03

    @Test("IT-02: append adds items and leaves the change count untouched")
    func appendAddsItems() throws {
        try withScratchPasteboard { repository, scope in
            let ownership = try repository.write(content([text: Data("first".utf8)]),
                                                 options: .default, scope: scope)

            let after = try repository.append(content([text: Data("second".utf8)]), ownership: ownership)

            #expect(after == ownership)
            let result = try repository.read(scope: scope)
            #expect(result.items.count == 2)
            #expect(result.changeCount == ownership.changeCount)
        }
    }

    @Test("IT-02: repeated appends keep accumulating")
    func repeatedAppends() throws {
        try withScratchPasteboard { repository, scope in
            var ownership = try repository.write(content([text: Data("1".utf8)]),
                                                 options: .default, scope: scope)
            for value in ["2", "3"] {
                ownership = try repository.append(content([text: Data(value.utf8)]), ownership: ownership)
            }
            #expect(try repository.read(scope: scope).items.count == 3)
        }
    }

    @Test("IT-03: append after another owner takes over reports lost ownership")
    func appendAfterOwnershipLost() throws {
        try withScratchPasteboard { repository, scope in
            let ownership = try repository.write(content([text: Data("mine".utf8)]),
                                                 options: .default, scope: scope)

            // Stand in for another process taking the pasteboard: any new owner advances the
            // change count, which is exactly what the guard reads.
            let stolen = try PasteboardResolver.resolve(scope).clearContents()
            #expect(stolen != ownership.changeCount)

            #expect(throws: ClipboardError.ownershipLost(expected: ownership.changeCount, actual: stolen)) {
                _ = try repository.append(content([text: Data("theirs".utf8)]), ownership: ownership)
            }
            // The rejected append must not have written anything.
            #expect(try repository.read(scope: scope).items.isEmpty)
        }
    }

    // MARK: - IT-04

    @Test("IT-04: a write advances the change count exactly once")
    func writeTakesOwnershipOnce() throws {
        try withScratchPasteboard { repository, scope in
            let before = try repository.changeCount(scope: scope)

            let ownership = try repository.write(content([text: Data("value".utf8)]),
                                                 options: .default, scope: scope)

            // clearContents() and prepareForNewContents(with:) each advance the count, so a copy
            // that routed through both would advance it by two. One step is the observable proof
            // that ownership is taken by a single call (RK-05).
            #expect(ownership.changeCount == before + 1)
            #expect(try repository.changeCount(scope: scope) == before + 1)
        }
    }

    @Test("a rejected write leaves the pasteboard untouched")
    func rejectedWriteLeavesContentsIntact() throws {
        try withScratchPasteboard { repository, scope in
            let ownership = try repository.write(content([text: Data("kept".utf8)]),
                                                 options: .default, scope: scope)

            #expect(throws: ClipboardError.invalidTypeIdentifier("not a uti")) {
                _ = try repository.write(self.content(["not a uti": Data("x".utf8)]),
                                         options: .default, scope: scope)
            }
            // Ownership is taken only after the items are built, so the earlier contents survive.
            let result = try repository.read(scope: scope)
            #expect(result.items.count == 1)
            #expect(result.changeCount == ownership.changeCount)
        }
    }

    // MARK: - IT-05

    @Test("IT-05: writing the same content twice does not throw")
    func repeatedIdenticalWrites() throws {
        try withScratchPasteboard { repository, scope in
            let source = content([text: Data("same".utf8)])
            // A pasteboard item cannot be written twice, so a mapper that cached items would
            // fail here on the second call (RK-14).
            let first = try repository.write(source, options: .default, scope: scope)
            let second = try repository.write(source, options: .default, scope: scope)

            #expect(second.changeCount == first.changeCount + 1)
            #expect(try repository.read(scope: scope).items.count == 1)
        }
    }

    // MARK: - IT-07

    @Test("IT-07: multiple items keep their count and order")
    func multipleItemsArePreserved() throws {
        try withScratchPasteboard { repository, scope in
            let source = content([text: Data("one".utf8)],
                                 [text: Data("two".utf8)],
                                 [text: Data("three".utf8)])
            _ = try repository.write(source, options: .default, scope: scope)

            let result = try repository.read(scope: scope)
            #expect(result.items.count == 3)
            #expect(result.items.map { $0.representations[self.text] }
                    == [Data("one".utf8), Data("two".utf8), Data("three".utf8)])
        }
    }

    // MARK: - IT-08

    @Test("IT-08: an unfiltered snapshot reports every item")
    func snapshotUnfiltered() throws {
        try withScratchPasteboard { repository, scope in
            _ = try repository.write(content([text: Data("a".utf8)], ["public.png": Data("b".utf8)]),
                                     options: .default, scope: scope)

            let snapshot = try repository.snapshot(matchingTypes: nil, scope: scope)
            #expect(snapshot.itemTypes.count == 2)
            #expect(snapshot.matchingItemIndexes == [0, 1])
        }
    }

    @Test("IT-08: a filter matches by conformance, not equality")
    func snapshotMatchesByConformance() throws {
        try withScratchPasteboard { repository, scope in
            // public.png is used for the non-matching item because public.rtf conforms to
            // public.text, and the pasteboard also derives plain text from it.
            _ = try repository.write(content([text: Data("a".utf8)], ["public.png": Data("b".utf8)]),
                                     options: .default, scope: scope)

            // public.utf8-plain-text conforms to public.text but is not equal to it, so a
            // filter of public.text selects it only if matching is by conformance.
            let snapshot = try repository.snapshot(matchingTypes: ["public.text"], scope: scope)
            #expect(snapshot.matchingItemIndexes == [0])
            // The full type list is reported regardless of the filter.
            #expect(snapshot.itemTypes.count == 2)
        }
    }

    @Test("IT-08: a filter that matches nothing yields no indexes")
    func snapshotMatchesNothing() throws {
        try withScratchPasteboard { repository, scope in
            _ = try repository.write(content([text: Data("a".utf8)]), options: .default, scope: scope)
            let snapshot = try repository.snapshot(matchingTypes: ["public.image"], scope: scope)
            #expect(snapshot.matchingItemIndexes.isEmpty)
            #expect(snapshot.itemTypes.count == 1)
        }
    }

    @Test("an empty filter is rejected")
    func snapshotRejectsEmptyFilter() throws {
        try withScratchPasteboard { repository, scope in
            #expect(throws: ClipboardError.emptyTypeFilter) {
                _ = try repository.snapshot(matchingTypes: [], scope: scope)
            }
        }
    }

    @Test("a snapshot filter can name an app's own undeclared type")
    func snapshotMatchesUndeclaredType() throws {
        try withScratchPasteboard { repository, scope in
            let custom = "com.mycompany.myformat"
            _ = try repository.write(content([custom: Data("a".utf8)], [text: Data("b".utf8)]),
                                     options: .default, scope: scope)

            let snapshot = try repository.snapshot(matchingTypes: [custom], scope: scope)
            #expect(snapshot.matchingItemIndexes == [0])
        }
    }

    // MARK: - Clear

    @Test("clear empties the pasteboard and reports the new change count")
    func clearEmptiesPasteboard() throws {
        try withScratchPasteboard { repository, scope in
            let ownership = try repository.write(content([text: Data("value".utf8)]),
                                                 options: .default, scope: scope)

            let after = try repository.clear(scope: scope)
            #expect(after == ownership.changeCount + 1)
            #expect(try repository.read(scope: scope).items.isEmpty)
        }
    }

    // MARK: - IT-06 (T-05)

    @Test("IT-06: releasing the general pasteboard is refused")
    func refusesToReleaseGeneral() {
        let repository = makeRepository()
        #expect(throws: ClipboardError.cannotReleaseStandardPasteboard(name: "general")) {
            try repository.removePasteboard(.general)
        }
    }

    @Test("IT-06: releasing any standard pasteboard by name is refused")
    func refusesToReleaseStandardNames() {
        let repository = makeRepository()
        for name in [NSPasteboard.Name.general, .font, .ruler, .find, .drag] {
            // A caller can reach a standard pasteboard through .named, so the case of the scope
            // is not enough to decide (RK-07).
            #expect(throws: ClipboardError.cannotReleaseStandardPasteboard(name: name.rawValue)) {
                try repository.removePasteboard(.named(name.rawValue))
            }
        }
    }

    @Test("a unique pasteboard can be created and released")
    func createsAndReleasesUniquePasteboard() throws {
        let repository = makeRepository()
        let scope = try repository.createPasteboard(.unique)
        guard case .unique(let name) = scope else {
            Issue.record("expected a unique scope, got \(scope)")
            return
        }
        #expect(!name.isEmpty)
        try repository.removePasteboard(scope)
    }

    @Test("a named pasteboard reports the requested name")
    func createsNamedPasteboard() throws {
        let repository = makeRepository()
        let name = "com.nativetoolkit.tests.repo.\(UUID().uuidString)"
        let scope = try repository.createPasteboard(.named(name))
        #expect(scope == .named(name))
        try repository.removePasteboard(scope)
    }

    @Test("an empty pasteboard name is rejected")
    func rejectsEmptyName() {
        let repository = makeRepository()
        #expect(throws: ClipboardError.invalidPasteboardName("")) {
            _ = try repository.createPasteboard(.named(""))
        }
    }

    // MARK: - Not yet implemented

    @Test("operations still to be built report which task delivers them")
    func unimplementedOperationsAreExplicit() throws {
        // These conform to the port so that any signature drift is a compile error now, rather
        // than a surprise when the owning task starts.
        let repository = makeRepository()
        #expect(throws: ClipboardError.self) {
            try repository.startReceivingFilePromises(handle: FilePromiseReceiptHandle(),
                                                      destinationDirectory: URL(filePath: "/tmp"),
                                                      scope: .general)
        }
    }
}
