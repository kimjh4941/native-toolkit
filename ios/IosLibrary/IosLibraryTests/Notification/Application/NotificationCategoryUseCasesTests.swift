//
//  NotificationCategoryUseCasesTests.swift
//  IosLibraryTests
//

import Testing
@testable import IosLibrary

struct NotificationCategoryUseCasesTests {

    private func makeCategory() -> NotificationCategory {
        NotificationCategory(identifier: "cat1")
    }

    // MARK: - RegisterNotificationCategoryUseCase

    @Test func registerCallsRepository() async {
        let repo = MockNotificationRepository()
        let useCase = RegisterNotificationCategoryUseCase(repository: repo)
        await useCase.execute(makeCategory())
        #expect(repo.registerCategoryCallCount == 1)
    }

    // MARK: - RemoveNotificationCategoryUseCase

    @Test func removeCallsRepository() async {
        let repo = MockNotificationRepository()
        let useCase = RemoveNotificationCategoryUseCase(repository: repo)
        await useCase.execute(identifier: "cat1")
        #expect(repo.removeCategoryCallCount == 1)
    }
}
