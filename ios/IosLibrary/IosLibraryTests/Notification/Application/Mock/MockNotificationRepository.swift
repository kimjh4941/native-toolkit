//
//  MockNotificationRepository.swift
//  IosLibraryTests
//

import Foundation
import UserNotifications
@testable import IosLibrary

final class MockNotificationRepository: NotificationRepository {

    var shouldFail = false
    var stubbedAuthorizationStatus: NotificationAuthorizationStatus = .authorized
    var stubbedScheduled: [ScheduledNotification] = []
    var stubbedDelivered: [ActiveNotification] = []

    private(set) var showCallCount = 0
    private(set) var updateCallCount = 0
    private(set) var scheduleCallCount = 0
    private(set) var cancelCallCount = 0
    private(set) var cancelAllCallCount = 0
    private(set) var removeDeliveredCallCount = 0
    private(set) var removeAllDeliveredCallCount = 0
    private(set) var cancelScheduledCallCount = 0
    private(set) var cancelAllScheduledCallCount = 0
    private(set) var setBadgeCountCallCount = 0
    private(set) var registerCategoryCallCount = 0
    private(set) var removeCategoryCallCount = 0
    private(set) var openSettingsCallCount = 0

    func show(content: NotificationContent, trigger: NotificationTrigger?) async throws {
        showCallCount += 1
        if shouldFail { throw NotificationError.addRequestFailed(TestError.stub) }
    }

    func update(identifier: String, content: NotificationContent, trigger: NotificationTrigger?) async throws {
        updateCallCount += 1
        if shouldFail { throw NotificationError.addRequestFailed(TestError.stub) }
    }

    func schedule(content: NotificationContent, trigger: NotificationTrigger, identifier: String) async throws {
        scheduleCallCount += 1
        if shouldFail { throw NotificationError.addRequestFailed(TestError.stub) }
    }

    func requestPermission(options: UNAuthorizationOptions) async throws -> Bool {
        if shouldFail { throw NotificationError.permissionDenied }
        return true
    }

    func setBadgeCount(_ count: Int) async throws {
        setBadgeCountCallCount += 1
        if shouldFail { throw NotificationError.setBadgeCountFailed(TestError.stub) }
    }

    func cancel(identifier: String) async {
        cancelCallCount += 1
    }

    func cancelAll() async {
        cancelAllCallCount += 1
    }

    func removeDelivered(identifier: String) async {
        removeDeliveredCallCount += 1
    }

    func removeAllDelivered() async {
        removeAllDeliveredCallCount += 1
    }

    func cancelScheduled(identifier: String) async {
        cancelScheduledCallCount += 1
    }

    func cancelAllScheduled() async {
        cancelAllScheduledCallCount += 1
    }

    func getScheduled() async -> [ScheduledNotification] {
        stubbedScheduled
    }

    func getDelivered() async -> [ActiveNotification] {
        stubbedDelivered
    }

    func authorizationStatus() async -> NotificationAuthorizationStatus {
        stubbedAuthorizationStatus
    }

    func openNotificationSettings() {
        openSettingsCallCount += 1
    }

    func registerCategory(_ category: NotificationCategory) async {
        registerCategoryCallCount += 1
    }

    func removeCategory(identifier: String) async {
        removeCategoryCallCount += 1
    }
}

enum TestError: Error {
    case stub
}
