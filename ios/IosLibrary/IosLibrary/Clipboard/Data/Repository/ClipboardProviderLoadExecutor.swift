//
//  ClipboardProviderLoadExecutor.swift
//  IosLibrary
//

import Foundation
import UIKit
import UniformTypeIdentifiers

/// A cancellable, exactly-once load of a single `ClipboardLoadRequest` from a single
/// `NSItemProvider`.
///
/// `finish` is the sole delivery gate: whichever of {provider completion, timeout, cancellation}
/// reaches it first wins; everything afterward is discarded, and any temporary file produced by a
/// losing/failed path is removed.
@MainActor
final class ClipboardProviderLoadHandle {
    private let TAG = "ClipboardProviderLoadHandle"
    private var completion: ((Result<ClipboardLoadedItem, ClipboardError>) -> Void)?
    private let fileStore: ClipboardTemporaryFileStore
    fileprivate var progress: Progress?
    fileprivate var timeoutTask: Task<Void, Never>?

    fileprivate init(
        fileStore: ClipboardTemporaryFileStore,
        completion: @escaping (Result<ClipboardLoadedItem, ClipboardError>) -> Void
    ) {
        self.fileStore = fileStore
        self.completion = completion
    }

    /// Cancels the load. Delivers `.cancelled` exactly once if it has not already been resolved.
    func cancel() {
        Log.d(TAG, "[cancel] isPending: \(completion != nil)")
        finish(.failure(.cancelled), tempFileURL: nil)
    }

    fileprivate func finish(
        _ outcome: Result<ClipboardLoadedItem, ClipboardError>,
        tempFileURL: URL?
    ) {
        guard let completion else {
            // Already resolved: discard the late result, including any file it produced.
            if let tempFileURL { fileStore.discard(tempFileURL) }
            return
        }
        self.completion = nil
        timeoutTask?.cancel()
        timeoutTask = nil
        // Best-effort: the system does not guarantee this suppresses the provider's completion.
        progress?.cancel()
        progress = nil
        if case .failure = outcome, let tempFileURL {
            fileStore.discard(tempFileURL)
        }
        completion(outcome)
    }
}

/// Loads one request from one `NSItemProvider`, enforcing `ClipboardLimits` and
/// `ClipboardTimeouts.providerLoad`, and delivering the result exactly once on the main actor.
///
/// Shared by `ClipboardItemLoaderImpl` (P-11, pasteboard-driven) and `PasteItemProviderLoader`
/// (S11, `UIPasteControl`-driven) so both paths get identical exactly-once, timeout,
/// cancellation, size-limit, and temporary-file cleanup semantics.
@MainActor
final class ClipboardProviderLoadExecutor {
    /// Sentinel `ClipboardFailureDetail` values for failures this executor originates itself, as
    /// opposed to normalized system errors. Test-visible so a regression in *which* boundary
    /// rejected a load is caught rather than passing on the error code alone.
    enum FailureDetailCode {
        static let domain = "ClipboardProviderLoadExecutor"
        /// The copied file's size could not be read, so the limit could not be enforced.
        static let copiedSizeUnverifiable = -2
        /// The source file's size could not be read, so the copy was never started.
        static let sourceSizeUnverifiable = -3
    }

    private let TAG = "ClipboardProviderLoadExecutor"
    private static let staticTAG = "ClipboardProviderLoadExecutor"
    private let fileStore: ClipboardTemporaryFileStore
    private let imageCoder: ClipboardImageCoder
    private let limits: ClipboardLimits
    private let timeouts: ClipboardTimeouts

    init(
        fileStore: ClipboardTemporaryFileStore? = nil,
        imageCoder: ClipboardImageCoder? = nil,
        limits: ClipboardLimits = .default,
        timeouts: ClipboardTimeouts = .default
    ) {
        self.fileStore = fileStore ?? ClipboardTemporaryFileStore()
        self.imageCoder = imageCoder ?? ClipboardImageCoder(limits: limits, timeouts: timeouts)
        self.limits = limits
        self.timeouts = timeouts
    }

