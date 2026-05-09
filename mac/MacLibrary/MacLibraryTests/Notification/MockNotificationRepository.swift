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
    var stubSettings: UNNotificationSettings? = nil
    var stubPendingRequests: [UNNotificationRequest] = []
    var stubDeliveredNotifications: [UNNotification] = []

    // MARK: - Call Counts

    var requestAuthorizationCallCount = 0
    var getAuthorizationStatusCallCount = 0
    var addCallCount = 0
    var removePendingCallCount = 0
    var removePendingIdentifiers: [String] = []
    var removeAllPendingCallCount = 0
    var removeDeliveredCallCount = 0
    var removeDeliveredIdentifiers: [String] = []
    var removeAllDeliveredCallCount = 0
    var getPendingRequestsCallCount = 0
    var getDeliveredNotificationsCallCount = 0
    var setNotificationCategoriesCallCount = 0
    var lastSetCategories: Set<UNNotificationCategory> = []
    var setBadgeCountCallCount = 0
    var lastBadgeCount: Int = 0

    // MARK: - NotificationRepository

    func requestAuthorization(
        options: UNAuthorizationOptions,
        completion: @escaping (Result<Bool, NotificationDomainError>) -> Void
    ) {
        requestAuthorizationCallCount += 1
        if shouldFail {
            completion(.failure(stubError))
        } else {
            completion(.success(true))
        }
    }

    func getAuthorizationStatus(
        completion: @escaping (Result<UNNotificationSettings, NotificationDomainError>) -> Void
    ) {
        getAuthorizationStatusCallCount += 1
        if shouldFail {
            completion(.failure(stubError))
        } else if let settings = stubSettings {
            completion(.success(settings))
        } else {
            completion(.failure(.queryFailed(underlying: NSError(domain: "test", code: -1))))
        }
    }

    func add(
        request: UNNotificationRequest,
        completion: @escaping (Result<Void, NotificationDomainError>) -> Void
    ) {
        addCallCount += 1
        if shouldFail {
            completion(.failure(stubError))
        } else {
            completion(.success(()))
        }
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

    func getPendingRequests(
        completion: @escaping (Result<[UNNotificationRequest], NotificationDomainError>) -> Void
    ) {
        getPendingRequestsCallCount += 1
        if shouldFail {
            completion(.failure(stubError))
        } else {
            completion(.success(stubPendingRequests))
        }
    }

    func getDeliveredNotifications(
        completion: @escaping (Result<[UNNotification], NotificationDomainError>) -> Void
    ) {
        getDeliveredNotificationsCallCount += 1
        if shouldFail {
            completion(.failure(stubError))
        } else {
            completion(.success(stubDeliveredNotifications))
        }
    }

    func setNotificationCategories(_ categories: Set<UNNotificationCategory>) {
        setNotificationCategoriesCallCount += 1
        lastSetCategories = categories
    }

    func setBadgeCount(
        _ count: Int,
        completion: @escaping (Result<Void, NotificationDomainError>) -> Void
    ) {
        setBadgeCountCallCount += 1
        lastBadgeCount = count
        if shouldFail {
            completion(.failure(stubError))
        } else {
            completion(.success(()))
        }
    }
}
