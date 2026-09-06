//
//  SynchronousUseCaseTests.swift
//  MacLibraryTests
//

import Testing
import Foundation
@testable import MacLibrary

/// Covers the eight synchronous use cases (OP-01 to OP-08).
///
/// Each one is a thin layer over the repository, so the tests assert three things: the port is
/// reached exactly once with the arguments it was given, the result comes back unchanged, and
/// a repository error propagates rather than being translated.
@Suite("Synchronous use cases")
@MainActor
struct SynchronousUseCaseTests {

    private let text = "public.utf8-plain-text"

    private func makeContext() throws -> (MockClipboardRepository, ClipboardContentValidator) {
        let repository = MockClipboardRepository()
        let validator = ClipboardContentValidator(limits: .default,
                                                  typeValidator: MockClipboardTypeIdentifierValidating())
        return (repository, validator)
    }

    private func sample() -> ClipboardContent {
        ClipboardContent(items: [ClipboardItemData(representations: [text: Data("v".utf8)])])
    }

    // MARK: - OP-01 copy

    @Test("copy validates, writes once and returns the ownership")
    func copyWrites() throws {
        let (repository, validator) = try makeContext()
        repository.stubbedOwnership = PasteboardOwnership(scope: .named("target"), changeCount: 9)
        let useCase = CopyContentUseCase(repository: repository,
                                         registry: MockClipboardPromiseRegistry(),
                                         validator: validator)

        let ownership = try useCase(sample(), options: .default, scope: .named("target"))

        #expect(repository.writeCallCount == 1)
        #expect(repository.lastContent == sample())
        #expect(repository.lastOptions == ClipboardCopyOptions.default)
        #expect(repository.lastScope == .named("target"))
        #expect(ownership.changeCount == 9)
    }

