//
//  FilePromiseUseCaseTests.swift
//  MacLibraryTests
//

import Testing
import Foundation
@testable import MacLibrary

@Suite("File promise use cases")
@MainActor
struct FilePromiseUseCaseTests {

    private func makeContext() -> (MockClipboardRepository,
                                   MockClipboardPromiseRegistry,
                                   MockFilePromiseSnapshotter,
                                   MockClipboardTypeIdentifierValidating) {
        (MockClipboardRepository(), MockClipboardPromiseRegistry(),
         MockFilePromiseSnapshotter(), MockClipboardTypeIdentifierValidating())
    }

    private func makeProvide(_ context: (MockClipboardRepository,
                                         MockClipboardPromiseRegistry,
                                         MockFilePromiseSnapshotter,
                                         MockClipboardTypeIdentifierValidating))
    -> ProvideFilePromiseUseCase {
        ProvideFilePromiseUseCase(repository: context.0, registry: context.1,
                                  snapshotter: context.2, typeValidator: context.3)
    }

    private func writerRequest(fileName: String = "note.txt",
                               fileType: String = "public.plain-text") -> FilePromiseRequest {
        FilePromiseRequest(fileTypeIdentifier: fileType, fileName: fileName,
                           source: .writer { _ in })
    }

    private func snapshotRequest(fileName: String = "note.txt") -> FilePromiseRequest {
        FilePromiseRequest(fileTypeIdentifier: "public.plain-text", fileName: fileName,
                           source: .snapshot(URL(filePath: "/tmp/source.txt")))
    }

    // MARK: - OP-16 validation

