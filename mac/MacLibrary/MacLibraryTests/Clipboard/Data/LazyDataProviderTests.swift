//
//  LazyDataProviderTests.swift
//  MacLibraryTests
//

import Testing
import AppKit
import Foundation
@testable import MacLibrary

@Suite("Lazy data provision")
@MainActor
struct LazyDataProviderTests {

    private let text = "public.utf8-plain-text"

    private func makeCoordinator() -> ClipboardSystemCoordinator {
        ClipboardSystemCoordinator()
    }

    private func makeValidator(warn: Int, max: Int, total: Int) throws -> ClipboardContentValidator {
        ClipboardContentValidator(
            limits: try ClipboardLimits(warnBytesPerRepresentation: warn,
                                        maxBytesPerRepresentation: max,
                                        maxTotalBytes: total),
            typeValidator: MockClipboardTypeIdentifierValidating())
    }

    private func content(_ representations: [String: Data]...) -> ClipboardContent {
        ClipboardContent(items: representations.map { ClipboardItemData(representations: $0) })
    }

    private func bytes(_ count: Int) -> Data { Data(repeating: 0x41, count: count) }

    // MARK: - Selection

    @Test("small content is written directly")
    func smallContentIsDirect() throws {
        let validator = try makeValidator(warn: 100, max: 200, total: 300)
        #expect(!validator.shouldUseLazyProvision(content([text: bytes(50)])))
    }

    @Test("content exactly on the warn threshold is written directly")
    func thresholdIsExclusive() throws {
        let validator = try makeValidator(warn: 100, max: 200, total: 300)
        // Only content past the threshold is worth deferring.
        #expect(!validator.shouldUseLazyProvision(content([text: bytes(100)])))
        #expect(validator.shouldUseLazyProvision(content([text: bytes(101)])))
    }

    @Test("multi item content is written directly regardless of size")
    func multiItemIsDirect() throws {
        let validator = try makeValidator(warn: 100, max: 200, total: 300)
        // A provider is registered per pasteboard item, so several items would need several
        // registrations and a rollback across all of them.
        #expect(!validator.shouldUseLazyProvision(content([text: bytes(150)], [text: bytes(150)])))
    }

    // MARK: - Transaction

    @Test("a large copy registers a provider and writes it promised")
    func largeCopyUsesProvider() throws {
        let repository = MockClipboardRepository()
        let coordinator = makeCoordinator()
        let useCase = CopyContentUseCase(repository: repository, registry: coordinator,
                                         validator: try makeValidator(warn: 100, max: 500, total: 500))

        _ = try useCase(content([text: bytes(200)]), options: .default, scope: .general)

        #expect(repository.writePromisedCallCount == 1)
        #expect(repository.writeCallCount == 0)
        #expect(coordinator.registeredLazyProviderCount == 1)
    }

    @Test("a small copy leaves no registration behind")
    func smallCopyRegistersNothing() throws {
        let repository = MockClipboardRepository()
        let coordinator = makeCoordinator()
        let useCase = CopyContentUseCase(repository: repository, registry: coordinator,
                                         validator: try makeValidator(warn: 100, max: 500, total: 500))

        _ = try useCase(content([text: bytes(50)]), options: .default, scope: .general)

        #expect(repository.writeCallCount == 1)
        #expect(coordinator.registeredLazyProviderCount == 0)
    }

