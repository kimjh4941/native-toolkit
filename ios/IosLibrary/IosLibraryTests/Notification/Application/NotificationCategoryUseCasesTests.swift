//
//  NotificationCategoryUseCasesTests.swift
//  IosLibraryTests
//

import Foundation
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

    // MARK: - enqueue (design S-P28)

    /// The synchronous forms queue on the port inside the call and complete after the change.
    @Test func enqueueQueuesOnThePortInsideTheCall() async {
        let center = FakeCategoryCenter()
        let repository = NotificationRepositoryImpl(requestCenter: FakeRequestCenter(),
                                                    categoryQueue: NotificationCategoryQueue(center: center))
        let register = RegisterNotificationCategoryUseCase(repository: repository)
        let remove = RemoveNotificationCategoryUseCase(repository: repository)

        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            register.enqueue(makeCategory()) { center.note("registered") }
            remove.enqueue(identifier: "cat1") {
                center.note("removed")
                continuation.resume()
            }
        }

        #expect(center.log == ["read", "write +cat1", "read", "registered", "read", "write -cat1", "read", "removed"])
    }
}