    @Test("copy rejects invalid content before touching the pasteboard")
    func copyValidatesFirst() throws {
        let (repository, _) = try makeContext()
        let validator = ClipboardContentValidator(limits: .default,
                                                  typeValidator: MockClipboardTypeIdentifierValidating())
        let useCase = CopyContentUseCase(repository: repository,
                                         registry: MockClipboardPromiseRegistry(),
                                         validator: validator)

        #expect(throws: ClipboardError.emptyContent) {
            _ = try useCase(ClipboardContent(items: []), options: .default, scope: .general)
        }
        // Validation happening after the write would leave the pasteboard emptied.
        #expect(repository.writeCallCount == 0)
    }

    @Test("copy passes a repository error through unchanged")
    func copyPropagatesError() throws {
        let (repository, validator) = try makeContext()
        repository.shouldFail = .writeRejected
        let useCase = CopyContentUseCase(repository: repository,
                                         registry: MockClipboardPromiseRegistry(),
                                         validator: validator)

        #expect(throws: ClipboardError.writeRejected) {
            _ = try useCase(self.sample(), options: .default, scope: .general)
        }
    }

    // MARK: - OP-02 append

    @Test("append forwards the ownership token")
    func appendForwardsOwnership() throws {
        let (repository, validator) = try makeContext()
        let ownership = PasteboardOwnership(scope: .named("target"), changeCount: 4)
        let useCase = AppendContentUseCase(repository: repository, validator: validator)

        _ = try useCase(sample(), ownership: ownership)

        #expect(repository.appendCallCount == 1)
        #expect(repository.lastOwnership == ownership)
    }

    @Test("append validates before appending")
    func appendValidatesFirst() throws {
        let (repository, validator) = try makeContext()
        let useCase = AppendContentUseCase(repository: repository, validator: validator)

        #expect(throws: ClipboardError.emptyContent) {
            _ = try useCase(ClipboardContent(items: []),
                            ownership: PasteboardOwnership(scope: .general, changeCount: 1))
        }
        #expect(repository.appendCallCount == 0)
    }

    @Test("append reports lost ownership unchanged")
    func appendPropagatesOwnershipLost() throws {
        let (repository, validator) = try makeContext()
        repository.shouldFail = .ownershipLost(expected: 1, actual: 2)
        let useCase = AppendContentUseCase(repository: repository, validator: validator)

        #expect(throws: ClipboardError.ownershipLost(expected: 1, actual: 2)) {
            _ = try useCase(self.sample(),
                            ownership: PasteboardOwnership(scope: .general, changeCount: 1))
        }
    }

    @Test("append reports a refused write unchanged")
    func appendPropagatesAppendRejected() throws {
        // The sibling of ownershipLost: ownership still matches, but `writeObjects` refuses.
        // Only this one had no test outside the error value's own, so 1510 was the single
        // error the product can return that nothing had ever driven (R-SA28).
        let (repository, validator) = try makeContext()
        repository.shouldFail = .appendRejected
        let useCase = AppendContentUseCase(repository: repository, validator: validator)

        #expect(throws: ClipboardError.appendRejected) {
            _ = try useCase(self.sample(),
                            ownership: PasteboardOwnership(scope: .general, changeCount: 1))
        }
    }

    // MARK: - OP-03 read

    @Test("read returns the repository result")
    func readReturnsItems() throws {
        let (repository, _) = try makeContext()
        repository.stubbedReadResult = ClipboardReadResult(
            items: [ClipboardItemData(representations: [text: Data("v".utf8)])], changeCount: 3)
        let useCase = ReadContentUseCase(repository: repository)

        let result = try useCase(scope: .general)

        #expect(repository.readCallCount == 1)
        #expect(result.items.count == 1)
        #expect(result.changeCount == 3)
    }

    @Test("read of an empty pasteboard is not an error")
    func readEmptyIsNotAnError() throws {
        let (repository, _) = try makeContext()
        let useCase = ReadContentUseCase(repository: repository)
        #expect(try useCase(scope: .general).items.isEmpty)
    }

    @Test("read propagates an unavailable pasteboard")
    func readPropagatesUnavailable() throws {
        let (repository, _) = try makeContext()
        repository.shouldFail = .pasteboardUnavailable(name: "gone")
        let useCase = ReadContentUseCase(repository: repository)

        #expect(throws: ClipboardError.pasteboardUnavailable(name: "gone")) {
            _ = try useCase(scope: .general)
        }
    }

    // MARK: - OP-04 readData

    @Test("readData forwards the type and returns the bytes")
    func readDataReturnsBytes() throws {
        let (repository, _) = try makeContext()
        repository.stubbedData = Data("bytes".utf8)
        let useCase = ReadDataUseCase(repository: repository)

        #expect(try useCase(utType: text, scope: .general) == Data("bytes".utf8))
        #expect(repository.lastUTType == text)
    }

    @Test("readData reports a missing type as nil rather than throwing")
    func readDataMissingIsNil() throws {
        let (repository, _) = try makeContext()
        repository.stubbedData = nil
        let useCase = ReadDataUseCase(repository: repository)
        // M-1: absence is an ordinary outcome, so the caller does not need a catch block.
        #expect(try useCase(utType: text, scope: .general) == nil)
    }

    // MARK: - OP-05 snapshot

    @Test("snapshot forwards a nil filter unchanged")
    func snapshotForwardsNilFilter() throws {
        let (repository, _) = try makeContext()
        let useCase = GetSnapshotUseCase(repository: repository)

        _ = try useCase(matchingTypes: nil, scope: .general)

        // A nil filter and an absent call are different things, so the mock records the
        // optional itself.
        #expect(repository.snapshotCallCount == 1)
        #expect(repository.lastMatchingTypes == .some(nil))
    }

    @Test("snapshot forwards a filter unchanged")
    func snapshotForwardsFilter() throws {
        let (repository, _) = try makeContext()
        let useCase = GetSnapshotUseCase(repository: repository)

        _ = try useCase(matchingTypes: ["public.text"], scope: .general)

        #expect(repository.lastMatchingTypes == .some(["public.text"]))
    }

    @Test("snapshot propagates an empty filter rejection")
    func snapshotPropagatesEmptyFilter() throws {
        let (repository, _) = try makeContext()
        repository.shouldFail = .emptyTypeFilter
        let useCase = GetSnapshotUseCase(repository: repository)

        #expect(throws: ClipboardError.emptyTypeFilter) {
            _ = try useCase(matchingTypes: [], scope: .general)
        }
    }

    // MARK: - OP-06 clear

    @Test("clear returns the new change count")
    func clearReturnsChangeCount() throws {
        let (repository, _) = try makeContext()
        repository.stubbedClearChangeCount = 12
        let useCase = ClearClipboardUseCase(repository: repository)

        #expect(try useCase(scope: .general) == 12)
        #expect(repository.clearCallCount == 1)
    }

    // MARK: - OP-07 createPasteboard

    @Test("createPasteboard returns the scope naming the pasteboard")
    func createReturnsScope() throws {
        let (repository, _) = try makeContext()
        repository.stubbedScope = .unique("com.apple.pasteboard.12345")
        let useCase = CreatePasteboardUseCase(repository: repository)

        let scope = try useCase(.unique)

        #expect(scope == .unique("com.apple.pasteboard.12345"))
        #expect(repository.lastRequest == .unique)
    }

    @Test("createPasteboard propagates an invalid name")
    func createPropagatesInvalidName() throws {
        let (repository, _) = try makeContext()
        repository.shouldFail = .invalidPasteboardName("")
        let useCase = CreatePasteboardUseCase(repository: repository)

        #expect(throws: ClipboardError.invalidPasteboardName("")) {
            _ = try useCase(.named(""))
        }
    }

    // MARK: - OP-08 removePasteboard

    @Test("removePasteboard forwards the scope")
    func removeForwardsScope() throws {
        let (repository, _) = try makeContext()
        let useCase = RemovePasteboardUseCase(repository: repository)

        try useCase(.unique("com.apple.pasteboard.12345"))

        #expect(repository.removePasteboardCallCount == 1)
        #expect(repository.lastRemovedScope == .unique("com.apple.pasteboard.12345"))
    }

    @Test("removePasteboard propagates the standard pasteboard refusal")
    func removePropagatesRefusal() throws {
        let (repository, _) = try makeContext()
        repository.shouldFail = .cannotReleaseStandardPasteboard(name: "general")
        let useCase = RemovePasteboardUseCase(repository: repository)

        #expect(throws: ClipboardError.cannotReleaseStandardPasteboard(name: "general")) {
            try useCase(.general)
        }
    }
}
