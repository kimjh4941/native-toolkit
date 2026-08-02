//
//  ClipboardItemLoaderImpl.swift
//  IosLibrary
//

import Foundation
import UIKit
import UniformTypeIdentifiers

/// `NSItemProvider`-backed implementation of `ClipboardItemLoader`.
///
/// Implements the exactly-once delivery contract: every request is registered in `requests` at
/// issuance time (before a provider is even searched for), so `cancelAll()` / a token's
/// `cancel()` catch it even on the immediate-failure path. Completion is delivered through the
/// single `finish(id:outcome:tempFileURL:)` gate, which resolves the race between success,
/// provider error, cancellation, and timeout — whichever reaches the gate first wins; anything
/// that arrives afterward (including a produced temp file) is discarded.
///
/// Marked `@unchecked Sendable` because instances are captured by `Task { @MainActor in ... }`
/// closures spawned from `NSItemProvider` completion handlers running on unspecified threads;
/// all mutable state is exclusively read/written on the main actor via `finish`/`cancelAll`/
/// `cancel(id:)`, so this is safe by construction.
@MainActor
final class ClipboardItemLoaderImpl: ClipboardItemLoader, @unchecked Sendable {
    private final class Request {
        let completion: (Result<ClipboardLoadedItem, ClipboardError>) -> Void
        var progress: Progress?
        var timeoutTask: Task<Void, Never>?
        init(completion: @escaping (Result<ClipboardLoadedItem, ClipboardError>) -> Void) {
            self.completion = completion
        }
    }

    private let TAG = "ClipboardItemLoaderImpl"
    private let resolver: PasteboardResolver
    private let fileStore: ClipboardTemporaryFileStore
    private let imageCoder: ClipboardImageCoder
    private let limits: ClipboardLimits
    private let timeouts: ClipboardTimeouts
    private var nextID = 0
    private var requests: [Int: Request] = [:]

    nonisolated init(
        resolver: PasteboardResolver = PasteboardResolver(),
        fileStore: ClipboardTemporaryFileStore = ClipboardTemporaryFileStore(),
        imageCoder: ClipboardImageCoder = ClipboardImageCoder(),
        limits: ClipboardLimits = .default,
        timeouts: ClipboardTimeouts = .default
    ) {
        self.resolver = resolver
        self.fileStore = fileStore
        self.imageCoder = imageCoder
        self.limits = limits
        self.timeouts = timeouts
    }

    @discardableResult
    func load(
        _ request: ClipboardLoadRequest,
        scope: PasteboardScope,
        completion: @escaping (Result<ClipboardLoadedItem, ClipboardError>) -> Void
    ) -> any ClipboardLoadToken {
        Log.d(TAG, "[load] scope: \(scope)")
        let id = nextID
        nextID += 1
        requests[id] = Request(completion: completion)
        let token = ClipboardLoadTokenImpl(loader: self, id: id)

        let pasteboard: UIPasteboard
        do {
            pasteboard = try resolver.resolve(scope)
        } catch let error as ClipboardError {
            scheduleFinish(id: id, outcome: .failure(error), tempFileURL: nil)
            return token
        } catch {
            scheduleFinish(id: id, outcome: .failure(.unknown(ClipboardFailureDetail(systemError: error))), tempFileURL: nil)
            return token
        }

        guard let provider = Self.firstMatchingProvider(request, in: pasteboard.itemProviders) else {
            scheduleFinish(id: id, outcome: .failure(.noMatchingItem), tempFileURL: nil)
            return token
        }

        startTimeout(id: id)
        startLoad(id: id, request: request, provider: provider)
        return token
    }

    func cancelAll() {
        Log.d(TAG, "[cancelAll]")
        let pending = requests
        requests.removeAll()
        for (_, requestState) in pending {
            requestState.timeoutTask?.cancel()
            requestState.progress?.cancel()
            requestState.completion(.failure(.cancelled))
        }
    }

    func cancel(id: Int) {
        Log.d(TAG, "[cancel] id: \(id)")
        guard let requestState = requests.removeValue(forKey: id) else { return }
        requestState.timeoutTask?.cancel()
        requestState.progress?.cancel()
        requestState.completion(.failure(.cancelled))
    }

    isolated deinit {
        cancelAll()
    }

    // MARK: - Private

    private static func firstMatchingProvider(
        _ request: ClipboardLoadRequest,
        in providers: [NSItemProvider]
    ) -> NSItemProvider? {
        switch request {
        case .text:
            return providers.first { $0.canLoadObject(ofClass: NSString.self) }
        case .url:
            return providers.first { $0.canLoadObject(ofClass: NSURL.self) }
        case .image:
            return providers.first { $0.hasItemConformingToTypeIdentifier(UTType.image.identifier) }
        case .file(let utType):
            return providers.first { $0.hasItemConformingToTypeIdentifier(utType) }
        }
    }

