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
/// All domain ↔ platform-type conversions are concentrated here so that higher
/// layers (Application, Domain) remain free of UserNotifications imports.
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
        completion: @escaping (Result<NotificationAuthorizationStatus, NotificationDomainError>) -> Void
    ) {
        Log.d(TAG, "getAuthorizationStatus called")
        center.getNotificationSettings { [weak self] settings in
            guard let self else { return }
            let status = self.mapAuthorizationStatus(settings.authorizationStatus)
            Log.d(self.TAG, "getAuthorizationStatus result: \(status)")
            completion(.success(status))
        }
    }

    // MARK: - Add / Remove

    public func add(
        content: NotificationContent,
        trigger: NotificationTrigger,
        completion: @escaping (Result<Void, NotificationDomainError>) -> Void
    ) {
        Log.d(TAG, "add called with id: \(content.id), trigger: \(trigger)")
        let requestResult = makeRequest(content: content, trigger: trigger)
        switch requestResult {
        case .failure(let e):
            completion(.failure(e))
        case .success(let request):
            center.add(request) { [weak self] error in
                guard let self else { return }
                if let error {
                    Log.e(self.TAG, "add failed: \(error.localizedDescription)")
                    completion(.failure(.addFailed(underlying: error)))
                } else {
                    Log.d(self.TAG, "add succeeded for id: \(content.id)")
                    completion(.success(()))
                }
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

    public func getScheduled(
        completion: @escaping (Result<[ScheduledNotification], NotificationDomainError>) -> Void
    ) {
        Log.d(TAG, "getScheduled called")
        center.getPendingNotificationRequests { [weak self] requests in
            guard let self else { return }
            let scheduled = requests.map { self.mapScheduledNotification($0) }
            Log.d(self.TAG, "getScheduled returned \(scheduled.count) items")
            completion(.success(scheduled))
        }
    }

    public func getDelivered(
        completion: @escaping (Result<[ActiveNotification], NotificationDomainError>) -> Void
    ) {
        Log.d(TAG, "getDelivered called")
        center.getDeliveredNotifications { [weak self] notifications in
            guard let self else { return }
            let active = notifications.map { self.mapActiveNotification($0) }
            Log.d(self.TAG, "getDelivered returned \(active.count) items")
            completion(.success(active))
        }
    }

    // MARK: - Category

    public func setCategories(_ categories: [NotificationCategory]) {
        Log.d(TAG, "setCategories called with count: \(categories.count)")
        let unCategories = Set(categories.map { mapUNCategory($0) })
        center.setNotificationCategories(unCategories)
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

    // MARK: - Private: Domain → Platform

    private func makeRequest(
        content: NotificationContent,
        trigger: NotificationTrigger
    ) -> Result<UNNotificationRequest, NotificationDomainError> {
        let triggerResult = makeUNTrigger(from: trigger)
        switch triggerResult {
        case .failure(let e): return .failure(e)
        case .success(let unTrigger):
            let unContent = UNMutableNotificationContent()
            unContent.title = content.title
            if let body = content.body { unContent.body = body }
            if let subtitle = content.subtitle { unContent.subtitle = subtitle }
            if let categoryIdentifier = content.categoryIdentifier { unContent.categoryIdentifier = categoryIdentifier }
            if let badge = content.badge { unContent.badge = NSNumber(value: badge) }
            if let userInfo = content.userInfo { unContent.userInfo = userInfo }
            let request = UNNotificationRequest(
                identifier: content.id,
                content: unContent,
                trigger: unTrigger
            )
            return .success(request)
        }
    }

    private func makeUNTrigger(
        from trigger: NotificationTrigger
    ) -> Result<UNNotificationTrigger?, NotificationDomainError> {
        switch trigger {
        case .immediate:
            return .success(nil)
        case .timeInterval(let seconds, let repeats):
            return .success(UNTimeIntervalNotificationTrigger(timeInterval: seconds, repeats: repeats))
        case .calendar(let components, let repeats):
            return .success(UNCalendarNotificationTrigger(dateMatching: components, repeats: repeats))
        }
    }

    private func mapUNCategory(_ category: NotificationCategory) -> UNNotificationCategory {
        let actions: [UNNotificationAction] = category.actions.map { action in
            if action.isTextInput {
                return UNTextInputNotificationAction(
                    identifier: action.id,
                    title: action.title,
                    options: action.isForeground ? [.foreground] : [],
                    textInputButtonTitle: action.title,
                    textInputPlaceholder: action.textInputPlaceholder ?? ""
                )
            } else {
                return UNNotificationAction(
                    identifier: action.id,
                    title: action.title,
                    options: action.isForeground ? [.foreground] : []
                )
            }
        }
        return UNNotificationCategory(
            identifier: category.id,
            actions: actions,
            intentIdentifiers: [],
            options: []
        )
    }

    // MARK: - Private: Platform → Domain

    private func mapAuthorizationStatus(_ status: UNAuthorizationStatus) -> NotificationAuthorizationStatus {
        switch status {
        case .notDetermined:  return .notDetermined
        case .denied:         return .denied
        case .authorized:     return .authorized
        case .provisional:    return .provisional
        case .ephemeral:      return .authorized
        @unknown default:     return .unsupported
        }
    }

    private func mapScheduledNotification(_ request: UNNotificationRequest) -> ScheduledNotification {
        ScheduledNotification(
            identifier: request.identifier,
            title: request.content.title,
            body: request.content.body.isEmpty ? nil : request.content.body,
            trigger: mapNotificationTrigger(request.trigger)
        )
    }

    private func mapActiveNotification(_ notification: UNNotification) -> ActiveNotification {
        ActiveNotification(
            identifier: notification.request.identifier,
            title: notification.request.content.title,
            body: notification.request.content.body.isEmpty ? nil : notification.request.content.body,
            date: notification.date
        )
    }

    private func mapNotificationTrigger(_ trigger: UNNotificationTrigger?) -> NotificationTrigger? {
        switch trigger {
        case let t as UNTimeIntervalNotificationTrigger:
            return .timeInterval(seconds: t.timeInterval, repeats: t.repeats)
        case let t as UNCalendarNotificationTrigger:
            return .calendar(dateComponents: t.dateComponents, repeats: t.repeats)
        default:
            return nil
        }
    }
}
