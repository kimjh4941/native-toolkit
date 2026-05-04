//
//  NotificationPermissionHelperTests.swift
//  IosLibraryTests
//

import Testing
@testable import IosLibrary

struct NotificationPermissionHelperTests {

    @Test func requestPermissionReturnsTrueWhenGranted() async throws {
        let repo = MockNotificationRepository()
        let helper = NotificationPermissionHelper(repository: repo)
        let result = try await helper.requestPermission()
        #expect(result == true)
    }

    @Test func requestPermissionThrowsPermissionDeniedWhenFailed() async {
        let repo = MockNotificationRepository()
        repo.shouldFail = true
        let helper = NotificationPermissionHelper(repository: repo)
        await #expect(throws: NotificationError.self) {
            _ = try await helper.requestPermission()
        }
    }

    @Test func authorizationStatusDelegatesToRepository() async {
        let repo = MockNotificationRepository()
        repo.stubbedAuthorizationStatus = .denied
        let helper = NotificationPermissionHelper(repository: repo)
        let status = await helper.authorizationStatus()
        #expect(status == .denied)
    }

    @Test func openNotificationSettingsCallsRepository() {
        let repo = MockNotificationRepository()
        let helper = NotificationPermissionHelper(repository: repo)
        helper.openNotificationSettings()
        #expect(repo.openSettingsCallCount == 1)
    }
}
