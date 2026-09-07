//
//  MockClipboardPromiseRegistry.swift
//  MacLibraryTests
//

import Foundation
@testable import MacLibrary

/// Records lazy provider registrations and releases.
@MainActor
final class MockClipboardPromiseRegistry: ClipboardPromiseRegistry {

    // MARK: Recorded calls

    private(set) var registerLazyProviderCallCount = 0
    private(set) var releaseLazyProviderCallCount = 0
    private(set) var lastLazyProviderTypes: [String]?
    private(set) var releasedLazyHandles: [PasteboardPromiseHandle] = []

    // MARK: Stubs

    var stubbedLazyHandle = PasteboardPromiseHandle()

    // MARK: ClipboardPromiseRegistry

    func registerLazyProvider(types: [String],
                              provide: @escaping @Sendable (String) -> Data?) -> PasteboardPromiseHandle {
        registerLazyProviderCallCount += 1
        lastLazyProviderTypes = types
        return stubbedLazyHandle
    }

    func releaseLazyProvider(_ handle: PasteboardPromiseHandle) {
        releaseLazyProviderCallCount += 1
        releasedLazyHandles.append(handle)
    }
}
