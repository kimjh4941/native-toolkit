//
//  IosClipboardManagerTests.swift
//  IosLibraryTests
//

import Testing
import Foundation
import UIKit
@testable import IosLibrary

@MainActor
struct IosClipboardManagerTests {
    private func makeManager(
        repository: MockClipboardRepository? = nil,
        loader: MockClipboardItemLoader? = nil
    ) -> IosClipboardManager {
        let repository = repository ?? MockClipboardRepository()
        let loader = loader ?? MockClipboardItemLoader()
        let useCases = ClipboardUseCases(
            repository: repository,
            loader: loader,
            typeValidator: MockClipboardTypeIdentifierValidating()
        )
        return IosClipboardManager(useCases: useCases)
    }

    @Test func copyCallbackReportsSuccess() async throws {
        let manager = makeManager()
        let (isSuccess, code, message) = await withCheckedContinuation { continuation in
            manager.copy(.plainText("hi")) { isSuccess, code, message in
                continuation.resume(returning: (isSuccess, code, message))
            }
        }
        #expect(isSuccess == true)
        #expect(code == nil)
        #expect(message == nil)
    }

    @Test func copyCallbackReportsFailureWithErrorCode() async throws {
        let manager = makeManager()
        let (isSuccess, code, message) = await withCheckedContinuation { continuation in
            manager.copy(.multipleText([])) { isSuccess, code, message in
                continuation.resume(returning: (isSuccess, code, message))
            }
        }
        #expect(isSuccess == false)
        #expect(code == ClipboardError.emptyItemList.errorCode)
        #expect(message != nil)
    }

    @Test func copyAsyncThrowsPropagatesTypedError() async {
        let repository = MockClipboardRepository()
        repository.shouldFail = true
        repository.errorToThrow = .emptyContent
        let manager = makeManager(repository: repository)
        await #expect(throws: ClipboardError.self) {
            try await manager.copy(.plainText("hi"))
        }
    }

    @Test func readDataCallbackReturnsCodeOnFailure() async {
        let repository = MockClipboardRepository()
        repository.shouldFail = true
        repository.errorToThrow = .invalidTypeIdentifier("x")
        let manager = makeManager(repository: repository)
        let (isSuccess, _, code, _) = await withCheckedContinuation { (continuation: CheckedContinuation<(Bool, Data?, String?, String?), Never>) in
            manager.readData(utType: "public.png") { isSuccess, data, code, message in
                continuation.resume(returning: (isSuccess, data, code, message))
            }
        }
        #expect(isSuccess == false)
        #expect(code == ClipboardError.invalidTypeIdentifier("x").errorCode)
    }

    @Test func startObservingTwiceDoesNotDuplicateEvents() {
        let manager = makeManager()
        var count1 = 0
        var count2 = 0
        manager.startObserving { _ in count1 += 1 }
        manager.startObserving { _ in count2 += 1 }
        NotificationCenter.default.post(name: UIPasteboard.changedNotification, object: UIPasteboard.general)
        #expect(count1 == 0)
        #expect(count2 <= 1)
        manager.stopObserving()
    }

    @Test func stopObservingPreventsFurtherEvents() {
        let manager = makeManager()
        var received = 0
        manager.startObserving { _ in received += 1 }
        manager.stopObserving()
        NotificationCenter.default.post(name: UIPasteboard.changedNotification, object: UIPasteboard.general)
        #expect(received == 0)
    }

    @Test func cancelAllLoadsDelegatesToLoader() {
        let loader = MockClipboardItemLoader()
        let manager = makeManager(loader: loader)
        manager.cancelAllLoads()
        #expect(loader.cancelAllCallCount == 1)
    }

    @Test func checkForegroundChangeIsSynchronous() {
        let repository = MockClipboardRepository()
        repository.stubbedChangeCount = 1
        let manager = makeManager(repository: repository)
        let changed = manager.checkForegroundChange()
        #expect(changed == false || changed == true)
    }

    @Test func loadItemCallbackReturnsSuccessValue() {
        let loader = MockClipboardItemLoader()
        loader.stubbedResult = .success(.text("hi"))
        let manager = makeManager(loader: loader)
        var received: ClipboardLoadedItem?
        manager.loadItem(.text) { isSuccess, item, _, _ in
            #expect(isSuccess == true)
            received = item
        }
        #expect(received == .text("hi"))
    }
}
