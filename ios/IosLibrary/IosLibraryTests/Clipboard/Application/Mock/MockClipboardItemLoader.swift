//
//  MockClipboardItemLoader.swift
//  IosLibraryTests
//

import Foundation
@testable import IosLibrary

@MainActor
final class MockClipboardLoadToken: ClipboardLoadToken {
    private(set) var cancelCallCount = 0
    func cancel() { cancelCallCount += 1 }
}

@MainActor
final class MockClipboardItemLoader: ClipboardItemLoader {
    var stubbedResult: Result<ClipboardLoadedItem, ClipboardError> = .success(.text("mock"))
    private(set) var loadCallCount = 0
    private(set) var cancelAllCallCount = 0
    private(set) var lastRequest: ClipboardLoadRequest?
    let lastToken = MockClipboardLoadToken()

    /// When true, `load` does not call `completion` synchronously; the test must call
    /// `deliver(_:)` manually to simulate an async provider callback.
    var deliversManually = false
    private var pendingCompletion: ((Result<ClipboardLoadedItem, ClipboardError>) -> Void)?

    func load(
        _ request: ClipboardLoadRequest,
        scope: PasteboardScope,
        completion: @escaping (Result<ClipboardLoadedItem, ClipboardError>) -> Void
    ) -> any ClipboardLoadToken {
        loadCallCount += 1
        lastRequest = request
        if deliversManually {
            pendingCompletion = completion
        } else {
            completion(stubbedResult)
        }
        return lastToken
    }

    func deliver(_ result: Result<ClipboardLoadedItem, ClipboardError>) {
        pendingCompletion?(result)
        pendingCompletion = nil
    }

    func cancelAll() {
        cancelAllCallCount += 1
    }
}
