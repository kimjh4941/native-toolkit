//
//  NotificationPermissionUseCasesTests.swift
//  IosLibraryTests
//
//  The use cases of the permission request, the settings page and the badge (design 9, SR-17):
//  they reach the port only.
//

import Foundation
import Testing
import UserNotifications
@testable import IosLibrary

struct NotificationPermissionUseCasesTests {

    @Test func requestReturnsTheGrantAndADenial() async throws {
        let repository = MockNotificationRepository()
        let useCase = RequestNotificationPermissionUseCase(repository: repository)

        #expect(try await useCase.execute(options: [.sound]) == true)
        repository.stubbedGranted = false
        #expect(try await useCase.execute(options: [.sound]) == false)
        #expect(repository.lastRequestedOptions == UNAuthorizationOptions.sound.rawValue)
        #expect(repository.authorizationStatusCallCount == 0)
    }

    @Test func requestThrowsANotificationErrorAsItIsAndAnotherAsAuthorizationFailed() async {
        let repository = MockNotificationRepository()
        repository.shouldFail = true
        let useCase = RequestNotificationPermissionUseCase(repository: repository)

        repository.requestPermissionError = NotificationError.permissionDenied
        await #expect(throws: NotificationError.permissionDenied) { try await useCase.execute(options: []) }
        repository.requestPermissionError = NSError(domain: "Custom", code: 9)
        await #expect(throws: NotificationError.authorizationFailed(FailureDetail(domain: "Custom", code: 9))) {
            try await useCase.execute(options: [])
        }
    }

    @Test func openSettingsReturnsWhetherItOpened() async {
        let repository = MockNotificationRepository()
        let useCase = OpenNotificationSettingsUseCase(repository: repository)

        #expect(await useCase.execute() == true)
        repository.stubbedSettingsOpened = false
        #expect(await useCase.execute() == false)
        #expect(repository.openSettingsCallCount == 2)
    }

    @Test func setBadgeCountCallsThePort() async throws {
        let repository = MockNotificationRepository()
        let useCase = SetBadgeCountUseCase(repository: repository)

        try await useCase.execute(2)
        repository.shouldFail = true
        await #expect(throws: NotificationError.setBadgeCountFailed(FailureDetail(systemError: TestError.stub))) {
            try await useCase.execute(0)
        }
        #expect(repository.setBadgeCountCallCount == 2)
    }
}
