//
//  ShareUseCasesTests.swift
//  MacLibraryTests
//
import Testing
@testable import MacLibrary

struct ShareUseCasesTests {

    // MARK: - SharePickerUseCase

    @Test func pickerExecuteReturnsStubbedResultAndCallsRepositoryOnce() async throws {
        let repo = MockShareRepository()
        repo.stubbedResult = ShareResult(completed: true, serviceName: "Mail")
        let useCase = SharePickerUseCase(repository: repo)

        let result = try await useCase.execute(content: ShareContent(items: [.text("hi")]))

        #expect(repo.presentPickerCallCount == 1)
        #expect(result.completed == true)
        #expect(result.serviceName == "Mail")
    }

    @Test func pickerExecutePropagatesRepositoryError() async {
        let repo = MockShareRepository()
        repo.shouldFail = true
        repo.errorToThrow = .noAnchorView
        let useCase = SharePickerUseCase(repository: repo)

        await #expect(throws: ShareError.self) {
            _ = try await useCase.execute(content: ShareContent(items: [.text("hi")]))
        }
    }

    @Test func pickerExecuteThrowsNoValidItemsForEmptyItems() async {
        let repo = MockShareRepository()
        let useCase = SharePickerUseCase(repository: repo)

        await #expect(throws: ShareError.self) {
            _ = try await useCase.execute(content: ShareContent(items: []))
        }
        #expect(repo.presentPickerCallCount == 0)
    }

    // MARK: - ShareServiceUseCase

    @Test func serviceExecuteReturnsStubbedResult() async throws {
        let repo = MockShareRepository()
        repo.stubbedResult = ShareResult(completed: true, serviceName: "AirDrop")
        let useCase = ShareServiceUseCase(repository: repo)

        let result = try await useCase.execute(content: ShareContent(items: [.text("hi")]),
                                                serviceName: "com.apple.share.System.airdrop")

        #expect(repo.performServiceCallCount == 1)
        #expect(repo.lastServiceName == "com.apple.share.System.airdrop")
        #expect(result.serviceName == "AirDrop")
    }

    @Test func serviceExecuteThrowsServiceUnavailableForEmptyName() async {
        let repo = MockShareRepository()
        let useCase = ShareServiceUseCase(repository: repo)

        await #expect(throws: ShareError.self) {
            _ = try await useCase.execute(content: ShareContent(items: [.text("hi")]), serviceName: "  ")
        }
        #expect(repo.performServiceCallCount == 0)
    }

    @Test func serviceExecuteThrowsNoValidItemsForEmptyItems() async {
        let repo = MockShareRepository()
        let useCase = ShareServiceUseCase(repository: repo)

        await #expect(throws: ShareError.self) {
            _ = try await useCase.execute(content: ShareContent(items: []), serviceName: "com.apple.share.Mail.compose")
        }
        #expect(repo.performServiceCallCount == 0)
    }

    // MARK: - ShareServiceQueryUseCase

    @Test func canPerformReturnsStubbedValue() async throws {
        let repo = MockShareRepository()
        repo.stubbedCanPerform = true
        let useCase = ShareServiceQueryUseCase(repository: repo)

        let canPerform = try await useCase.canPerform(content: ShareContent(items: [.text("hi")]),
                                                       serviceName: "com.apple.share.Mail.compose")

        #expect(canPerform == true)
        #expect(repo.canPerformServiceCallCount == 1)
    }

    @Test func canPerformReturnsFalseForEmptyItemsWithoutCallingRepository() async throws {
        let repo = MockShareRepository()
        let useCase = ShareServiceQueryUseCase(repository: repo)

        let canPerform = try await useCase.canPerform(content: ShareContent(items: []),
                                                       serviceName: "com.apple.share.Mail.compose")

        #expect(canPerform == false)
        #expect(repo.canPerformServiceCallCount == 0)
    }
}
