//
//  NotificationScheduleUseCasesTests.swift
//  IosLibraryTests
//

import Testing
@testable import IosLibrary

struct NotificationScheduleUseCasesTests {

    private func makeContent() -> NotificationContent {
        NotificationContent(id: "sched-id", title: "Scheduled")
    }

    private func makeTrigger() -> NotificationTrigger {
        .timeInterval(60, repeats: false)
    }

    // MARK: - ScheduleNotificationUseCase

    @Test func scheduleCallsRepository() async throws {
        let repo = MockNotificationRepository()
        let useCase = ScheduleNotificationUseCase(repository: repo)
        try await useCase.execute(content: makeContent(), trigger: makeTrigger(), identifier: "id1")
        #expect(repo.scheduleCallCount == 1)
    }

    @Test func scheduleThrowsOnFailure() async {
        let repo = MockNotificationRepository()
        repo.shouldFail = true
        let useCase = ScheduleNotificationUseCase(repository: repo)
        await #expect(throws: NotificationError.self) {
            try await useCase.execute(content: makeContent(), trigger: makeTrigger(), identifier: "id1")
        }
    }

    // MARK: - CancelScheduledNotificationUseCase

    @Test func cancelScheduledCallsRepository() async {
        let repo = MockNotificationRepository()
        let useCase = CancelScheduledNotificationUseCase(repository: repo)
        await useCase.execute(identifier: "id1")
        #expect(repo.cancelScheduledCallCount == 1)
    }

    // MARK: - CancelAllScheduledNotificationsUseCase

    @Test func cancelAllScheduledCallsRepository() async {
        let repo = MockNotificationRepository()
        let useCase = CancelAllScheduledNotificationsUseCase(repository: repo)
        await useCase.execute()
        #expect(repo.cancelAllScheduledCallCount == 1)
    }

    // MARK: - GetScheduledNotificationsUseCase

    @Test func getScheduledReturnsRepositoryResult() async {
        let repo = MockNotificationRepository()
        let useCase = GetScheduledNotificationsUseCase(repository: repo)
        let result = await useCase.execute()
        #expect(result.isEmpty)
    }
}
