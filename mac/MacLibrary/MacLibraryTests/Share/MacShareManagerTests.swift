//
//  MacShareManagerTests.swift
//  MacLibraryTests
//
import Testing
@testable import MacLibrary

struct MacShareManagerTests {

    // MARK: - Helpers

    private func awaitShare(
        manager: MacShareManager,
        content: ShareContent
    ) async -> (Bool, Bool, String?, String?) {
        await withCheckedContinuation { continuation in
            manager.share(content: content) { isSuccess, completed, serviceName, errorMessage in
                continuation.resume(returning: (isSuccess, completed, serviceName, errorMessage))
            }
        }
    }

    private func awaitShareViaService(
        manager: MacShareManager,
        content: ShareContent,
        serviceName: String
    ) async -> (Bool, Bool, String?, String?) {
        await withCheckedContinuation { continuation in
            manager.share(content: content, serviceName: serviceName) { isSuccess, completed, resultServiceName, errorMessage in
                continuation.resume(returning: (isSuccess, completed, resultServiceName, errorMessage))
            }
        }
    }

    // MARK: - share(content:completion:) — picker

    @Test func shareCompletionSucceedsWithChosenService() async {
        let repo = MockShareRepository()
        repo.stubbedResult = ShareResult(completed: true, serviceName: "Mail")
        let manager = MacShareManager(repository: repo)

        let (isSuccess, completed, serviceName, errorMessage) = await awaitShare(
            manager: manager, content: ShareContent(items: [.text("hi")]))

        #expect(isSuccess == true)
        #expect(completed == true)
        #expect(serviceName == "Mail")
        #expect(errorMessage == nil)
    }

    @Test func shareCompletionReflectsCancellation() async {
        let repo = MockShareRepository()
        repo.stubbedResult = ShareResult(completed: false, serviceName: nil)
        let manager = MacShareManager(repository: repo)

        let (isSuccess, completed, serviceName, errorMessage) = await awaitShare(
            manager: manager, content: ShareContent(items: [.text("hi")]))

        #expect(isSuccess == true)
        #expect(completed == false)
        #expect(serviceName == nil)
        #expect(errorMessage == nil)
    }

    @Test func shareCompletionReturnsFailureMessageOnError() async {
        let repo = MockShareRepository()
        repo.shouldFail = true
        repo.errorToThrow = .noAnchorView
        let manager = MacShareManager(repository: repo)

        let (isSuccess, completed, serviceName, errorMessage) = await awaitShare(
            manager: manager, content: ShareContent(items: [.text("hi")]))

        #expect(isSuccess == false)
        #expect(completed == false)
        #expect(serviceName == nil)
        #expect(errorMessage == ShareError.noAnchorView.errorMessage)
    }

    // MARK: - share(content:serviceName:completion:) — direct

    @Test func shareViaServiceCompletionSucceeds() async {
        let repo = MockShareRepository()
        repo.stubbedResult = ShareResult(completed: true, serviceName: "AirDrop")
        let manager = MacShareManager(repository: repo)

        let (isSuccess, completed, serviceName, errorMessage) = await awaitShareViaService(
            manager: manager,
            content: ShareContent(items: [.text("hi")]),
            serviceName: "com.apple.share.System.airdrop")

        #expect(isSuccess == true)
        #expect(completed == true)
        #expect(serviceName == "AirDrop")
        #expect(errorMessage == nil)
    }

    @Test func shareViaServiceCompletionReturnsFailureMessageOnError() async {
        let repo = MockShareRepository()
        repo.shouldFail = true
        repo.errorToThrow = .serviceUnavailable(name: "bad.name")
        let manager = MacShareManager(repository: repo)

        let (isSuccess, completed, serviceName, errorMessage) = await awaitShareViaService(
            manager: manager,
            content: ShareContent(items: [.text("hi")]),
            serviceName: "bad.name")

        #expect(isSuccess == false)
        #expect(completed == false)
        #expect(serviceName == nil)
        #expect(errorMessage == ShareError.serviceUnavailable(name: "bad.name").errorMessage)
    }

    // MARK: - async throws form

    @Test func shareAsyncReturnsResult() async throws {
        let repo = MockShareRepository()
        repo.stubbedResult = ShareResult(completed: true, serviceName: "Mail")
        let manager = MacShareManager(repository: repo)

        let result = try await manager.share(content: ShareContent(items: [.text("hi")]))

        #expect(result.completed == true)
        #expect(result.serviceName == "Mail")
    }

    @Test func shareAsyncThrowsTypedError() async {
        let repo = MockShareRepository()
        repo.shouldFail = true
        repo.errorToThrow = .noValidItems
        let manager = MacShareManager(repository: repo)

        await #expect(throws: ShareError.self) {
            _ = try await manager.share(content: ShareContent(items: [.text("hi")]))
        }
    }

    @Test func canPerformReturnsStubbedValue() async throws {
        let repo = MockShareRepository()
        repo.stubbedCanPerform = true
        let manager = MacShareManager(repository: repo)

        let canPerform = try await manager.canPerform(content: ShareContent(items: [.text("hi")]),
                                                       serviceName: "com.apple.share.Mail.compose")
        #expect(canPerform == true)
    }
}
