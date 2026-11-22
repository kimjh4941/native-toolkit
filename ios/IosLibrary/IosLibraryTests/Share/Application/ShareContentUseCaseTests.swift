//
//  ShareContentUseCaseTests.swift
//  IosLibraryTests
//

import Testing
@testable import IosLibrary

@MainActor
struct ShareContentUseCaseTests {

    private func makeContent(items: [ShareItem] = [.text("hello")]) -> ShareContent {
        ShareContent(items: items)
    }

    @Test func executeCallsRepositoryAndReturnsResult() async throws {
        let repo = MockShareRepository()
        let useCase = ShareContentUseCase(repository: repo)
        let result = try await useCase.execute(content: makeContent())
        #expect(repo.presentCallCount == 1)
        #expect(result.completed == repo.stubbedResult.completed)
        #expect(result.activityType == repo.stubbedResult.activityType)
    }

    @Test func executePropagatesRepositoryError() async {
        let repo = MockShareRepository()
        repo.shouldFail = true
        repo.errorToThrow = .noRootViewController
        let useCase = ShareContentUseCase(repository: repo)
        await #expect(throws: ShareError.self) {
            try await useCase.execute(content: makeContent())
        }
    }

    @Test func executeThrowsNoValidItemsWhenEmpty() async {
        let repo = MockShareRepository()
        let useCase = ShareContentUseCase(repository: repo)
        await #expect(throws: ShareError.self) {
            try await useCase.execute(content: makeContent(items: []))
        }
        #expect(repo.presentCallCount == 0)
    }

    // MARK: - presenter (8.2)

    /// The form without a presenter keeps the search it always used.
    @Test func executeWithoutAPresenterUsesFirstActiveScene() async throws {
        let repo = MockShareRepository()
        let useCase = ShareContentUseCase(repository: repo)
        _ = try await useCase.execute(content: makeContent())
        #expect(repo.presenters == ["firstActiveScene"])
    }

    @Test func executePassesThePresenterOn() async throws {
        let repo = MockShareRepository()
        let useCase = ShareContentUseCase(repository: repo)
        _ = try await useCase.execute(content: makeContent(), presenter: .foreground)
        _ = try await useCase.execute(content: makeContent(), presenter: .viewController { nil })
        #expect(repo.presenters == ["foreground", "viewController"])
    }

    @Test func executeWithAPresenterThrowsNoValidItemsWhenEmpty() async {
        let repo = MockShareRepository()
        let useCase = ShareContentUseCase(repository: repo)
        await #expect(throws: ShareError.noValidItems) {
            try await useCase.execute(content: makeContent(items: []), presenter: .foreground)
        }
        #expect(repo.presentCallCount == 0)
    }
}