    @Test("R2-M12: a failed promised write rolls the registration back")
    func failedWriteReleasesProvider() throws {
        let repository = MockClipboardRepository()
        repository.shouldFail = .writeRejected
        let coordinator = makeCoordinator()
        let useCase = CopyContentUseCase(repository: repository, registry: coordinator,
                                         validator: try makeValidator(warn: 100, max: 500, total: 500))

        #expect(throws: ClipboardError.writeRejected) {
            _ = try useCase(self.content([self.text: self.bytes(200)]),
                            options: .default, scope: .general)
        }
        // Otherwise the provider would be held for the life of the app for an item that was
        // never written.
        #expect(coordinator.registeredLazyProviderCount == 0)
    }

    @Test("the registered types are the item's representations")
    func registeredTypesMatchContent() throws {
        let repository = MockClipboardRepository()
        let coordinator = makeCoordinator()
        let useCase = CopyContentUseCase(repository: repository, registry: coordinator,
                                         validator: try makeValidator(warn: 10, max: 500, total: 500))

        _ = try useCase(content([text: bytes(20), "public.rtf": bytes(20)]),
                        options: .default, scope: .general)

        let handle = try #require(coordinator.lazyProviderHandlesForTests.first)
        #expect(coordinator.lazyProviderTypes(for: handle) == ["public.rtf", text])
    }

    // MARK: - Provider behaviour

    @Test("the provider supplies bytes only when a type is requested")
    func providerSuppliesOnDemand() throws {
        let coordinator = makeCoordinator()
        let handle = coordinator.registerLazyProvider(types: [text]) { identifier in
            identifier == self.text ? Data("lazy".utf8) : nil
        }
        let provider = try #require(coordinator.lazyProvider(for: handle) as? LazyDataProvider)

        let item = NSPasteboardItem()
        provider.pasteboard(nil, item: item, provideDataForType: .init(text))

        #expect(item.data(forType: .init(text)) == Data("lazy".utf8))
    }

    @Test("declining a type leaves it absent rather than empty")
    func providerCanDecline() throws {
        let coordinator = makeCoordinator()
        let handle = coordinator.registerLazyProvider(types: [text]) { _ in nil }
        let provider = try #require(coordinator.lazyProvider(for: handle) as? LazyDataProvider)

        let item = NSPasteboardItem()
        provider.pasteboard(nil, item: item, provideDataForType: .init(text))

        // An empty value would look like a successful paste of nothing.
        #expect(item.data(forType: .init(text)) == nil)
    }

    @Test("the pasteboard finishing releases the registration")
    func finishReleasesRegistration() async throws {
        let coordinator = makeCoordinator()
        let handle = coordinator.registerLazyProvider(types: [text]) { _ in nil }
        let provider = try #require(coordinator.lazyProvider(for: handle) as? LazyDataProvider)
        #expect(coordinator.registeredLazyProviderCount == 1)

        // L-03 is the only signal that the provider will never be asked again.
        provider.pasteboardFinishedWithDataProvider(NSPasteboard.withUniqueName())
        try await Task.sleep(for: .milliseconds(50))

        #expect(coordinator.registeredLazyProviderCount == 0)
    }

    // MARK: - Real pasteboard

    @Test("a promised write round trips through a real pasteboard")
    func promisedWriteRoundTrips() throws {
        let coordinator = makeCoordinator()
        let repository = ClipboardRepositoryImpl(validator: ClipboardTypeIdentifierValidator(),
                                                 lookup: coordinator)
        let scope = try repository.createPasteboard(.unique)
        defer { try? repository.removePasteboard(scope) }

        let handle = coordinator.registerLazyProvider(types: [text]) { _ in Data("deferred".utf8) }
        _ = try repository.writePromised(handle: handle, types: [text],
                                         options: .default, scope: scope)

        // The bytes were never handed over up front; reading is what pulls them.
        #expect(try repository.readData(utType: text, scope: scope) == Data("deferred".utf8))
    }

    @Test("a promised write with no types is rejected")
    func promisedWriteRejectsEmptyTypes() throws {
        let coordinator = makeCoordinator()
        let repository = ClipboardRepositoryImpl(validator: ClipboardTypeIdentifierValidator(),
                                                 lookup: coordinator)
        let handle = coordinator.registerLazyProvider(types: []) { _ in nil }

        #expect(throws: ClipboardError.emptyRepresentations(itemIndex: 0)) {
            _ = try repository.writePromised(handle: handle, types: [],
                                             options: .default, scope: .general)
        }
    }
}
