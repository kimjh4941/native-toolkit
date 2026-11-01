//
//  NotificationEventRouting.swift
//  IosLibraryExample
//
//  How the sample sets the library's notification events up at launch (Swift API design 12:
//  SA-06, SA-08, SA-11, SA-12, SA-18), and the second listener of SA-06.
//

import Foundation
import IosLibrary
import os
import UserNotifications

private let logger = Logger(subsystem: "com.jonghyunkim.ios.nativetoolkit.example", category: "NotificationEventRouting")
private let hostLogger = Logger(subsystem: "com.jonghyunkim.ios.nativetoolkit.example", category: "SampleHostNotificationDelegate")

@MainActor
final class NotificationEventRouting {

    static let shared = NotificationEventRouting()

    /// The delay of the `delayListener` test shape (SA-08).
    ///
    /// It races the system's `didReceive` of the launch response, which comes in the launch's
    /// first turns, before the first `didBecomeActive` (MS-05); 5 seconds keeps a wide margin and
    /// still delivers well inside the UI test's 10-second wait for the event.
    static let listenerDelay: TimeInterval = 5

    private let log = NotificationEventLog.shared
    private var firstRegistration: NotificationEventRegistration?
    private var secondRegistration: NotificationEventRegistration?
    private var settingsRegistration: NotificationEventRegistration?
    /// True while the first listener is being added: what it receives then was kept by the hub.
    private var addingFirstListener = false

    private init() {}

    /// Called once from `application(_:didFinishLaunchingWithOptions:)` (`SampleAppDelegate`), so
    /// the delegate is set before the launch returns (D-7).
    func start() {
        let (configuration, source) = SampleLaunchConfiguration.resolve()
        logger.debug("[start] mode: \(configuration.mode.rawValue, privacy: .public), source: \(source.rawValue, privacy: .public), hostDelegate: \(configuration.hostDelegate, privacy: .public)")
        if configuration.hostDelegate {
            // SA-12: the host's delegate is set first; the library's proxy goes in front of it.
            SampleHostNotificationDelegate.shared.install()
        }
        let install: String
        switch configuration.mode {
        case .legacyReceivers:
            // The deprecated path, as before 2.0.0: the receivers first, then setup().
            legacyEntries.setReceivers(
                action: { notificationId, actionId, _ in
                    logger.debug("[onActionReceived] notificationId: \(notificationId, privacy: .public), actionId: \(actionId, privacy: .public)")
                    NotificationEventLog.shared.record(kind: .action, notificationId: notificationId, actionId: actionId, userText: nil,
                                                       path: .legacy, isLaunchResponse: false, delivery: .live)
                },
                textInput: { notificationId, actionId, userText, _ in
                    logger.debug("[onTextInputActionReceived] notificationId: \(notificationId, privacy: .public), actionId: \(actionId, privacy: .public), userTextLength: \(userText.utf8.count, privacy: .public)")
                    NotificationEventLog.shared.record(kind: .textInput, notificationId: notificationId, actionId: actionId, userText: userText,
                                                       path: .legacy, isLaunchResponse: false, delivery: .live)
                }
            )
            legacyEntries.setup()
            install = "setup()"
        case .none, .delayListener:
            install = IosNotificationManager.installDelegate() == .installed ? "installed" : "notMainThread"
        }
        log.updateStatus { status in
            status.install = install
            status.isDelegateInstalled = IosNotificationManager.isDelegateInstalled
            status.mode = configuration.mode
            status.source = source
            status.hostDelegate = configuration.hostDelegate
        }
        addSettingsListener()
        switch configuration.mode {
        case .none:
            addFirstListener()
        case .delayListener:
            DispatchQueue.main.asyncAfter(deadline: .now() + Self.listenerDelay) {
                MainActor.assumeIsolated { self.addFirstListener() }
            }
        case .legacyReceivers:
            break
        }
    }

    /// The listener that records the last event (the screen's `notification.lastEvent.*`).
    private func addFirstListener() {
        logger.debug("[addFirstListener]")
        addingFirstListener = true
        defer { addingFirstListener = false }
        do {
            firstRegistration = try IosNotificationManager.shared.responses.addListener { [weak self] event, _ in
                self?.recordFirst(event)
            }
        } catch {
            logger.error("[addFirstListener] error: \(String(describing: error), privacy: .public)")
        }
    }

    private func recordFirst(_ event: NotificationResponseEvent) {
        logger.debug("[recordFirst] notificationId: \(event.notificationIdentifier, privacy: .public), actionId: \(event.actionIdentifier, privacy: .public), userTextLength: \(event.userText?.utf8.count ?? 0, privacy: .public), isLaunchResponse: \(event.isLaunchResponse, privacy: .public)")
        log.updateStatus { $0.firstListenerCount += 1 }
        log.record(
            kind: event.userText == nil ? .action : .textInput,
            notificationId: event.notificationIdentifier,
            actionId: event.actionIdentifier,
            userText: event.userText,
            path: .hub,
            isLaunchResponse: event.isLaunchResponse,
            delivery: addingFirstListener ? .held : .live
        )
    }