    private func startTimeout(id: Int) {
        let seconds = max(timeouts.providerLoad, 0)
        let task = Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
            guard !Task.isCancelled else { return }
            self?.finish(id: id, outcome: .failure(.timedOut(operation: .providerLoad)), tempFileURL: nil)
        }
        requests[id]?.timeoutTask = task
    }

    private func startLoad(id: Int, request: ClipboardLoadRequest, provider: NSItemProvider) {
        switch request {
        case .text:
            let progress = provider.loadObject(ofClass: NSString.self) { [weak self] object, error in
                guard let self else { return }
                if let error {
                    self.scheduleFinish(
                        id: id, outcome: .failure(.providerLoadFailed(ClipboardFailureDetail(systemError: error))),
                        tempFileURL: nil
                    )
                } else if let text = object as? NSString {
                    self.scheduleFinish(id: id, outcome: .success(.text(text as String)), tempFileURL: nil)
                } else {
                    self.scheduleFinish(id: id, outcome: .failure(.unexpectedType), tempFileURL: nil)
                }
            }
            requests[id]?.progress = progress

        case .url:
            let progress = provider.loadObject(ofClass: NSURL.self) { [weak self] object, error in
                guard let self else { return }
                if let error {
                    self.scheduleFinish(
                        id: id, outcome: .failure(.providerLoadFailed(ClipboardFailureDetail(systemError: error))),
                        tempFileURL: nil
                    )
                } else if let url = object as? NSURL {
                    self.scheduleFinish(id: id, outcome: .success(.url(url.absoluteString ?? "")), tempFileURL: nil)
                } else {
                    self.scheduleFinish(id: id, outcome: .failure(.unexpectedType), tempFileURL: nil)
                }
            }
            requests[id]?.progress = progress

        case .image:
            let limits = self.limits
            let imageCoder = self.imageCoder
            let progress = provider.loadDataRepresentation(forTypeIdentifier: UTType.image.identifier) { [weak self] data, error in
                guard let self else { return }
                if let error {
                    self.scheduleFinish(
                        id: id, outcome: .failure(.providerLoadFailed(ClipboardFailureDetail(systemError: error))),
                        tempFileURL: nil
                    )
                    return
                }
                guard let data else {
                    self.scheduleFinish(id: id, outcome: .failure(.unexpectedType), tempFileURL: nil)
                    return
                }
                guard data.count <= limits.maxLoadByteCount else {
                    self.scheduleFinish(
                        id: id,
                        outcome: .failure(.contentTooLarge(byteCount: data.count, limit: limits.maxLoadByteCount)),
                        tempFileURL: nil
                    )
                    return
                }
                Task {
                    do {
                        let png = try await imageCoder.encodePastedImage(data)
                        self.scheduleFinish(id: id, outcome: .success(.imageData(png, utType: "public.png")), tempFileURL: nil)
                    } catch let error as ClipboardError {
                        self.scheduleFinish(id: id, outcome: .failure(error), tempFileURL: nil)
                    } catch {
                        self.scheduleFinish(
                            id: id, outcome: .failure(.unknown(ClipboardFailureDetail(systemError: error))), tempFileURL: nil
                        )
                    }
                }
            }
            requests[id]?.progress = progress

        case .file(let utType):
            let suggestedName = provider.suggestedName
            let limits = self.limits
            let fileStore = self.fileStore
            let progress = provider.loadFileRepresentation(forTypeIdentifier: utType) { [weak self] url, error in
                guard let self else { return }
                if let error {
                    self.scheduleFinish(
                        id: id, outcome: .failure(.providerLoadFailed(ClipboardFailureDetail(systemError: error))),
                        tempFileURL: nil
                    )
                    return
                }
                guard let url else {
                    self.scheduleFinish(id: id, outcome: .failure(.unexpectedType), tempFileURL: nil)
                    return
                }
                // The URL is only valid inside this callback; copy it synchronously here.
                let didStartAccess = url.startAccessingSecurityScopedResource()
                defer { if didStartAccess { url.stopAccessingSecurityScopedResource() } }

                if let preSize = try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize,
                   preSize > limits.maxLoadByteCount {
                    self.scheduleFinish(
                        id: id,
                        outcome: .failure(.contentTooLarge(byteCount: preSize, limit: limits.maxLoadByteCount)),
                        tempFileURL: nil
                    )
                    return
                }

                do {
                    let destination = try fileStore.store(sourceURL: url, suggestedName: suggestedName)
                    if let postSize = try? destination.resourceValues(forKeys: [.fileSizeKey]).fileSize,
                       postSize > limits.maxLoadByteCount {
                        fileStore.discard(destination)
                        self.scheduleFinish(
                            id: id,
                            outcome: .failure(.contentTooLarge(byteCount: postSize, limit: limits.maxLoadByteCount)),
                            tempFileURL: nil
                        )
                        return
                    }
                    self.scheduleFinish(id: id, outcome: .success(.file(destination)), tempFileURL: destination)
                } catch let error as ClipboardError {
                    self.scheduleFinish(id: id, outcome: .failure(error), tempFileURL: nil)
                } catch {
                    self.scheduleFinish(
                        id: id, outcome: .failure(.unknown(ClipboardFailureDetail(systemError: error))), tempFileURL: nil
                    )
                }
            }
            requests[id]?.progress = progress
        }
    }

    /// Callable from any thread; hops to the main actor to resolve the single delivery gate.
    nonisolated private func scheduleFinish(id: Int, outcome: Result<ClipboardLoadedItem, ClipboardError>, tempFileURL: URL?) {
        Task { @MainActor in
            self.finish(id: id, outcome: outcome, tempFileURL: tempFileURL)
        }
    }

    /// The single gate resolving success / error / cancellation / timeout exactly once.
    private func finish(id: Int, outcome: Result<ClipboardLoadedItem, ClipboardError>, tempFileURL: URL?) {
        guard let requestState = requests.removeValue(forKey: id) else {
            if let tempFileURL { fileStore.discard(tempFileURL) }
            return
        }
        requestState.timeoutTask?.cancel()
        if case .failure = outcome, let tempFileURL {
            fileStore.discard(tempFileURL)
        }
        requestState.completion(outcome)
    }
}

/// Cancellation handle returned by `ClipboardItemLoaderImpl.load`.
@MainActor
final class ClipboardLoadTokenImpl: ClipboardLoadToken, @unchecked Sendable {
    private weak var loader: ClipboardItemLoaderImpl?
    private let id: Int

    init(loader: ClipboardItemLoaderImpl, id: Int) {
        self.loader = loader
        self.id = id
    }

    func cancel() {
        loader?.cancel(id: id)
    }
}
