//
//  NotificationQueryUseCasesTests.swift
//  MacLibraryTests
//
//  Created by Kim Jong Hyun on 2026/05/09.
//
import Testing
@testable import MacLibrary

struct NotificationQueryUseCasesTests {

    private func makeUseCase(repo: MockNotificationRepository) -> NotificationQueryUseCases {
        NotificationQueryUseCases(repository: repo)
    }

    // MARK: - getDelivered

    @Test func getDeliveredSuccessReturnsEmpty() {
        let repo = MockNotificationRepository()
        let useCase = makeUseCase(repo: repo)
        var notifications: [ActiveNotification]?
        useCase.getDelivered { r in
            if case .success(let list) = r { notifications = list }
        }
        #expect(notifications != nil)
        #expect(notifications?.isEmpty == true)
    }

    @Test func getDeliveredPropagatesQueryFailure() {
        let repo = MockNotificationRepository()
        repo.shouldFail = true
        repo.stubError = .queryFailed(underlying: NSError(domain: "t", code: 0))
        let useCase = makeUseCase(repo: repo)
        var errorCode: Int?
        useCase.getDelivered { r in
            if case .failure(let e) = r { errorCode = e.errorCode }
        }
        #expect(errorCode == 1203)
    }

    // MARK: - removeDelivered

    @Test func removeDeliveredCallsRepositoryWithIdentifier() {
        let repo = MockNotificationRepository()
        let useCase = makeUseCase(repo: repo)
        useCase.removeDelivered(identifier: "notif-123")
        #expect(repo.removeDeliveredCallCount == 1)
        #expect(repo.removeDeliveredIdentifiers == ["notif-123"])
    }

    // MARK: - removeAllDelivered

    @Test func removeAllDeliveredCallsRepository() {
        let repo = MockNotificationRepository()
        let useCase = makeUseCase(repo: repo)
        useCase.removeAllDelivered()
        #expect(repo.removeAllDeliveredCallCount == 1)
    }
}
