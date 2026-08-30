//
//  MacClipboardManagerTests.swift
//  MacLibraryTests
//

import Testing
import Foundation
@testable import MacLibrary

@Suite("MacClipboardManager")
@MainActor
struct MacClipboardManagerTests {

    private let text = "public.utf8-plain-text"

    private func makeManager() -> (MacClipboardManager, MockClipboardRepository,
                                   MockClipboardPromiseRegistry, ClipboardSystemCoordinator) {
        let repository = MockClipboardRepository()
        let registry = MockClipboardPromiseRegistry()
        let snapshotter = MockFilePromiseSnapshotter()
        let coordinator = ClipboardSystemCoordinator(
            snapshotter: snapshotter,
            stagingBase: URL(filePath: "/tmp/ClipboardManagerTests/\(UUID().uuidString)"))
        let useCases = ClipboardUseCases(repository: repository,
                                         registry: registry,
                                         snapshotter: snapshotter,
                                         typeValidator: MockClipboardTypeIdentifierValidating())
        let manager = MacClipboardManager(coordinator: coordinator,
                                          useCases: useCases)
        return (manager, repository, registry, coordinator)
    }

    private func sample() -> ClipboardContent {
        ClipboardContent(items: [ClipboardItemData(representations: [text: Data("v".utf8)])])
    }

    // MARK: - Dependency injection order

    @Test("construction attaches the stale query, closing the dependency cycle")
    func initAttachesStaleQuery() {
        let (_, _, _, coordinator) = makeManager()
        // The coordinator cannot hold the repository, so the query arrives last. Until it does
        // the stale check is inert (R6-H3).
        #expect(coordinator.isStaleTimerRunning)
    }

    @Test("the attached query reaches the repository")
    func staleQueryReachesRepository() {
        let (_, repository, _, coordinator) = makeManager()
        let before = repository.changeCountCallCount

        let handle = coordinator.reserveFilePromiseHandle()
        _ = coordinator.registerFilePromise(
            FilePromiseRequest(fileTypeIdentifier: "public.plain-text", fileName: "n.txt",
                               source: .writer { _ in }),
            reserved: handle, stagingURL: nil)
        coordinator.activateFilePromise(handle,
                                        ownership: PasteboardOwnership(scope: .general, changeCount: 0))
        coordinator.checkForStalePromises()

        #expect(repository.changeCountCallCount == before + 1)
    }

    @Test("the default object graph builds without a cycle")
    func defaultGraphBuilds() {
        // The convenience initializer fixes the construction order. If it were wrong this
        // would deadlock or trap rather than fail an assertion.
        _ = MacClipboardManager()
    }

    // MARK: - Native async form

    @Test("copy returns the ownership")
    func copyReturnsOwnership() async throws {
        let (manager, repository, _, _) = makeManager()
        repository.stubbedOwnership = PasteboardOwnership(scope: .general, changeCount: 5)

        let ownership = try await manager.copy(sample())

        #expect(ownership.changeCount == 5)
        #expect(repository.writeCallCount == 1)
    }

    @Test("copy defaults to the general pasteboard and localOnly")
    func copyDefaults() async throws {
        let (manager, repository, _, _) = makeManager()
        _ = try await manager.copy(sample())
        #expect(repository.lastScope == .general)
        #expect(repository.lastOptions?.localOnly == true)
    }

