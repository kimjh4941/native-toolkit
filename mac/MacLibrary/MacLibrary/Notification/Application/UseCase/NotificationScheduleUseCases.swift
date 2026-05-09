//
//  NotificationScheduleUseCases.swift
//  MacLibrary
//
//  Created by Kim Jong Hyun on 2026/05/09.
//
import UserNotifications

/// Use cases for managing pending (scheduled) notifications.
public final class NotificationScheduleUseCases {

    private let TAG = "NotificationScheduleUseCases"
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
    ) -> Result<UNNotificationTrigger, NotificationDomainError> {
        switch trigger {
        case .immediate:
            return .failure(.invalidTrigger(reason: "schedule requires a non-immediate trigger"))
        case .timeInterval(let seconds, let repeats):
            guard seconds >= 1 else {
                return .failure(.invalidTrigger(reason: "timeInterval must be >= 1 second"))
            }
            return .success(UNTimeIntervalNotificationTrigger(timeInterval: seconds, repeats: repeats))
        case .calendar(let components, let repeats):
            return .success(UNCalendarNotificationTrigger(dateMatching: components, repeats: repeats))
        }
    }

    // MARK: - Use Cases

    /// Schedules a future notification.
    ///
    /// - Parameters:
    ///   - content: The notification payload.
    ///   - trigger: When to fire. Must not be `.immediate`.
    ///   - completion: Called with `.success` or `.failure(NotificationDomainError)`.
    public func schedule(
        content: NotificationContent,
        trigger: NotificationTrigger,
        completion: @escaping (Result<Void, NotificationDomainError>) -> Void
    ) {
        Log.d(TAG, "schedule called with id: \(content.id)")
        if let error = validateContent(content) {
            Log.e(TAG, "schedule validation failed: \(error.errorMessage)")
            completion(.failure(error))
            return
        }
        switch makeTrigger(from: trigger) {
        case .failure(let e):
            Log.e(TAG, "schedule trigger invalid: \(e.errorMessage)")
            completion(.failure(e))
        case .success(let unTrigger):
            let unContent = UNMutableNotificationContent()
            unContent.title = content.title
            if let body = content.body { unContent.body = body }
            if let subtitle = content.subtitle { unContent.subtitle = subtitle }
            if let badge = content.badge { unContent.badge = NSNumber(value: badge) }
            if let userInfo = content.userInfo { unContent.userInfo = userInfo }
            let request = UNNotificationRequest(
                identifier: content.id,
                content: unContent,
                trigger: unTrigger
            )
            repository.add(request: request, completion: completion)
        }
    }

    /// Cancels the pending notification with the given identifier.
    ///
    /// - Parameter identifier: The notification identifier to cancel.
    public func cancelScheduled(identifier: String) {
        Log.d(TAG, "cancelScheduled called with identifier: \(identifier)")
        repository.removePending(identifiers: [identifier])
    }

    /// Cancels all pending notifications.
    public func cancelAllScheduled() {
        Log.d(TAG, "cancelAllScheduled called")
        repository.removeAllPending()
    }

    /// Returns all pending (scheduled) notifications.
    ///
    /// - Parameter completion: Called with the list of scheduled notifications or a domain error.
    public func getScheduled(
        completion: @escaping (Result<[ScheduledNotification], NotificationDomainError>) -> Void
    ) {
        Log.d(TAG, "getScheduled called")
        repository.getPendingRequests { result in
            switch result {
            case .failure(let e):
                completion(.failure(e))
            case .success(let requests):
                let scheduled = requests.map {
                    ScheduledNotification(
                        identifier: $0.identifier,
                        title: $0.content.title,
                        body: $0.content.body.isEmpty ? nil : $0.content.body,
                        trigger: $0.trigger
                    )
                }
                completion(.success(scheduled))
            }
        }
    }
}
