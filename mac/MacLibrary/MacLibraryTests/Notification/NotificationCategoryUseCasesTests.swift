//
//  NotificationCategoryUseCasesTests.swift
//  MacLibraryTests
//
//  Created by Kim Jong Hyun on 2026/05/09.
//
import Testing
@testable import MacLibrary

struct NotificationCategoryUseCasesTests {

    private func makeUseCase(repo: MockNotificationRepository) -> NotificationCategoryUseCases {
        NotificationCategoryUseCases(repository: repo)
    }

    private func validCategory(id: String = "cat-1") -> NotificationCategory {
        let action = NotificationAction(id: "act-1", title: "Open")
        return NotificationCategory(id: id, actions: [action])
    }

    // MARK: - registerCategory: success

    @Test func registerCategoryCallsSetCategories() {
        let repo = MockNotificationRepository()
        let useCase = makeUseCase(repo: repo)
        var result: Result<Void, NotificationDomainError>?
        useCase.registerCategory(validCategory()) { result = $0 }
        #expect(repo.setCategoriesCallCount == 1)
        #expect(repo.lastSetCategories.count == 1)
        if case .success = result! {} else { Issue.record("Expected success") }
    }

    // MARK: - registerCategory: invalid id

    @Test func registerCategoryFailsOnEmptyId() {
        let repo = MockNotificationRepository()
        let useCase = makeUseCase(repo: repo)
        let category = NotificationCategory(id: "", actions: [])
        var errorCode: Int?
        useCase.registerCategory(category) { r in
            if case .failure(let e) = r { errorCode = e.errorCode }
        }
        #expect(errorCode == 1103)
        #expect(repo.setCategoriesCallCount == 0)
    }

    // MARK: - removeCategory: success

    @Test func removeCategoryRemovesFromRegisteredSet() {
        let repo = MockNotificationRepository()
        let useCase = makeUseCase(repo: repo)
        // Register first
        useCase.registerCategory(validCategory(id: "cat-2")) { _ in }
        #expect(repo.lastSetCategories.count == 1)
        // Now remove
        var result: Result<Void, NotificationDomainError>?
        useCase.removeCategory(identifier: "cat-2") { result = $0 }
        #expect(repo.setCategoriesCallCount == 2)
        #expect(repo.lastSetCategories.isEmpty)
        if case .success = result! {} else { Issue.record("Expected success") }
    }

    // MARK: - removeCategory: empty id

    @Test func removeCategoryFailsOnEmptyId() {
        let repo = MockNotificationRepository()
        let useCase = makeUseCase(repo: repo)
        var errorCode: Int?
        useCase.removeCategory(identifier: "") { r in
            if case .failure(let e) = r { errorCode = e.errorCode }
        }
        #expect(errorCode == 1103)
    }
}
