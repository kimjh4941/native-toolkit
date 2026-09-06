//
//  ClipboardSystemCoordinatorTests.swift
//  MacLibraryTests
//

import Testing
import Foundation
@testable import MacLibrary

@Suite("ClipboardSystemCoordinator")
@MainActor
struct ClipboardSystemCoordinatorTests {

    // MARK: - Lazy providers

    @Test("a lazy provider is held until released")
    func lazyProviderLifecycle() {
        let coordinator = ClipboardSystemCoordinator()
        let handle = coordinator.registerLazyProvider(types: ["public.png"]) { _ in nil }

        #expect(coordinator.registeredLazyProviderCount == 1)
        coordinator.releaseLazyProvider(handle)
        #expect(coordinator.registeredLazyProviderCount == 0)
    }

    @Test("releasing a lazy provider twice is a no-op")
    func lazyProviderReleaseIsIdempotent() {
        let coordinator = ClipboardSystemCoordinator()
        let handle = coordinator.registerLazyProvider(types: ["public.png"]) { _ in nil }

        coordinator.releaseLazyProvider(handle)
        coordinator.releaseLazyProvider(handle)
        coordinator.releaseLazyProvider(PasteboardPromiseHandle())

        #expect(coordinator.registeredLazyProviderCount == 0)
    }

    @Test("the registered types are recorded with the provider")
    func lazyProviderKeepsItsTypes() {
        let coordinator = ClipboardSystemCoordinator()
        let handle = coordinator.registerLazyProvider(types: ["public.png", "public.tiff"]) { _ in nil }

        #expect(coordinator.lazyProviderTypes(for: handle) == ["public.png", "public.tiff"])
        #expect(coordinator.lazyProviderHandlesForTests == [handle])
    }

    @Test("an unknown handle resolves to no provider")
    func unknownLazyProviderResolvesToNil() {
        let coordinator = ClipboardSystemCoordinator()

        #expect(coordinator.lazyProvider(for: PasteboardPromiseHandle()) == nil)
        #expect(coordinator.lazyProviderTypes(for: PasteboardPromiseHandle()) == nil)
    }
}
