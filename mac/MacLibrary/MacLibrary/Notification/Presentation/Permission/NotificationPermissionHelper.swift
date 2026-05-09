//
//  NotificationPermissionHelper.swift
//  MacLibrary
//
//  Created by Kim Jong Hyun on 2026/05/09.
//
import UserNotifications
import AppKit

/// Helper that wraps permission-related notification operations.
///
/// All completion callbacks are dispatched to the **main queue**.
public final class NotificationPermissionHelper {

    private let TAG = "NotificationPermissionHelper"
    private let repository: NotificationRepository

    public init(repository: NotificationRepository) {
        Log.d(TAG, "init")
        self.repository = repository
    }

    // MARK: - Public API

    /// Requests notification authorization with the specified options.
    ///
    /// - Parameters:
    ///   - options: The authorization options (alert, sound, badge, etc.).
    ///   - completion: Called on the main queue with `true` if granted, or a domain error.
    public func requestPermission(
        options: UNAuthorizationOptions = [.alert, .sound, .badge],
        completion: @escaping (Result<Bool, NotificationDomainError>) -> Void
    ) {
        Log.d(TAG, "requestPermission called")
        repository.requestAuthorization(options: options) { result in
            DispatchQueue.main.async {
                completion(result)
            }
        }
    }

    /// Returns the current authorization status.
    ///
    /// - Parameter completion: Called on the main queue with the mapped status.
    public func getAuthorizationStatus(
        completion: @escaping (Result<NotificationAuthorizationStatus, NotificationDomainError>) -> Void
    ) {
        Log.d(TAG, "getAuthorizationStatus called")
        repository.getAuthorizationStatus { result in
            DispatchQueue.main.async {
                switch result {
                case .failure(let e):
                    completion(.failure(e))
                case .success(let settings):
                    let status = NotificationPermissionHelper.map(settings.authorizationStatus)
                    completion(.success(status))
                }
            }
        }
    }

    /// Opens the system Notification Settings for this application.
    ///
    /// - Parameter completion: Called on the main queue with `.success` or a domain error.
    public func openNotificationSettings(
        completion: @escaping (Result<Void, NotificationDomainError>) -> Void
    ) {
        Log.d(TAG, "openNotificationSettings called")
        DispatchQueue.main.async {
            if let url = URL(string: "x-apple.systempreferences:com.apple.preference.notifications") {
                let opened = NSWorkspace.shared.open(url)
                if opened {
                    Log.d(self.TAG, "openNotificationSettings opened successfully")
                    completion(.success(()))
                } else {
                    Log.e(self.TAG, "openNotificationSettings failed to open URL")
                    let error = NSError(
                        domain: "NotificationPermissionHelper",
                        code: -1,
                        userInfo: [NSLocalizedDescriptionKey: "Failed to open notification settings URL"]
                    )
                    completion(.failure(.openSettingsFailed(underlying: error)))
                }
            } else {
                Log.e(self.TAG, "openNotificationSettings invalid URL")
                let error = NSError(
                    domain: "NotificationPermissionHelper",
                    code: -1,
                    userInfo: [NSLocalizedDescriptionKey: "Invalid settings URL"]
                )
                completion(.failure(.openSettingsFailed(underlying: error)))
            }
        }
    }

    // MARK: - Private

    private static func map(_ status: UNAuthorizationStatus) -> NotificationAuthorizationStatus {
        switch status {
        case .notDetermined:  return .notDetermined
        case .denied:         return .denied
        case .authorized:     return .authorized
        case .provisional:    return .provisional
        case .ephemeral:      return .authorized
        @unknown default:     return .unsupported
        }
    }
}
