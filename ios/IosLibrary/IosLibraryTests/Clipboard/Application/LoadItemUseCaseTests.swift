//
//  LoadItemUseCaseTests.swift
//  IosLibraryTests
//

import Testing
@testable import IosLibrary

@MainActor
struct LoadItemUseCaseTests {
    @Test func executeReturnsEachLoadedKind() {
        let loader = MockClipboardItemLoader()
        let useCase = LoadItemUseCase(loader: loader)

        loader.stubbedResult = .success(.text("hi"))
        var received: Result<ClipboardLoadedItem, ClipboardError>?
        useCase.execute(.text, scope: .general) { received = $0 }
        #expect(received == .success(.text("hi")))

        loader.stubbedResult = .success(.url("https://example.com"))
        useCase.execute(.url, scope: .general) { received = $0 }
        #expect(received == .success(.url("https://example.com")))
    }

    @Test(arguments: [
        ClipboardError.noMatchingItem,
        ClipboardError.unexpectedType,
        ClipboardError.cancelled
    ])
    func executePropagatesEachErrorKind(_ error: ClipboardError) {
        let loader = MockClipboardItemLoader()
        loader.stubbedResult = .failure(error)
        let useCase = LoadItemUseCase(loader: loader)
        var received: Result<ClipboardLoadedItem, ClipboardError>?
        useCase.execute(.text, scope: .general) { received = $0 }
        #expect(received == .failure(error))
    }

    @Test func tokenCancelIncrementsLoaderCancelCount() {
        let loader = MockClipboardItemLoader()
        let useCase = LoadItemUseCase(loader: loader)
        let token = useCase.execute(.text, scope: .general) { _ in }
        token.cancel()
        #expect(loader.lastToken.cancelCallCount == 1)
    }
}
