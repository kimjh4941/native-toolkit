//
//  NotificationQueryUseCasesTests.swift
//  IosLibraryTests
//

import Testing
@testable import IosLibrary

struct NotificationQueryUseCasesTests {

    // MARK: - GetDeliveredNotificationsUseCase

    @Test func getDeliveredReturnsRepositoryResult() async {
        let repo = MockNotificationRepository()
        let delivered = ActiveNotification(
            identifier: "n1", title: "Hi", subtitle: nil, body: nil,
            categoryIdentifier: "", date: Date(), userInfo: [:]
        )
        repo.stubbedDelivered = [delivered]
        let useCase = GetDeliveredNotificationsUseCase(repository: repo)
        let result = await useCase.execute()
        #expect(result.count == 1)
        #expect(result.first?.identifier == "n1")
    }

    // MARK: - HasNotificationPermissionUseCase

    @Test func hasPermissionReturnsTrueWhenAuthorized() async {
        let repo = MockNotificationRepository()
        repo.stubbedAuthorizationStatus = .authorized
        let useCase = HasNotificationPermissionUseCase(repository: repo)
        let result = await useCase.execute()
        #expect(result == true)
    }

    @Test func hasPermissionReturnsTrueWhenProvisional() async {
        let repo = MockNotificationRepository()
        repo.stubbedAuthorizationStatus = .provisional
        let useCase = HasNotificationPermissionUseCase(repository: repo)
        let result = await useCase.execute()
        #expect(result == true)
    }

    @Test func hasPermissionReturnsFalseWhenDenied() async {
        let repo = MockNotificationRepository()
        repo.stubbedAuthorizationStatus = .denied
        let useCase = HasNotificationPermissionUseCase(repository: repo)
        let result = await useCase.execute()
        #expect(result == false)
    }

    @Test func hasPermissionReturnsFalseWhenNotDetermined() async {
        let repo = MockNotificationRepository()
        repo.stubbedAuthorizationStatus = .notDetermined
        let useCase = HasNotificationPermissionUseCase(repository: repo)
        let result = await useCase.execute()
        #expect(result == false)
    }

    // MARK: - GetAuthorizationStatusUseCase

    @Test func getAuthorizationStatusReturnsRepositoryValue() async {
        let repo = MockNotificationRepository()
        repo.stubbedAuthorizationStatus = .ephemeral
        let useCase = GetAuthorizationStatusUseCase(repository: repo)
        let result = await useCase.execute()
        #expect(result == .ephemeral)
    }
}
