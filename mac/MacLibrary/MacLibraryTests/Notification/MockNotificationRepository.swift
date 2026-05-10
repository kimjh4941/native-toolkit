//
//  MockNotificationRepository.swift
//  MacLibraryTests
//
//  Created by Kim Jong Hyun on 2026/05/09.
//
import UserNotifications
@testable import MacLibrary

/// A mock implementation of `NotificationRepository` for unit testing.
final class MockNotificationRepository: NotificationRepository {

    // MARK: - Stubs

    var shouldFail = false
    var stubError: NotificationDomainError = .unknown(underlying: NSError(domain: "test", code: -1))
    var stubAuthorizationStatus: NotificationAuthorizationStatus = .authorized
    var stubScheduled: [ScheduledNotification] = []
    var stubDelivered: [ActiveNotification] = []

    // MARK: - Call Counts

    var requestAuthorizationCallCount = 0
    var getAuthorizationStatusCallCount = 0
    var addCallCount = 0
    var lastAddContent: NotificationContent?
    var lastAddTrigger: NotificationTrigger?
    var removePendingCallCount = 0
    var removePendingIdentifiers: [String] = []
    var removeAllPendingCallCount = 0
    var removeDeliveredCallCount = 0
    var removeDeliveredIdentifiers: [String] = []
    var removeAllDeliveredCallCount = 0
    var getScheduledCallCount = 0
    var getDeliveredCallCount = 0
    var setCategoriesCallCount = 0
    var lastSetCategories: [NotificationCategory] = []
    var setBadgeCountCallCount = 0
    var lastBadgeCount: Int = 0

    // MARK: - NotificationRepository

    func requestAuthorization(
        options: UNAuthorizationOptions,
        completion: @escaping (Result<Bool, NotificationDomainError>) -> Void
    ) {
        requestAuthorizationCallCount += 1
        completion(shouldFail ? .failure(stubError) : .success(true))
    }

    func getAuthorizationStatus(
        completion: @escaping (Result<NotificationAuthorizationStatus, NotificationDomainError>) -> Void
    ) {
        getAuthorizationStatusCallCount += 1
        completion(shouldFail ? .failure(stubError) : .success(stubAuthorizationStatus))
    }

    func add(
        content: NotificationContent,
        trigger: NotificationTrigger,
        completion: @escaping (Result<Void, NotificationDomainError>) -> Void
    ) {
        addCallCount += 1
        lastAddContent = content
        lastAddTrigger = trigger
        completion(shouldFail ? .failure(stubError) : .success(()))
    }

    func removePending(identifiers: [String]) {
        removePendingCallCount += 1
        removePendingIdentifiers = identifiers
    }

    func removeAllPending() {
        removeAllPendingCallCount += 1
    }

    func removeDelivered(identifiers: [String]) {
        removeDeliveredCallCount += 1
        removeDeliveredIdentifiers = identifiers
    }

    func removeAllDelivered() {
        removeAllDeliveredCallCount += 1
    }

    func getScheduled(
        completion: @escaping (Result<[ScheduledNotification], NotificationDomainError>) -> Void
    ) {
        getScheduledCallCount += 1
        completion(shouldFail ? .failure(stubError) : .success(stubScheduled))
    }

    func getDelivered(
        completion: @escaping (Result<[ActiveNotification], NotificationDomainError>) -> Void
    ) {
        getDeliveredCallCount += 1
        completion(shouldFail ? .failure(stubError) : .success(stubDelivered))
    }

    func setCategories(_ categories: [NotificationCategory]) {
        setCategoriesCallCount += 1
        lastSetCategories = categories
    }

    func setBadgeCount(
        _ count: Int,
        completion: @escaping (Result<Void, NotificationDomainError>) -> Void
    ) {
        setBadgeCountCallCount += 1
        lastBadgeCount = count
        completion(shouldFail ? .failure(stubError) : .success(()))
    }
}
