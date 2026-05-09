//
//  NotificationRepositoryImpl.swift
//  MacLibrary
//
//  Created by Kim Jong Hyun on 2026/05/09.
//
import UserNotifications
import AppKit

/// Concrete implementation of `NotificationRepository` backed by `UNUserNotificationCenter`.
///
/// - Note: Requires macOS 15+. All completions are called on an unspecified internal queue.
///   `MacNotificationManager` is responsible for dispatching to the main queue before
///   surfacing results to callers.
public final class NotificationRepositoryImpl: NotificationRepository {

    private let TAG = "NotificationRepositoryImpl"
    private let center: UNUserNotificationCenter

    public init(center: UNUserNotificationCenter = .current()) {
        Log.d(TAG, "init")
        self.center = center
    }

    // MARK: - Permission

    public func requestAuthorization(
        options: UNAuthorizationOptions,
        completion: @escaping (Result<Bool, NotificationDomainError>) -> Void
    ) {
        Log.d(TAG, "requestAuthorization called with options: \(options.rawValue)")
        center.requestAuthorization(options: options) { [weak self] granted, error in
            guard let self else { return }
            if let error {
                Log.e(self.TAG, "requestAuthorization failed: \(error.localizedDescription)")
                completion(.failure(.permissionRequestFailed(underlying: error)))
            } else if !granted {
                Log.e(self.TAG, "requestAuthorization denied")
                completion(.failure(.permissionDenied))
            } else {
                Log.d(self.TAG, "requestAuthorization granted")
                completion(.success(granted))
            }
        }
    }

    public func getAuthorizationStatus(
        completion: @escaping (Result<UNNotificationSettings, NotificationDomainError>) -> Void
    ) {
        Log.d(TAG, "getAuthorizationStatus called")
        center.getNotificationSettings { settings in
            completion(.success(settings))
        }
    }

    // MARK: - Add / Remove

    public func add(
        request: UNNotificationRequest,
        completion: @escaping (Result<Void, NotificationDomainError>) -> Void
    ) {
        Log.d(TAG, "add called with identifier: \(request.identifier)")
        center.add(request) { [weak self] error in
            guard let self else { return }
            if let error {
                Log.e(self.TAG, "add failed: \(error.localizedDescription)")
                completion(.failure(.addFailed(underlying: error)))
            } else {
                Log.d(self.TAG, "add succeeded")
                completion(.success(()))
            }
        }
    }

    public func removePending(identifiers: [String]) {
        Log.d(TAG, "removePending called with identifiers: \(identifiers)")
        center.removePendingNotificationRequests(withIdentifiers: identifiers)
    }

    public func removeAllPending() {
        Log.d(TAG, "removeAllPending called")
        center.removeAllPendingNotificationRequests()
    }

    public func removeDelivered(identifiers: [String]) {
        Log.d(TAG, "removeDelivered called with identifiers: \(identifiers)")
        center.removeDeliveredNotifications(withIdentifiers: identifiers)
    }

    public func removeAllDelivered() {
        Log.d(TAG, "removeAllDelivered called")
        center.removeAllDeliveredNotifications()
    }

    // MARK: - Query

    public func getPendingRequests(
        completion: @escaping (Result<[UNNotificationRequest], NotificationDomainError>) -> Void
    ) {
        Log.d(TAG, "getPendingRequests called")
        center.getPendingNotificationRequests { requests in
            completion(.success(requests))
        }
    }

    public func getDeliveredNotifications(
        completion: @escaping (Result<[UNNotification], NotificationDomainError>) -> Void
    ) {
        Log.d(TAG, "getDeliveredNotifications called")
        center.getDeliveredNotifications { notifications in
            completion(.success(notifications))
        }
    }

    // MARK: - Category

    public func setNotificationCategories(_ categories: Set<UNNotificationCategory>) {
        Log.d(TAG, "setNotificationCategories called with count: \(categories.count)")
        center.setNotificationCategories(categories)
    }

    // MARK: - Badge

    public func setBadgeCount(
        _ count: Int,
        completion: @escaping (Result<Void, NotificationDomainError>) -> Void
    ) {
        Log.d(TAG, "setBadgeCount called with count: \(count)")
        if #available(macOS 15.0, *) {
            center.setBadgeCount(count) { [weak self] error in
                guard let self else { return }
                if let error {
                    Log.e(self.TAG, "setBadgeCount failed: \(error.localizedDescription)")
                    completion(.failure(.setBadgeFailed(underlying: error)))
                } else {
                    Log.d(self.TAG, "setBadgeCount succeeded")
                    completion(.success(()))
                }
            }
        } else {
            DispatchQueue.main.async {
                NSApplication.shared.dockTile.badgeLabel = count > 0 ? "\(count)" : nil
                completion(.success(()))
            }
        }
    }
}