    /// Picks the request kind to use for `provider`, honoring `acceptedTypes` and the documented
    /// per-provider priority: text > url > image > file.
    /// - Returns: `nil` when the provider advertises nothing the caller accepts.
    static func requestKind(for provider: NSItemProvider, acceptedTypes: [String]) -> ClipboardLoadRequest? {
        // Only counts are logged: a type identifier can be caller-supplied data.
        Log.d(staticTAG, "[requestKind] acceptedTypeCount: \(acceptedTypes.count), "
            + "providerTypeCount: \(provider.registeredTypeIdentifiers.count)")
        let acceptedUTTypes = acceptedTypes.compactMap { UTType($0) }
        if acceptedUTTypes.contains(where: { $0.conforms(to: .text) }),
           provider.canLoadObject(ofClass: NSString.self) {
            return .text
        }
        if acceptedUTTypes.contains(where: { $0.conforms(to: .url) }),
           provider.canLoadObject(ofClass: NSURL.self) {
            return .url
        }
        if acceptedUTTypes.contains(where: { $0.conforms(to: .image) }),
           provider.hasItemConformingToTypeIdentifier(UTType.image.identifier) {
            return .image
        }
        if let fileType = acceptedTypes.first(where: { provider.hasItemConformingToTypeIdentifier($0) }) {
            return .file(utType: fileType)
        }
        return nil
    }

    /// Starts the load. `completion` is invoked exactly once on the main actor.
    @discardableResult
    func start(
        _ request: ClipboardLoadRequest,
        from provider: NSItemProvider,
        completion: @escaping (Result<ClipboardLoadedItem, ClipboardError>) -> Void
    ) -> ClipboardProviderLoadHandle {
        Log.d(TAG, "[start] request kind resolved, providerLoadTimeout: \(timeouts.providerLoad)")
        let handle = ClipboardProviderLoadHandle(fileStore: fileStore, completion: completion)

        let seconds = max(timeouts.providerLoad, 0)
        handle.timeoutTask = Task { @MainActor [weak handle] in
            try? await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
            guard !Task.isCancelled else { return }
            handle?.finish(.failure(.timedOut(operation: .providerLoad)), tempFileURL: nil)
        }

        switch request {
        case .text:
            startTextLoad(provider: provider, handle: handle)
        case .url:
            startURLLoad(provider: provider, handle: handle)
        case .image:
            startImageLoad(provider: provider, handle: handle)
        case .file(let utType):
            startFileLoad(provider: provider, utType: utType, handle: handle)
        }
        return handle
    }

    // MARK: - Per-kind loads

    private func startTextLoad(provider: NSItemProvider, handle: ClipboardProviderLoadHandle) {
        let limits = self.limits
        handle.progress = provider.loadObject(ofClass: NSString.self) { object, error in
            let outcome: Result<ClipboardLoadedItem, ClipboardError>
            if let error {
                outcome = .failure(.providerLoadFailed(ClipboardFailureDetail(systemError: error)))
            } else if let text = object as? NSString {
                let value = text as String
                let byteCount = value.utf8.count
                if byteCount > limits.maxLoadByteCount {
                    outcome = .failure(.contentTooLarge(byteCount: byteCount, limit: limits.maxLoadByteCount))
                } else {
                    outcome = .success(.text(value))
                }
            } else {
                outcome = .failure(.unexpectedType)
            }
            Task { @MainActor in handle.finish(outcome, tempFileURL: nil) }
        }
    }

    private func startURLLoad(provider: NSItemProvider, handle: ClipboardProviderLoadHandle) {
        let limits = self.limits
        handle.progress = provider.loadObject(ofClass: NSURL.self) { object, error in
            let outcome: Result<ClipboardLoadedItem, ClipboardError>
            if let error {
                outcome = .failure(.providerLoadFailed(ClipboardFailureDetail(systemError: error)))
            } else if let url = object as? NSURL, let absolute = url.absoluteString {
                let byteCount = absolute.utf8.count
                if byteCount > limits.maxLoadByteCount {
                    outcome = .failure(.contentTooLarge(byteCount: byteCount, limit: limits.maxLoadByteCount))
                } else {
                    outcome = .success(.url(absolute))
                }
            } else {
                outcome = .failure(.unexpectedType)
            }
            Task { @MainActor in handle.finish(outcome, tempFileURL: nil) }
        }
    }

