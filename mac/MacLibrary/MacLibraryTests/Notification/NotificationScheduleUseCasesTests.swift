//
//  NotificationScheduleUseCasesTests.swift
//  MacLibraryTests
//
//  Created by Kim Jong Hyun on 2026/05/09.
//
import Testing
@testable import MacLibrary

struct NotificationScheduleUseCasesTests {

    private func makeUseCase(repo: MockNotificationRepository) -> NotificationScheduleUseCases {
        NotificationScheduleUseCases(repository: repo)
    }

    private func validContent() -> NotificationContent {
        NotificationContent(id: "sched-id", title: "Schedule Test")
    }

    // MARK: - schedule: success

    @Test func scheduleSuccessWithTimeInterval() {
        let repo = MockNotificationRepository()
        let useCase = makeUseCase(repo: repo)
        var result: Result<Void, NotificationDomainError>?
        useCase.schedule(content: validContent(), trigger: .timeInterval(seconds: 60, repeats: false)) { result = $0 }
        #expect(repo.addCallCount == 1)
        if case .success = result! {} else { Issue.record("Expected success") }
    }

    // MARK: - schedule: rejects immediate trigger

    @Test func scheduleRejectsImmediateTrigger() {
        let repo = MockNotificationRepository()
        let useCase = makeUseCase(repo: repo)
        var errorCode: Int?
        useCase.schedule(content: validContent(), trigger: .immediate) { r in
            if case .failure(let e) = r { errorCode = e.errorCode }
        }
        #expect(errorCode == 1102)
        #expect(repo.addCallCount == 0)
    }

    // MARK: - cancelScheduled / cancelAllScheduled

    @Test func cancelScheduledCallsRemovePending() {
        let repo = MockNotificationRepository()
        let useCase = makeUseCase(repo: repo)
        useCase.cancelScheduled(identifier: "sched-id")
        #expect(repo.removePendingCallCount == 1)
        #expect(repo.removePendingIdentifiers == ["sched-id"])
    }

    @Test func cancelAllScheduledCallsRemoveAllPending() {
        let repo = MockNotificationRepository()
        let useCase = makeUseCase(repo: repo)
        useCase.cancelAllScheduled()
        #expect(repo.removeAllPendingCallCount == 1)
    }

    // MARK: - getScheduled

    @Test func getScheduledSuccessReturnsEmpty() {
        let repo = MockNotificationRepository()
        let useCase = makeUseCase(repo: repo)
        var notifications: [ScheduledNotification]?
        useCase.getScheduled { r in
            if case .success(let list) = r { notifications = list }
        }
        #expect(notifications != nil)
        #expect(notifications?.isEmpty == true)
    }

    @Test func getScheduledPropagatesQueryFailure() {
        let repo = MockNotificationRepository()
        repo.shouldFail = true
        repo.stubError = .queryFailed(underlying: NSError(domain: "t", code: 0))
        let useCase = makeUseCase(repo: repo)
        var errorCode: Int?
        useCase.getScheduled { r in
            if case .failure(let e) = r { errorCode = e.errorCode }
        }
        #expect(errorCode == 1203)
    }
}
