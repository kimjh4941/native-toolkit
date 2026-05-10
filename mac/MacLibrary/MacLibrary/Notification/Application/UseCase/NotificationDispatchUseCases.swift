//
//  NotificationDispatchUseCases.swift
//  MacLibrary
//
//  Created by Kim Jong Hyun on 2026/05/09.
//

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

    private func validateTriggerForShow(_ trigger: NotificationTrigger) -> NotificationDomainError? {
        if case .timeInterval(let seconds, _) = trigger, seconds < 1 {
            return .invalidTrigger(reason: "timeInterval must be >= 1 second")
        }
        return nil
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
        Log.d(TAG, "show called with id: \(content.id), trigger: \(trigger)")
        if let error = validateContent(content) {
            Log.e(TAG, "show validation failed: \(error.errorMessage)")
            completion(.failure(error))
            return
        }
        if let error = validateTriggerForShow(trigger) {
            Log.e(TAG, "show trigger invalid: \(error.errorMessage)")
            completion(.failure(error))
            return
        }
        repository.add(content: content, trigger: trigger, completion: completion)
    }

    /// Updates an existing pending notification by replacing it with new content.
    ///
    /// `UNUserNotificationCenter` replaces requests with the same identifier on `add`.
    ///
    /// - Parameters:
    ///   - identifier: The identifier of the pending notification to replace.
    ///   - content: New notification payload.
    ///   - trigger: New trigger.
    ///   - completion: Called with `.success` or `.failure(NotificationDomainError)`.
    public func update(
        identifier: String,
        content: NotificationContent,
        trigger: NotificationTrigger,
        completion: @escaping (Result<Void, NotificationDomainError>) -> Void
    ) {
        Log.d(TAG, "update called with identifier: \(identifier), content.id: \(content.id), trigger: \(trigger)")
        if let error = validateContent(content) {
            Log.e(TAG, "update validation failed: \(error.errorMessage)")
            completion(.failure(error))
            return
        }
        repository.add(content: content, trigger: trigger, completion: completion)
    }
}