    private func startImageLoad(provider: NSItemProvider, handle: ClipboardProviderLoadHandle) {
        let limits = self.limits
        let imageCoder = self.imageCoder
        handle.progress = provider.loadDataRepresentation(forTypeIdentifier: UTType.image.identifier) { data, error in
            if let error {
                Task { @MainActor in
                    handle.finish(
                        .failure(.providerLoadFailed(ClipboardFailureDetail(systemError: error))),
                        tempFileURL: nil
                    )
                }
                return
            }
            guard let data else {
                Task { @MainActor in handle.finish(.failure(.unexpectedType), tempFileURL: nil) }
                return
            }
            guard data.count <= limits.maxLoadByteCount else {
                Task { @MainActor in
                    handle.finish(
                        .failure(.contentTooLarge(byteCount: data.count, limit: limits.maxLoadByteCount)),
                        tempFileURL: nil
                    )
                }
                return
            }
            Task { @MainActor in
                do {
                    let png = try await imageCoder.encodePastedImage(data)
                    handle.finish(.success(.imageData(png, utType: UTType.png.identifier)), tempFileURL: nil)
                } catch let error as ClipboardError {
                    handle.finish(.failure(error), tempFileURL: nil)
                } catch {
                    handle.finish(.failure(.unknown(ClipboardFailureDetail(systemError: error))), tempFileURL: nil)
                }
            }
        }
    }

    private func startFileLoad(provider: NSItemProvider, utType: String, handle: ClipboardProviderLoadHandle) {
        let limits = self.limits
        let fileStore = self.fileStore
        let suggestedName = provider.suggestedName
        handle.progress = provider.loadFileRepresentation(forTypeIdentifier: utType) { url, error in
            var outcome: Result<ClipboardLoadedItem, ClipboardError>
            var producedFileURL: URL?

            if let error {
                outcome = .failure(.providerLoadFailed(ClipboardFailureDetail(systemError: error)))
            } else if let url {
                // The URL is valid only inside this callback; copy it synchronously here.
                let didStartAccess = url.startAccessingSecurityScopedResource()
                defer { if didStartAccess { url.stopAccessingSecurityScopedResource() } }

                // The size limit is a security boundary, so it is enforced *before* any bytes are
                // written: if the source size cannot be read, the copy must not start at all —
                // an unbounded copy into the temporary directory is exactly what the limit exists
                // to prevent.
                let preCopySize = try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize
                if preCopySize == nil {
                    outcome = .failure(.fileCopyFailed(ClipboardFailureDetail(
                        domain: FailureDetailCode.domain,
                        code: FailureDetailCode.sourceSizeUnverifiable,
                        debugMessage: "source file size could not be verified before copying"
                    )))
                } else if let preCopySize, preCopySize > limits.maxLoadByteCount {
                    outcome = .failure(.contentTooLarge(byteCount: preCopySize, limit: limits.maxLoadByteCount))
                } else {
                    do {
                        let destination = try fileStore.store(sourceURL: url, suggestedName: suggestedName)
                        producedFileURL = destination
                        // Same boundary after the copy: an unverifiable size must not pass as
                        // success, so a post-copy size read failure is treated as an error.
                        let postCopySize = try? destination.resourceValues(forKeys: [.fileSizeKey]).fileSize
                        if let postCopySize {
                            outcome = postCopySize > limits.maxLoadByteCount
                                ? .failure(.contentTooLarge(byteCount: postCopySize, limit: limits.maxLoadByteCount))
                                : .success(.file(destination))
                        } else {
                            outcome = .failure(.fileCopyFailed(ClipboardFailureDetail(
                                domain: FailureDetailCode.domain,
                                code: FailureDetailCode.copiedSizeUnverifiable,
                                debugMessage: "copied file size could not be verified"
                            )))
                        }
                    } catch let storeError as ClipboardError {
                        outcome = .failure(storeError)
                    } catch {
                        outcome = .failure(.unknown(ClipboardFailureDetail(systemError: error)))
                    }
                }
            } else {
                outcome = .failure(.unexpectedType)
            }

            let capturedOutcome = outcome
            let capturedFileURL = producedFileURL
            Task { @MainActor in handle.finish(capturedOutcome, tempFileURL: capturedFileURL) }
        }
    }
}
