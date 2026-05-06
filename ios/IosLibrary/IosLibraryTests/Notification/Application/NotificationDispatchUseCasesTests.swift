//
//  NotificationDispatchUseCasesTests.swift
//  IosLibraryTests
//

import Testing
@testable import IosLibrary

struct NotificationDispatchUseCasesTests {

    private func makeContent() -> NotificationContent {
        NotificationContent(id: "test-id", title: "Test")
    }

    // MARK: - ShowNotificationUseCase

    @Test func showCallsRepository() async throws {
        let repo = MockNotificationRepository()
        let useCase = ShowNotificationUseCase(repository: repo)
        try await useCase.execute(content: makeContent())
        #expect(repo.showCallCount == 1)
    }

    @Test func showThrowsOnFailure() async {
        let repo = MockNotificationRepository()
        repo.shouldFail = true
        let useCase = ShowNotificationUseCase(repository: repo)
        await #expect(throws: NotificationError.self) {
            try await useCase.execute(content: makeContent())
        }
    }

    // MARK: - UpdateNotificationUseCase

    @Test func updateCallsRepository() async throws {
        let repo = MockNotificationRepository()
        let useCase = UpdateNotificationUseCase(repository: repo)
        try await useCase.execute(identifier: "id1", content: makeContent(), trigger: nil)
        #expect(repo.updateCallCount == 1)
    }

    @Test func updateThrowsOnFailure() async {
        let repo = MockNotificationRepository()
        repo.shouldFail = true
        let useCase = UpdateNotificationUseCase(repository: repo)
        await #expect(throws: NotificationError.self) {
            try await useCase.execute(identifier: "id1", content: makeContent(), trigger: nil)
        }
    }

    // MARK: - CancelNotificationUseCase

    @Test func cancelCallsRepository() async {
        let repo = MockNotificationRepository()
        let useCase = CancelNotificationUseCase(repository: repo)
        await useCase.execute(identifier: "id1")
        #expect(repo.cancelCallCount == 1)
    }

    // MARK: - CancelAllNotificationsUseCase

    @Test func cancelAllCallsRepository() async {
        let repo = MockNotificationRepository()
        let useCase = CancelAllNotificationsUseCase(repository: repo)
        await useCase.execute()
        #expect(repo.cancelAllCallCount == 1)
    }

    // MARK: - RemoveDeliveredNotificationUseCase

    @Test func removeDeliveredCallsRepository() async {
        let repo = MockNotificationRepository()
        let useCase = RemoveDeliveredNotificationUseCase(repository: repo)
        await useCase.execute(identifier: "id1")
        #expect(repo.removeDeliveredCallCount == 1)
    }

    // MARK: - RemoveAllDeliveredNotificationsUseCase

    @Test func removeAllDeliveredCallsRepository() async {
        let repo = MockNotificationRepository()
        let useCase = RemoveAllDeliveredNotificationsUseCase(repository: repo)
        await useCase.execute()
        #expect(repo.removeAllDeliveredCallCount == 1)
    }
}