    @Test("a native call throws the domain error unchanged")
    func nativeThrowsDomainError() async throws {
        let (manager, repository, _, _) = makeManager()
        repository.shouldFail = .writeRejected

        await #expect(throws: ClipboardError.writeRejected) {
            _ = try await manager.copy(self.sample())
        }
    }

    @Test("readData reports a missing type as nil")
    func readDataMissingIsNil() async throws {
        let (manager, repository, _, _) = makeManager()
        repository.stubbedData = nil
        #expect(try await manager.readData(utType: text) == nil)
    }

    // MARK: - Callback form

    @Test("a successful callback reports (true, value, 0, nil)")
    func callbackSuccessShape() {
        let (manager, repository, _, _) = makeManager()
        repository.stubbedClearChangeCount = 11
        var received: (Bool, Int?, Int, String?)?

        manager.clear(scope: .general) { received = ($0, $1, $2, $3) }

        #expect(received?.0 == true)
        #expect(received?.1 == 11)
        #expect(received?.2 == 0)
        #expect(received?.3 == nil)
    }

    @Test("a failing callback reports the domain code and message")
    func callbackFailureShape() {
        let (manager, repository, _, _) = makeManager()
        repository.shouldFail = .writeRejected
        var received: (Bool, PasteboardOwnership?, Int, String?)?

        manager.copy(sample()) { received = ($0, $1, $2, $3) }

        // This is the only place a ClipboardError becomes a number. The bridge forwards what
        // it is handed and never converts again (R6-M7).
        #expect(received?.0 == false)
        #expect(received?.1 == nil)
        #expect(received?.2 == ClipboardError.writeRejected.errorCode)
        #expect(received?.3 == ClipboardError.writeRejected.errorMessage)
    }

    @Test("the void callback omits the value argument")
    func voidCallbackShape() {
        let (manager, repository, _, _) = makeManager()
        repository.shouldFail = .cannotReleaseStandardPasteboard(name: "general")
        var received: (Bool, Int, String?)?

        manager.removePasteboard(.general) { received = ($0, $1, $2) }

        #expect(received?.0 == false)
        #expect(received?.1 == 1508)
        #expect(received?.2?.contains("general") == true)
    }

    @Test("a nil callback does not trap")
    func nilCallbackIsSafe() {
        let (manager, _, _, _) = makeManager()
        manager.clear(scope: .general, completion: nil)
        manager.removePasteboard(.unique("x"), completion: nil)
    }

    @Test("readData reports a missing type as success with a nil value")
    func readDataCallbackMissingType() {
        let (manager, repository, _, _) = makeManager()
        repository.stubbedData = nil
        var received: (Bool, Data?, Int, String?)?

        manager.readData(utType: text) { received = ($0, $1, $2, $3) }

        // Absence is not a failure, so the callback must not report an error code.
        #expect(received?.0 == true)
        #expect(received?.1 == nil)
        #expect(received?.2 == 0)
    }

    @Test("an async operation's callback is delivered on the main actor")
    func asyncCallbackIsMainActor() async throws {
        let (manager, _, _, _) = makeManager()
        var wasMainActor = false
        var delivered = false

        manager.detectMetadata(scope: .general) { isSuccess, _, _, _ in
            // CT-04: the callback form exists for the bridge, which calls from arbitrary
            // threads. The delivery actor must not depend on the caller's.
            wasMainActor = Thread.isMainThread
            delivered = isSuccess
        }
        // The detection operations hop through a Task, so give it a turn.
        try await Task.sleep(for: .milliseconds(50))

        #expect(delivered)
        #expect(wasMainActor)
    }

    @Test("an async operation reports its error through the callback")
    func asyncCallbackFailure() async throws {
        let (manager, repository, _, _) = makeManager()
        repository.shouldFail = .detectionDenied
        var code: Int?

        manager.detectValues([.links], scope: .general) { _, _, errorCode, _ in code = errorCode }
        try await Task.sleep(for: .milliseconds(50))

        #expect(code == ClipboardError.detectionDenied.errorCode)
    }

    @Test("an empty pattern set is rejected before the port is reached")
    func emptyPatternsRejected() async throws {
        let (manager, _, _, _) = makeManager()
        await #expect(throws: ClipboardError.emptyDetectionPatterns) {
            _ = try await manager.detectPatterns([])
        }
    }

    // MARK: - Synchronous control operations

    @Test("accessBehavior is synchronous")
    func accessBehaviorIsSynchronous() throws {
        let (manager, _, _, _) = makeManager()
        // An immediate control query, exempt from the async throws rule (common.md).
        #expect(try manager.accessBehavior() == .unavailable)
    }

    @Test("checkForegroundChange reports the first look as a change")
    func foregroundFirstLook() throws {
        let (manager, repository, _, _) = makeManager()
        repository.stubbedChangeCount = 3
        #expect(try manager.checkForegroundChange())
        #expect(!(try manager.checkForegroundChange()))
    }

    @Test("releasing and cancelling are idempotent and never throw")
    func idempotentControls() {
        let (manager, _, registry, _) = makeManager()
        let promise = FilePromiseHandle()
        let receipt = FilePromiseReceiptHandle()

        manager.releaseFilePromise(promise)
        manager.releaseFilePromise(promise)
        manager.cancelReceiveFilePromises(receipt)
        manager.cancelReceiveFilePromises(receipt)

        #expect(registry.releaseFilePromiseCallCount == 2)
        #expect(registry.cancelReceiptCallCount == 2)
    }
}
