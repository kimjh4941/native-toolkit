//
//  NotificationPresentationGate.swift
//  IosLibrary
//

import Foundation
import os
import UserNotifications

private let logger = Logger(subsystem: "com.jonghyunkim.nativetoolkit.IosLibrary", category: "NotificationPresentationGate")

/// Decides whether the permission request and the settings page may go ahead for a
/// ``PresenterSelection`` (design 8.5.4, 8.5.5, S-13, SR-17), then calls their use cases.
///
/// Neither operation presents a view controller of its own, but both can bring up system UI (the
/// permission alert, the Settings app). They use the "not presenting" column of the C ABI design
/// part 1, 5.13.2 (`PresentationProcedure.requireForeground`): the app must be in the foreground,
/// settled or not.
///
/// | Presenter | Permission request | Settings page |
/// |---|---|---|
/// | `.firstActiveScene` | Requests at once (the behavior before 2.0.0) | Opens at once (the behavior before 2.0.0) |
/// | `.foreground`, `.viewController(_:)` | Reads the status first. Not `notDetermined`: answers from it without requesting (`authorized`, `provisional` and `ephemeral` are `true`). `notDetermined`: ``NotificationError/notForeground`` outside the foreground, otherwise requests | ``NotificationError/notForeground`` outside the foreground, otherwise opens |
///
/// The use cases only reach the data; they know nothing of the foreground.
struct NotificationPresentationGate: Sendable {

    private let statusUseCase: GetAuthorizationStatusUseCase
    private let requestUseCase: RequestNotificationPermissionUseCase
    private let openSettingsUseCase: OpenNotificationSettingsUseCase
    /// Whether `presenter` finds the app in the foreground (`PresentationProcedure.requireForeground`
    /// on the environment the gate was made with).
    private let isForeground: @MainActor @Sendable (PresenterSelection) -> Bool

    /// - Parameters:
    ///   - repository: The repository the use cases reach.
    ///   - makeEnvironment: The UIKit work (a fake in the tests), made per check.
    init<Environment: PresentationEnvironment>(
        repository: NotificationRepository,
        makeEnvironment: @escaping @MainActor @Sendable () -> Environment
    ) {
        logger.log(level: .libraryDebug, "[init] repository: \(String(describing: type(of: repository)), privacy: .public), environment: \(String(describing: Environment.self), privacy: .public)")
        statusUseCase = GetAuthorizationStatusUseCase(repository: repository)
        requestUseCase = RequestNotificationPermissionUseCase(repository: repository)
        openSettingsUseCase = OpenNotificationSettingsUseCase(repository: repository)
        isForeground = { presenter in
            logger.log(level: .libraryDebug, "[isForeground] presenter: \(presenter.logName, privacy: .public)")
            // The box only carries the procedure's verdict: a failed check closes it.
            let box = RequestBox()
            var proceeded = false
            PresentationProcedure.requireForeground(presenter: presenter, box: box, environment: makeEnvironment()) {
                proceeded = true
            }
            return proceeded
        }
    }

    /// Requests the permission as the table says.
    /// - Returns: `true` when granted, `false` when denied (or already denied), or the error.
    @MainActor
    func requestPermission(options: UNAuthorizationOptions, presenter: PresenterSelection) async -> Result<Bool, NotificationError> {
        logger.log(level: .libraryDebug, "[requestPermission] options: \(options.rawValue, privacy: .public), presenter: \(presenter.logName, privacy: .public)")
        if !Self.isFirstActiveScene(presenter) {
            let status = await statusUseCase.execute()
            guard status == .notDetermined else {
                let granted = Self.grants(status)
                logger.log(level: .libraryDebug, "[requestPermission] status: \(status.rawValue, privacy: .public), not requested, granted: \(granted, privacy: .public)")
                return .success(granted)
            }
            guard isForeground(presenter) else {
                logger.error("[requestPermission] the permission is not determined and the app is not in the foreground: not requested")
                return .failure(.notForeground)
            }
        }
        do {
            return .success(try await requestUseCase.execute(options: options))
        } catch {
            return .failure(error)
        }
    }

    /// Opens the app's notification settings page as the table says.
    @MainActor
    func openNotificationSettings(presenter: PresenterSelection) async -> Result<Void, NotificationError> {
        logger.log(level: .libraryDebug, "[openNotificationSettings] presenter: \(presenter.logName, privacy: .public)")
        if !Self.isFirstActiveScene(presenter), !isForeground(presenter) {
            logger.error("[openNotificationSettings] the app is not in the foreground: not opened")
            return .failure(.notForeground)
        }
        guard await openSettingsUseCase.execute() else {
            return .failure(.openSettingsFailed)
        }
        return .success(())
    }

    /// Whether `presenter` is `.firstActiveScene` (no foreground check, the behavior before 2.0.0).
    static func isFirstActiveScene(_ presenter: PresenterSelection) -> Bool {
        logger.log(level: .libraryDebug, "[isFirstActiveScene] presenter: \(presenter.logName, privacy: .public)")
        if case .firstActiveScene = presenter.kind { return true }
        return false
    }

    /// Whether a status that is not `notDetermined` lets the app post notifications.
    static func grants(_ status: NotificationAuthorizationStatus) -> Bool {
        logger.log(level: .libraryDebug, "[grants] status: \(status.rawValue, privacy: .public)")
        switch status {
        case .authorized, .provisional, .ephemeral:
            return true
        case .notDetermined, .denied, .unknown:
            return false
        }
    }
}
