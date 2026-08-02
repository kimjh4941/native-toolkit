//
//  PasteItemProviderLoader.swift
//  IosLibrary
//

import Foundation
import UIKit
import UniformTypeIdentifiers

/// Aggregates loading an explicit `[NSItemProvider]` array handed over by `UIResponder.paste(itemProviders:)`.
///
/// Lives in Presentation because `NSItemProvider` must not appear in an Application Port.
/// Per-provider type priority: text > url > image > file is not modeled explicitly (file loading
/// requires an accepted custom UTI outside the standard three); unmatched providers fail with
/// `.noMatchingItem`, which participates in the aggregate result like any other failure.
///
/// Marked `@unchecked Sendable` for the same reason as `ClipboardItemLoaderImpl`: instances are
/// captured across `Task { @MainActor in ... }` hops from `NSItemProvider` completion callbacks
/// whose thread is unspecified; all mutable state is only touched from `finishOne` on the main
/// actor.
@MainActor
final class PasteItemProviderLoader: @unchecked Sendable {
    struct AggregateResult {
        let items: [ClipboardLoadedItem]
        let failures: [ClipboardError]
    }

    private final class Session {
        var results: [Result<ClipboardLoadedItem, ClipboardError>?]
        var remaining: Int
        var isCancelled = false
        let completion: (AggregateResult) -> Void

        init(count: Int, completion: @escaping (AggregateResult) -> Void) {
            self.results = Array(repeating: nil, count: count)
            self.remaining = count
            self.completion = completion
        }
    }

    private let TAG = "PasteItemProviderLoader"
    private let imageCoder: ClipboardImageCoder
    private let limits: ClipboardLimits
    private var currentSession: Session?

    nonisolated init(imageCoder: ClipboardImageCoder = ClipboardImageCoder(), limits: ClipboardLimits = .default) {
        self.imageCoder = imageCoder
        self.limits = limits
    }

    /// Loads every provider, preserving input order in `items`. A new call supersedes any
    /// pending session: the previous session's completion is never invoked (see `cancelAll`).
    func load(providers: [NSItemProvider], completion: @escaping (AggregateResult) -> Void) {
        Log.d(TAG, "[load] providerCount: \(providers.count)")
        cancelAll()
        guard !providers.isEmpty else {
            completion(AggregateResult(items: [], failures: [.noMatchingItem]))
            return
        }
        let session = Session(count: providers.count, completion: completion)
        currentSession = session

        for (index, provider) in providers.enumerated() {
            loadSingle(provider) { [weak self] outcome in
                self?.receive(session: session, index: index, outcome: outcome)
            }
        }
    }

    /// Cancels the pending session, if any. Its completion is never invoked — cancellation is
    /// caller-initiated (a new paste, or the owning view being torn down) and must not surface as
    /// a UI callback.
    func cancelAll() {
        Log.d(TAG, "[cancelAll]")
        currentSession?.isCancelled = true
        currentSession = nil
    }

    private nonisolated func receive(session: Session, index: Int, outcome: Result<ClipboardLoadedItem, ClipboardError>) {
        Task { @MainActor in
            self.finishOne(session: session, index: index, outcome: outcome)
        }
    }

    private func finishOne(session: Session, index: Int, outcome: Result<ClipboardLoadedItem, ClipboardError>) {
        guard !session.isCancelled, currentSession === session else { return }
        session.results[index] = outcome
        session.remaining -= 1
        guard session.remaining == 0 else { return }
        currentSession = nil

        var items: [ClipboardLoadedItem] = []
        var failures: [ClipboardError] = []
        for result in session.results {
            switch result {
            case .success(let item): items.append(item)
            case .failure(let error): failures.append(error)
            case .none: break
            }
        }
        session.completion(AggregateResult(items: items, failures: failures))
    }

    private func loadSingle(
        _ provider: NSItemProvider,
        completion: @escaping (Result<ClipboardLoadedItem, ClipboardError>) -> Void
    ) {
        if provider.canLoadObject(ofClass: NSString.self) {
            provider.loadObject(ofClass: NSString.self) { object, error in
                if let error {
                    completion(.failure(.providerLoadFailed(ClipboardFailureDetail(systemError: error))))
                } else if let text = object as? NSString {
                    completion(.success(.text(text as String)))
                } else {
                    completion(.failure(.unexpectedType))
                }
            }
            return
        }

        if provider.canLoadObject(ofClass: NSURL.self) {
            provider.loadObject(ofClass: NSURL.self) { object, error in
                if let error {
                    completion(.failure(.providerLoadFailed(ClipboardFailureDetail(systemError: error))))
                } else if let url = object as? NSURL {
                    completion(.success(.url(url.absoluteString ?? "")))
                } else {
                    completion(.failure(.unexpectedType))
                }
            }
            return
        }

        if provider.hasItemConformingToTypeIdentifier(UTType.image.identifier) {
            let imageCoder = self.imageCoder
            let limits = self.limits
            provider.loadDataRepresentation(forTypeIdentifier: UTType.image.identifier) { data, error in
                if let error {
                    completion(.failure(.providerLoadFailed(ClipboardFailureDetail(systemError: error))))
                    return
                }
                guard let data else {
                    completion(.failure(.unexpectedType))
                    return
                }
                guard data.count <= limits.maxLoadByteCount else {
                    completion(.failure(.contentTooLarge(byteCount: data.count, limit: limits.maxLoadByteCount)))
                    return
                }
                Task {
                    do {
                        let png = try await imageCoder.encodePastedImage(data)
                        completion(.success(.imageData(png, utType: "public.png")))
                    } catch let error as ClipboardError {
                        completion(.failure(error))
                    } catch {
                        completion(.failure(.unknown(ClipboardFailureDetail(systemError: error))))
                    }
                }
            }
            return
        }

        completion(.failure(.noMatchingItem))
    }
}
