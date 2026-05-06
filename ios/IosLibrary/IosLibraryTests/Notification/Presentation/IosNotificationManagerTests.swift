//
//  IosNotificationManagerTests.swift
//  IosLibraryTests
//

import Testing
import UserNotifications
@testable import IosLibrary

struct IosNotificationManagerTests {

    private func makeManager(repo: MockNotificationRepository) -> IosNotificationManager {
        let helper = NotificationPermissionHelper(repository: repo)
        return IosNotificationManager(repository: repo, permissionHelper: helper)
    }

    @Test func foregroundPresentationOptionsContainsListByDefault() {
        let repo = MockNotificationRepository()
        let manager = makeManager(repo: repo)
        #expect(manager.foregroundPresentationOptions.contains(.banner))
        #expect(manager.foregroundPresentationOptions.contains(.list))
    }

    @Test func openNotificationSettingsCallsRepository() {
        let repo = MockNotificationRepository()
        let manager = makeManager(repo: repo)

        manager.openNotificationSettings()

        #expect(repo.openSettingsCallCount == 1)
    }

    @Test func authorizationStatusReturnsUseCaseValue() async {
        let repo = MockNotificationRepository()
        repo.stubbedAuthorizationStatus = .provisional
        let manager = makeManager(repo: repo)

        let result = await withCheckedContinuation { continuation in
            manager.authorizationStatus { status in
                continuation.resume(returning: status)
            }
        }

        #expect(result == .provisional)
    }

    @Test func getScheduledReturnsUseCaseValue() async {
        let repo = MockNotificationRepository()
        repo.stubbedScheduled = [
            ScheduledNotification(
                identifier: "scheduled-1",
                title: "title",
                subtitle: nil,
                body: "body",
                categoryIdentifier: "sample",
                userInfo: [:]
            )
        ]
        let manager = makeManager(repo: repo)

        let result = await withCheckedContinuation { continuation in
            manager.getScheduled { scheduled in
                continuation.resume(returning: scheduled)
            }
        }

        #expect(result.count == 1)
        #expect(result[0].identifier == "scheduled-1")
        #expect(result[0].body == "body")
    }
}
