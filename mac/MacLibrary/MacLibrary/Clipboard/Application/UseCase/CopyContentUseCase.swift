//
//  CopyContentUseCase.swift
//  MacLibrary
//

import Foundation

/// OP-01. Validates content, then takes ownership of the pasteboard and writes it.
///
/// Large single-item content is written through a lazy data provider instead: the pasteboard
/// is told which types are available and the bytes are produced only if a reader asks. That
/// keeps a big copy off the main actor for data nobody may ever paste. The choice is internal
/// and invisible to callers (RK-17).
@MainActor
public struct CopyContentUseCase {

    private let TAG = "CopyContentUseCase"

    private let repository: any ClipboardRepository
    private let registry: any ClipboardPromiseRegistry
    private let validator: ClipboardContentValidator

    /// Creates the use case with the ports it needs. Dependencies are injected so a test can substitute mocks.
    public init(repository: any ClipboardRepository,
                registry: any ClipboardPromiseRegistry,
                validator: ClipboardContentValidator) {
        self.repository = repository
        self.registry = registry
        self.validator = validator
    }

    /// - Returns: Proof of ownership, required by ``AppendContentUseCase``.
    public func callAsFunction(_ content: ClipboardContent,
                               options: ClipboardCopyOptions,
                               scope: PasteboardScope) throws -> PasteboardOwnership {
        Log.d(TAG, "[callAsFunction] content: \(ClipboardLog.content(content)), "
              + "localOnly: \(options.localOnly), scope: \(ClipboardLog.scope(scope))")
        try validator.validate(content)
        guard validator.shouldUseLazyProvision(content), let item = content.items.first else {
            return try repository.write(content, options: options, scope: scope)
        }
        return try writeLazily(item, options: options, scope: scope)
    }

    /// Register, write, and roll the registration back if the write fails (R2-M12).
    private func writeLazily(_ item: ClipboardItemData,
                             options: ClipboardCopyOptions,
                             scope: PasteboardScope) throws -> PasteboardOwnership {
        Log.d(TAG, "[writeLazily] reps: \(item.representations.count)")
        // Captured by value so the closure is Sendable and the bytes outlive this call.
        let representations = item.representations
        let types = representations.keys.sorted()
        let handle = registry.registerLazyProvider(types: types) { identifier in
            representations[identifier]
        }
        do {
            return try repository.writePromised(handle: handle, types: types,
                                                options: options, scope: scope)
        } catch {
            // Without this the provider would be held for the life of the app for a pasteboard
            // item that was never written.
            registry.releaseLazyProvider(handle)
            throw error
        }
    }
}