    private func addSettingsListener() {
        logger.debug("[addSettingsListener]")
        do {
            settingsRegistration = try IosNotificationManager.shared.settingsRequests.addListener { [weak self] request, _ in
                logger.debug("[settingsRequest] notificationId: \(request.notificationIdentifier ?? "nil", privacy: .public)")
                self?.log.updateStatus { status in
                    status.settingsRequestCount += 1
                    status.lastSettingsRequestId = request.notificationIdentifier
                }
            }
        } catch {
            logger.error("[addSettingsListener] error: \(String(describing: error), privacy: .public)")
        }
    }

    // MARK: SA-06

    /// Adds the second listener (counts only). Returns the result line.
    func addSecondListener() -> String {
        logger.debug("[addSecondListener] added: \(self.secondRegistration != nil, privacy: .public)")
        guard secondRegistration == nil else { return "[addSecondListener] already added" }
        do {
            secondRegistration = try IosNotificationManager.shared.responses.addListener { [weak self] event, _ in
                logger.debug("[secondListener] notificationId: \(event.notificationIdentifier, privacy: .public)")
                self?.log.updateStatus { $0.secondListenerCount += 1 }
            }
            log.updateStatus { $0.secondListenerState = "added" }
            return "[addSecondListener] added"
        } catch {
            return "[addSecondListener] error: \(error)"
        }
    }

    /// Removes the second listener. Returns the result line.
    func removeSecondListener() -> String {
        logger.debug("[removeSecondListener] added: \(self.secondRegistration != nil, privacy: .public)")
        guard let registration = secondRegistration else { return "[removeSecondListener] not added" }
        registration.remove()
        secondRegistration = nil
        log.updateStatus { $0.secondListenerState = "removed" }
        return "[removeSecondListener] removed"
    }

    // MARK: SA-08

    /// `launchResponse()` as a result line.
    func launchResponseLine() -> String {
        logger.debug("[launchResponseLine]")
        do {
            guard let event = try IosNotificationManager.shared.launchResponse() else {
                return "[launchResponse] nil"
            }
            return "[launchResponse] notificationId=\(event.notificationIdentifier), actionId=\(event.actionIdentifier), isLaunchResponse=\(event.isLaunchResponse)"
        } catch {
            return "[launchResponse] error: \(error)"
        }
    }

    // MARK: Deprecated entries

    /// The deprecated entries, called through a protocol so that the sample builds without
    /// deprecation warnings (the legacy path must call them).
    private var legacyEntries: any LegacyNotificationEntries { DeprecatedNotificationEntries() }
}

protocol LegacyNotificationEntries {
    func setReceivers(action: @escaping NotificationActionHandler, textInput: @escaping NotificationTextInputActionHandler)
    func setup()
}

private struct DeprecatedNotificationEntries: LegacyNotificationEntries {
    @available(*, deprecated)
    func setReceivers(action: @escaping NotificationActionHandler, textInput: @escaping NotificationTextInputActionHandler) {
        logger.debug("[setReceivers] action: provided, textInput: provided")
        IosNotificationManager.shared.onActionReceived = action
        IosNotificationManager.shared.onTextInputActionReceived = textInput
    }

    @available(*, deprecated)
    func setup() {
        logger.debug("[setup]")
        IosNotificationManager.setup()
    }
}

// MARK: - Host delegate (SA-12)

/// A host app's own `UNUserNotificationCenterDelegate`, set before the library's with
/// `-ntkSampleHostDelegate`. The library forwards the notifications that are not its own to it.
final class SampleHostNotificationDelegate: NSObject, UNUserNotificationCenterDelegate {

    @MainActor static let shared = SampleHostNotificationDelegate()

    static let notificationId = "sample-host-notification"
    static let title = "Host Notification"
    static let body = "Posted without the library"

    @MainActor
    func install() {
        hostLogger.debug("[install]")
        UNUserNotificationCenter.current().delegate = self
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping @Sendable (UNNotificationPresentationOptions) -> Void
    ) {
        hostLogger.debug("[willPresent] identifier: \(notification.request.identifier, privacy: .public)")
        NotificationEventLog.shared.updateStatus { $0.hostWillPresentCount += 1 }
        completionHandler([.banner, .list, .sound])
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping @Sendable () -> Void
    ) {
        let identifier = response.notification.request.identifier
        let action = response.actionIdentifier
        hostLogger.debug("[didReceive] identifier: \(identifier, privacy: .public), actionIdentifier: \(action, privacy: .public)")
        NotificationEventLog.shared.updateStatus { status in
            status.hostDidReceiveCount += 1
            status.hostLastNotificationId = identifier
            status.hostLastActionId = action
        }
        completionHandler()
    }

    /// Posts the host's own notification (not through the library, so without its marker).
    static func post(completion: @escaping @MainActor @Sendable (String) -> Void) {
        hostLogger.debug("[post] completion: provided")
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.userInfo = ["sampleHost": true]
        let request = UNNotificationRequest(identifier: notificationId, content: content, trigger: nil)
        UNUserNotificationCenter.current().add(request) { error in
            let line = "[showHostNotification] error: \(error.map { ($0 as NSError).domain } ?? "nil")"
            DispatchQueue.main.async {
                MainActor.assumeIsolated { completion(line) }
            }
        }
    }
}
