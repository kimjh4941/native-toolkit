//
//  NotificationDispatchUseCases.swift
//  MacLibrary
//
//  Created by Kim Jong Hyun on 2026/05/09.
//
import UserNotifications

/// Use cases for dispatching (showing / updating) notifications immediately or with a trigger.
public final class NotificationDispatchUseCases {

    private let TAG = "NotificationDispatchUseCases"
    private let repository: NotificationRepository

    public init(repository: NotificationRepository) {
        Log.d(TAG, "init")
        self.repository = repository
    }

    // MARK: - Validation

    private func validateContent(_ content: NotificationContent) -> NotificationDomainError? {
        let idPattern = "^[A-Za-z0-9\\-_]{1,128}$"
        guard content.id.range(of: idPattern, options: .regularExpression) != nil else {
            return .invalidContent(reason: "id must be 1-128 chars using [A-Za-z0-9\\-_]")
        }
        guard !content.title.isEmpty, content.title.count <= 128 else {
            return .invalidContent(reason: "title must be 1-128 characters")
        }
        if let body = content.body, body.count > 1024 {
            return .invalidContent(reason: "body must not exceed 1024 characters")
        }
        return nil
    }

    private func makeTrigger(
        from trigger: NotificationTrigger
    ) -> Result<UNNotificationTrigger?, NotificationDomainError> {
        switch trigger {
        case .immediate:
            return .success(nil)
        case .timeInterval(let seconds, let repeats):
            guard seconds >= 1 else {
                return .failure(.invalidTrigger(reason: "timeInterval must be >= 1 second"))
            }
            return .success(UNTimeIntervalNotificationTrigger(timeInterval: seconds, repeats: repeats))
        case .calendar(let components, let repeats):
            return .success(UNCalendarNotificationTrigger(dateMatching: components, repeats: repeats))
        }
    }

    private func makeRequest(
        content: NotificationContent,
        trigger: NotificationTrigger
    ) -> Result<UNNotificationRequest, NotificationDomainError> {
        if let error = validateContent(content) {
            return .failure(error)
        }
        let triggerResult = makeTrigger(from: trigger)
        switch triggerResult {
        case .failure(let e): return .failure(e)
        case .success(let unTrigger):
            let unContent = UNMutableNotificationContent()
            unContent.title = content.title
            if let body = content.body { unContent.body = body }
            if let subtitle = content.subtitle { unContent.subtitle = subtitle }
            if let badge = content.badge { unContent.badge = NSNumber(value: badge) }
            if let userInfo = content.userInfo {
                unContent.userInfo = userInfo
            }
            let request = UNNotificationRequest(
                identifier: content.id,
                content: unContent,
                trigger: unTrigger
            )
            return .success(request)
        }
    }

    // MARK: - Use Cases

    /// Dispatches a notification immediately or with the given trigger.
    ///
    /// - Parameters:
    ///   - content: The notification payload.
    ///   - trigger: When to fire the notification.
    ///   - completion: Called with `.success` or `.failure(NotificationDomainError)`.
    public func show(
        content: NotificationContent,
        trigger: NotificationTrigger,
        completion: @escaping (Result<Void, NotificationDomainError>) -> Void
    ) {
        Log.d(TAG, "show called with id: \(content.id)")
        switch makeRequest(content: content, trigger: trigger) {
        case .failure(let e):
            Log.e(TAG, "show validation failed: \(e.errorMessage)")
            completion(.failure(e))
        case .success(let request):
            repository.add(request: request, completion: completion)
        }
    }

    /// Updates an existing pending notification by replacing it with new content.
    ///
    /// - Parameters:
    ///   - identifier: The identifier of the pending notification to replace.
    ///   - content: New notification payload (must use the same `id` as `identifier`).
    ///   - trigger: New trigger.
    ///   - completion: Called with `.success` or `.failure(NotificationDomainError)`.
    public func update(
        identifier: String,
        content: NotificationContent,
        trigger: NotificationTrigger,
        completion: @escaping (Result<Void, NotificationDomainError>) -> Void
    ) {
        Log.d(TAG, "update called with identifier: \(identifier)")
        repository.getPendingRequests { [weak self] result in
            guard let self else { return }
            switch result {
            case .failure(let e):
                Log.e(self.TAG, "update query failed: \(e.errorMessage)")
                completion(.failure(e))
            case .success(let requests):
                guard requests.contains(where: { $0.identifier == identifier }) else {
                    Log.e(self.TAG, "update notificationNotFound: \(identifier)")
                    completion(.failure(.notificationNotFound(identifier: identifier)))
                    return
                }
                switch self.makeRequest(content: content, trigger: trigger) {
                case .failure(let e):
                    Log.e(self.TAG, "update validation failed: \(e.errorMessage)")
                    completion(.failure(e))
                case .success(let request):
                    self.repository.add(request: request, completion: completion)
                }
            }
        }
    }
}
