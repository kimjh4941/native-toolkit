//
//  NotificationDispatchUseCasesTests.swift
//  MacLibraryTests
//
//  Created by Kim Jong Hyun on 2026/05/09.
//
import Testing
@testable import MacLibrary

struct NotificationDispatchUseCasesTests {

    private func makeUseCase(repo: MockNotificationRepository) -> NotificationDispatchUseCases {
        NotificationDispatchUseCases(repository: repo)
    }

    private func validContent(id: String = "test-id") -> NotificationContent {
        NotificationContent(id: id, title: "Hello")
    }

    // MARK: - show: success

    @Test func showSuccessCallsAdd() async throws {
        let repo = MockNotificationRepository()
        let useCase = makeUseCase(repo: repo)
        var result: Result<Void, NotificationDomainError>?
        useCase.show(content: validContent(), trigger: .immediate) { result = $0 }
        #expect(repo.addCallCount == 1)
        if case .success = result! {} else { Issue.record("Expected success") }
    }

    // MARK: - show: invalid content

    @Test func showFailsOnEmptyTitle() {
        let repo = MockNotificationRepository()
        let useCase = makeUseCase(repo: repo)
        let content = NotificationContent(id: "id", title: "")
        var errorCode: Int?
        useCase.show(content: content, trigger: .immediate) { r in
            if case .failure(let e) = r { errorCode = e.errorCode }
        }
        #expect(errorCode == 1101)
        #expect(repo.addCallCount == 0)
    }

    @Test func showFailsOnInvalidId() {
        let repo = MockNotificationRepository()
        let useCase = makeUseCase(repo: repo)
        let content = NotificationContent(id: "invalid id!", title: "Title")
        var errorCode: Int?
        useCase.show(content: content, trigger: .immediate) { r in
            if case .failure(let e) = r { errorCode = e.errorCode }
        }
        #expect(errorCode == 1101)
    }

    @Test func showFailsOnTriggerBelowOneSecond() {
        let repo = MockNotificationRepository()
        let useCase = makeUseCase(repo: repo)
        var errorCode: Int?
        useCase.show(content: validContent(), trigger: .timeInterval(seconds: 0.5, repeats: false)) { r in
            if case .failure(let e) = r { errorCode = e.errorCode }
        }
        #expect(errorCode == 1102)
    }

    // MARK: - show: repository failure

    @Test func showPropagatesRepositoryError() {
        let repo = MockNotificationRepository()
        repo.shouldFail = true
        repo.stubError = .addFailed(underlying: NSError(domain: "t", code: 0))
        let useCase = makeUseCase(repo: repo)
        var errorCode: Int?
        useCase.show(content: validContent(), trigger: .immediate) { r in
            if case .failure(let e) = r { errorCode = e.errorCode }
        }
        #expect(errorCode == 1201)
    }

    // MARK: - update: success

    @Test func updateSuccessCallsAdd() {
        let repo = MockNotificationRepository()
        let useCase = makeUseCase(repo: repo)
        var result: Result<Void, NotificationDomainError>?
        useCase.update(identifier: "test-id", content: validContent(), trigger: .immediate) { result = $0 }
        #expect(repo.addCallCount == 1)
        if case .success = result! {} else { Issue.record("Expected success") }
    }

    // MARK: - update: invalid content

    @Test func updateFailsOnInvalidContent() {
        let repo = MockNotificationRepository()
        let useCase = makeUseCase(repo: repo)
        let bad = NotificationContent(id: "id", title: "")
        var errorCode: Int?
        useCase.update(identifier: "id", content: bad, trigger: .immediate) { r in
            if case .failure(let e) = r { errorCode = e.errorCode }
        }
        #expect(errorCode == 1101)
        #expect(repo.addCallCount == 0)
    }
}
