//
//  ReleaseFilePromiseUseCase.swift
//  MacLibrary
//

import Foundation

/// OP-17. Releases a file promise registration and its staging directory.
@MainActor
public struct ReleaseFilePromiseUseCase {

    private let TAG = "ReleaseFilePromiseUseCase"

    private let registry: any ClipboardPromiseRegistry

    /// Creates the use case with the ports it needs. Dependencies are injected so a test can substitute mocks.
    public init(registry: any ClipboardPromiseRegistry) {
        self.registry = registry
    }

    /// Idempotent and non throwing. An unknown or already released handle is a no-op, because
    /// a caller that releases twice has still achieved what it wanted.
    public func callAsFunction(_ handle: FilePromiseHandle) {
        Log.d(TAG, "[callAsFunction] handle: \(handle.id)")
        registry.releaseFilePromise(handle)
    }
}
