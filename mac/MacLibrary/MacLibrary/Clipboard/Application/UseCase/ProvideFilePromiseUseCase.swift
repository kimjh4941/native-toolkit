//
//  ProvideFilePromiseUseCase.swift
//  MacLibrary
//

import Foundation

/// OP-16. Registers a promised file and advertises it on a pasteboard.
///
/// This type is the only executor of the promise transaction. The coordinator cannot run it
/// because it does not hold the repository, and splitting the steps across layers is what
/// previously allowed a registration to survive a failed pasteboard write (R6-H2).
@MainActor
public struct ProvideFilePromiseUseCase {

    private let TAG = "ProvideFilePromiseUseCase"

    /// Longest permitted file name. `NAME_MAX` on macOS is 255 bytes, and the name is measured
    /// in UTF-8 bytes rather than characters because that is what the file system counts.
    private static let maxFileNameBytes = 255

    private let repository: any ClipboardRepository
    private let registry: any ClipboardPromiseRegistry
    private let snapshotter: any FilePromiseSnapshotting
    private let typeValidator: any ClipboardTypeIdentifierValidating

    /// Creates the use case with the ports it needs. Dependencies are injected so a test can substitute mocks.
    public init(repository: any ClipboardRepository,
                registry: any ClipboardPromiseRegistry,
                snapshotter: any FilePromiseSnapshotting,
                typeValidator: any ClipboardTypeIdentifierValidating) {
        self.repository = repository
        self.registry = registry
        self.snapshotter = snapshotter
        self.typeValidator = typeValidator
    }

    /// - Returns: The handle identifying the registration, for use with
    ///   ``ReleaseFilePromiseUseCase``.
    /// - Throws: ``ClipboardError/filePromiseTypeInvalid(_:)``,
    ///   ``ClipboardError/invalidFileName(_:)``, `CancellationError`, or whatever the
    ///   pasteboard write reports. On any failure nothing is left registered and no staging
    ///   directory survives.
    public func callAsFunction(_ request: FilePromiseRequest,
                               scope: PasteboardScope) async throws -> FilePromiseHandle {
        Log.d(TAG, "[callAsFunction] fileType: \(request.fileTypeIdentifier), "
              + "fileName: \(ClipboardLog.path(request.fileName)), scope: \(ClipboardLog.scope(scope))")
        try validate(request)

        // 1. Reserve without registering, so the staging path can be derived from the handle.
        let handle = registry.reserveFilePromiseHandle()

        // 2. Copy off the main actor. A recursive directory copy has no size bound, so doing it
        //    inline would block the main actor for an unbounded time (R4-H3).
        var stagingURL: URL?
        if case .snapshot(let source) = request.source {
            try Task.checkCancellation()
            let root = registry.stagingRoot(for: handle)
            let staged = try await snapshotter.snapshot(from: source, into: root)
            do {
                // The copy can finish after the task was cancelled. Nothing is registered yet,
                // so the completed staging would otherwise be orphaned (R5-M6).
                try Task.checkCancellation()
            } catch {
                await snapshotter.discard(stagingURL: staged)
                throw error
            }
            stagingURL = staged
        }

        // 3. Register provisionally. Stale monitoring does not start yet: there is no
        //    pasteboard ownership to compare against until step 4 succeeds.
        _ = registry.registerFilePromise(request, reserved: handle, stagingURL: stagingURL)

        // 4. Write, then activate. A failure here rolls the registration back, which also
        //    deletes the staging directory (R2-M12).
        do {
            let ownership = try repository.writeFilePromise(handle: handle, scope: scope)
            registry.activateFilePromise(handle, ownership: ownership)
        } catch {
            registry.releaseFilePromise(handle)
            throw error
        }
        return handle
    }

    private func validate(_ request: FilePromiseRequest) throws {
        Log.d(TAG, "[validate] fileType: \(request.fileTypeIdentifier), "
              + "fileName: \(ClipboardLog.path(request.fileName))")
        guard typeValidator.isValidFileType(request.fileTypeIdentifier) else {
            throw ClipboardError.filePromiseTypeInvalid(request.fileTypeIdentifier)
        }
        let name = request.fileName
        // A name with a separator or a relative component would let the promise write outside
        // the destination the receiving app chose.
        guard !name.isEmpty,
              !name.contains("/"),
              name != ".", name != "..",
              name.utf8.count <= Self.maxFileNameBytes else {
            throw ClipboardError.invalidFileName(name)
        }
    }
}
