//
//  MockClipboardPromiseRegistry.swift
//  MacLibraryTests
//

import Foundation
@testable import MacLibrary

/// Records registrations and releases so a test can prove the promise transaction rolls back.
@MainActor
final class MockClipboardPromiseRegistry: ClipboardPromiseRegistry {

    // MARK: Recorded calls

    private(set) var registerLazyProviderCallCount = 0
    private(set) var releaseLazyProviderCallCount = 0
    private(set) var reserveFilePromiseHandleCallCount = 0
    private(set) var stagingRootCallCount = 0
    private(set) var registerFilePromiseCallCount = 0
    private(set) var activateFilePromiseCallCount = 0
    private(set) var releaseFilePromiseCallCount = 0
    private(set) var reserveReceiptHandleCallCount = 0
    private(set) var registerReceiptCallCount = 0
    private(set) var cancelReceiptCallCount = 0
    private(set) var terminateReceiptWithoutDeliveryCallCount = 0
    private(set) var discardReceiptAfterStartFailureCallCount = 0
    private(set) var finalizeReceiptCallCount = 0

    private(set) var lastRequest: FilePromiseRequest?
    private(set) var lastReservedHandle: FilePromiseHandle?
    private(set) var lastStagingURL: URL??
    private(set) var lastOwnership: PasteboardOwnership?
    private(set) var releasedHandles: [FilePromiseHandle] = []
    private(set) var lastPolicy: FilePromiseReceiptPolicy?
    private(set) var cancelledReceipts: [FilePromiseReceiptHandle] = []

    /// Order of the transaction steps, so a test can assert that a write never happens before
    /// the registration it depends on.
    private(set) var callOrder: [String] = []

    // MARK: Stubs

    var stubbedFilePromiseHandle = FilePromiseHandle()
    var stubbedReceiptHandle = FilePromiseReceiptHandle()
    var stubbedStagingRoot = URL(filePath: "/tmp/ClipboardPromise/mock")

    // MARK: Lazy data providers

    func registerLazyProvider(types: [String],
                              provide: @escaping @Sendable (String) -> Data?) -> PasteboardPromiseHandle {
        registerLazyProviderCallCount += 1
        callOrder.append("registerLazyProvider")
        return PasteboardPromiseHandle()
    }

    func releaseLazyProvider(_ handle: PasteboardPromiseHandle) {
        releaseLazyProviderCallCount += 1
        callOrder.append("releaseLazyProvider")
    }

    // MARK: File promise providers

    func reserveFilePromiseHandle() -> FilePromiseHandle {
        reserveFilePromiseHandleCallCount += 1
        callOrder.append("reserveFilePromiseHandle")
        return stubbedFilePromiseHandle
    }

    func stagingRoot(for handle: FilePromiseHandle) -> URL {
        stagingRootCallCount += 1
        callOrder.append("stagingRoot")
        return stubbedStagingRoot
    }

    func registerFilePromise(_ request: FilePromiseRequest,
                             reserved: FilePromiseHandle,
                             stagingURL: URL?) -> FilePromiseHandle {
        registerFilePromiseCallCount += 1
        callOrder.append("registerFilePromise")
        lastRequest = request
        lastReservedHandle = reserved
        lastStagingURL = .some(stagingURL)
        return reserved
    }

    func activateFilePromise(_ handle: FilePromiseHandle, ownership: PasteboardOwnership) {
        activateFilePromiseCallCount += 1
        callOrder.append("activateFilePromise")
        lastOwnership = ownership
    }

    func releaseFilePromise(_ handle: FilePromiseHandle) {
        releaseFilePromiseCallCount += 1
        callOrder.append("releaseFilePromise")
        releasedHandles.append(handle)
    }

    // MARK: Receive sessions

    func reserveReceiptHandle() -> FilePromiseReceiptHandle {
        reserveReceiptHandleCallCount += 1
        callOrder.append("reserveReceiptHandle")
        return stubbedReceiptHandle
    }

    func registerReceipt(reserved: FilePromiseReceiptHandle,
                         policy: FilePromiseReceiptPolicy,
                         onEvent: @escaping @MainActor (FilePromiseReceiptEvent) -> Void) {
        registerReceiptCallCount += 1
        callOrder.append("registerReceipt")
        lastPolicy = policy
    }

    func cancelReceipt(_ handle: FilePromiseReceiptHandle) {
        cancelReceiptCallCount += 1
        callOrder.append("cancelReceipt")
        cancelledReceipts.append(handle)
    }

    func terminateReceiptWithoutDelivery(_ handle: FilePromiseReceiptHandle) {
        terminateReceiptWithoutDeliveryCallCount += 1
        callOrder.append("terminateReceiptWithoutDelivery")
    }

    func discardReceiptAfterStartFailure(_ handle: FilePromiseReceiptHandle) {
        discardReceiptAfterStartFailureCallCount += 1
        callOrder.append("discardReceiptAfterStartFailure")
    }

    func finalizeReceipt(_ handle: FilePromiseReceiptHandle) {
        finalizeReceiptCallCount += 1
        callOrder.append("finalizeReceipt")
    }
}