    @Test("a file type that is not data or directory is rejected")
    func rejectsInvalidFileType() async throws {
        let context = makeContext()
        context.3.invalidFileTypeIdentifiers = ["public.item"]
        let useCase = makeProvide(context)

        await #expect(throws: ClipboardError.filePromiseTypeInvalid("public.item")) {
            _ = try await useCase(self.writerRequest(fileType: "public.item"), scope: .general)
        }
        // Validation runs before anything is reserved, so no handle leaks.
        #expect(context.1.reserveFilePromiseHandleCallCount == 0)
    }

    @Test("an unusable file name is rejected", arguments: [
        "", "/", "a/b", ".", "..", String(repeating: "a", count: 256),
    ])
    func rejectsInvalidFileName(fileName: String) async throws {
        let context = makeContext()
        let useCase = makeProvide(context)

        await #expect(throws: ClipboardError.invalidFileName(fileName)) {
            _ = try await useCase(self.writerRequest(fileName: fileName), scope: .general)
        }
        #expect(context.1.reserveFilePromiseHandleCallCount == 0)
    }

    @Test("a name of exactly 255 bytes is accepted")
    func acceptsNameAtLimit() async throws {
        let context = makeContext()
        let useCase = makeProvide(context)
        _ = try await useCase(writerRequest(fileName: String(repeating: "a", count: 255)),
                              scope: .general)
        #expect(context.1.registerFilePromiseCallCount == 1)
    }

    @Test("the name limit counts UTF-8 bytes, not characters")
    func nameLimitCountsBytes() async throws {
        let context = makeContext()
        let useCase = makeProvide(context)
        // 86 three-byte characters are 258 bytes, well under 255 characters. The file system
        // counts bytes, so this has to be rejected.
        let name = String(repeating: "あ", count: 86)
        #expect(name.count == 86 && name.utf8.count == 258)

        await #expect(throws: ClipboardError.invalidFileName(name)) {
            _ = try await useCase(self.writerRequest(fileName: name), scope: .general)
        }
    }

    // MARK: - OP-16 transaction

    @Test("a writer request registers and writes without snapshotting")
    func writerSkipsSnapshot() async throws {
        let context = makeContext()
        let useCase = makeProvide(context)

        _ = try await useCase(writerRequest(), scope: .general)

        #expect(context.2.snapshotCallCount == 0)
        #expect(context.1.lastStagingURL == .some(nil))
        #expect(context.1.callOrder == ["reserveFilePromiseHandle", "registerFilePromise",
                                        "activateFilePromise"])
    }

    @Test("a snapshot request copies before registering")
    func snapshotBeforeRegister() async throws {
        let context = makeContext()
        let useCase = makeProvide(context)

        _ = try await useCase(snapshotRequest(), scope: .general)

        #expect(context.2.snapshotCallCount == 1)
        #expect(context.2.lastSource == URL(filePath: "/tmp/source.txt"))
        #expect(context.2.lastStagingRoot == context.1.stubbedStagingRoot)
        // The copy has to be complete before the promise is registered, otherwise a fulfilment
        // could arrive while the staging directory is half written.
        #expect(context.1.callOrder == ["reserveFilePromiseHandle", "stagingRoot",
                                        "registerFilePromise", "activateFilePromise"])
    }

    @Test("ownership is recorded only after a successful write")
    func activatesWithOwnership() async throws {
        let context = makeContext()
        context.0.stubbedOwnership = PasteboardOwnership(scope: .general, changeCount: 42)
        let useCase = makeProvide(context)

        _ = try await useCase(writerRequest(), scope: .general)

        #expect(context.1.activateFilePromiseCallCount == 1)
        #expect(context.1.lastOwnership?.changeCount == 42)
    }

    @Test("a failed pasteboard write rolls the registration back")
    func rollsBackFailedWrite() async throws {
        let context = makeContext()
        context.0.shouldFail = .writeRejected
        let useCase = makeProvide(context)

        await #expect(throws: ClipboardError.writeRejected) {
            _ = try await useCase(self.writerRequest(), scope: .general)
        }
        // Without the release the promise would stay registered and its staging directory
        // would never be deleted (R2-M12).
        #expect(context.1.releaseFilePromiseCallCount == 1)
        #expect(context.1.activateFilePromiseCallCount == 0)
    }

    @Test("a failed snapshot registers nothing")
    func failedSnapshotRegistersNothing() async throws {
        let context = makeContext()
        context.2.shouldFail = .filePromiseWriteFailed("disk full")
        let useCase = makeProvide(context)

        await #expect(throws: ClipboardError.filePromiseWriteFailed("disk full")) {
            _ = try await useCase(self.snapshotRequest(), scope: .general)
        }
        #expect(context.1.registerFilePromiseCallCount == 0)
        #expect(context.1.releaseFilePromiseCallCount == 0)
        #expect(context.0.writeFilePromiseCallCount == 0)
    }

    @Test("a cancellation after the copy finished discards the staging directory")
    func discardsStagingOnLateCancellation() async throws {
        let context = makeContext()
        let useCase = makeProvide(context)

        let task = Task { @MainActor in
            try await useCase(self.snapshotRequest(), scope: .general)
        }
        // Cancel from inside the snapshot, so the copy completes into a cancelled task. This is
        // the window where a completed staging directory would otherwise be orphaned (R5-M6).
        context.2.onSnapshot = { task.cancel() }

        await #expect(throws: CancellationError.self) { try await task.value }
        #expect(context.2.discardCallCount == 1)
        #expect(context.1.registerFilePromiseCallCount == 0)
    }

    // MARK: - OP-17

    @Test("releasing is idempotent and never throws")
    func releaseIsIdempotent() {
        let context = makeContext()
        let useCase = ReleaseFilePromiseUseCase(registry: context.1)
        let handle = FilePromiseHandle()

        useCase(handle)
        useCase(handle)

        #expect(context.1.releaseFilePromiseCallCount == 2)
        #expect(context.1.releasedHandles == [handle, handle])
    }

    // MARK: - OP-18

    @Test("starting a session reserves, registers and starts in that order")
    func startOrder() throws {
        let context = makeContext()
        let useCase = ReceiveFilePromisesUseCase(repository: context.0, registry: context.1)

        _ = try useCase(destinationDirectory: URL(filePath: "/tmp/dest"),
                        scope: .general, policy: .default, onEvent: { _ in })

        #expect(context.1.callOrder == ["reserveReceiptHandle", "registerReceipt"])
        #expect(context.1.lastPolicy == FilePromiseReceiptPolicy.default)
    }

    @Test("a failed start rolls back without delivering an event")
    func failedStartIsSilent() throws {
        let context = makeContext()
        context.0.shouldFail = .destinationNotWritable("/tmp/dest")
        let useCase = ReceiveFilePromisesUseCase(repository: context.0, registry: context.1)

        var events: [FilePromiseReceiptEvent] = []
        #expect(throws: ClipboardError.destinationNotWritable("/tmp/dest")) {
            _ = try useCase(destinationDirectory: URL(filePath: "/tmp/dest"),
                            scope: .general, policy: .default, onEvent: { events.append($0) })
        }
        // A session that never began must produce no event at all, so the rollback path is
        // separate from the public cancel path (R5-H4).
        #expect(events.isEmpty)
        #expect(context.1.discardReceiptAfterStartFailureCallCount == 1)
        #expect(context.1.cancelReceiptCallCount == 0)
    }

    // MARK: - OP-20

    @Test("cancelling is idempotent and never throws")
    func cancelIsIdempotent() {
        let context = makeContext()
        let useCase = CancelReceiveFilePromisesUseCase(registry: context.1)
        let handle = FilePromiseReceiptHandle()

        useCase(handle)
        useCase(handle)

        #expect(context.1.cancelReceiptCallCount == 2)
        #expect(context.1.cancelledReceipts == [handle, handle])
    }

    @Test("cancelling an unknown session is a no-op rather than an error")
    func cancelUnknownHandle() {
        let context = makeContext()
        let useCase = CancelReceiveFilePromisesUseCase(registry: context.1)
        useCase(FilePromiseReceiptHandle())
        #expect(context.1.cancelReceiptCallCount == 1)
    }
}
