//
//  NotificationPermissionHelperTests.swift
//  IosLibraryTests
//
//  The deprecated `NotificationPermissionHelper` keeps its behavior (design S-P27). It is called
//  through `deprecatedNotification`, so that the test target builds without deprecation warnings.
//

import Testing
@testable import IosLibrary

struct NotificationPermissionHelperTests {

    @Test func requestPermissionReturnsTrueWhenGranted() async throws {
        let repo = MockNotificationRepository()
        let result = try await deprecatedNotification.helperRequestPermission(repository: repo)
        #expect(result == true)
    }

    /// A denial is still thrown as `permissionDenied`.
    @Test func requestPermissionThrowsPermissionDeniedWhenDenied() async {
        let repo = MockNotificationRepository()
        repo.stubbedGranted = false
        await #expect(throws: NotificationError.permissionDenied) {
            _ = try await deprecatedNotification.helperRequestPermission(repository: repo)
        }
    }

    @Test func requestPermissionThrowsWhatTheRepositoryThrew() async {
        let repo = MockNotificationRepository()
        repo.shouldFail = true
        repo.requestPermissionError = NotificationError.authorizationFailed(FailureDetail(domain: "UNErrorDomain", code: 1))
        await #expect(throws: NotificationError.authorizationFailed(FailureDetail(domain: "UNErrorDomain", code: 1))) {
            _ = try await deprecatedNotification.helperRequestPermission(repository: repo)
        }
    }

    @Test func authorizationStatusDelegatesToRepository() async {
        let repo = MockNotificationRepository()
        repo.stubbedAuthorizationStatus = .denied
        let status = await deprecatedNotification.helperAuthorizationStatus(repository: repo)
        #expect(status == .denied)
    }

    /// Still returns at once; the repository's `async` form is called in a task.
    @Test func openNotificationSettingsCallsRepository() async throws {
        let repo = MockNotificationRepository()
        deprecatedNotification.helperOpenNotificationSettings(repository: repo)
        for _ in 0..<500 where repo.openSettingsCallCount == 0 {
            try await Task.sleep(nanoseconds: 10_000_000)
        }
        #expect(repo.openSettingsCallCount == 1)
    }
}
