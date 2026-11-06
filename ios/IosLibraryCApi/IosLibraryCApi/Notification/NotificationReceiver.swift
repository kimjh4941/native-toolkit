//
//  NotificationReceiver.swift
//  IosLibraryCApi
//

import IosLibrary
import UserNotifications

/// What the functions of Notification.h do (part 2, 5.1, 5.2, 6.3): the entry's checks and copies in
/// `NotificationMapping` and the builder's snapshot, the accepted request to the main thread, the manager, the
/// handle and the completion. Notification text, userInfo and attachment names are never logged.
enum NotificationReceiver {
    /// The calls of `show`, `update` and `schedule`, with the status their pre-check reads (P2-10). Tests replace
    /// them, so that what the pre-check stops is seen without the notification center (part 2, 12.1).
    struct Adding: Sendable {
        var authorizationStatus: @MainActor @Sendable () async -> NotificationAuthorizationStatus
        var show: @MainActor @Sendable (NotificationContentValue, NotificationTrigger?) async throws -> Void
        var update: @MainActor @Sendable (String, NotificationContentValue, NotificationTrigger?) async throws -> Void
        var schedule: @MainActor @Sendable (String, NotificationContentValue, NotificationTrigger) async throws -> Void

        /// The manager's `async throws` forms (part 2, 5.2). The content is made here, on the main actor, from
        /// the Sendable copy the entry took (part 2, 5.2).
        static let manager = Adding(
            authorizationStatus: { await IosNotificationManager.shared.authorizationStatus() },
            show: { value, trigger in try await IosNotificationManager.shared.show(content: value.makeContent(), trigger: trigger) },
            update: { identifier, value, trigger in
                try await IosNotificationManager.shared.update(identifier: identifier, content: value.makeContent(), trigger: trigger)
            },
            schedule: { identifier, value, trigger in
                try await IosNotificationManager.shared.schedule(content: value.makeContent(), trigger: trigger, identifier: identifier)
            })
    }

    @MainActor static var adding = Adding.manager

    private static let none = ntk_notification_error(NTK_NOTIFICATION_ERROR_NONE)
    private static let unknown = ntk_notification_error(NTK_NOTIFICATION_ERROR_UNKNOWN)
    private static let systemCode: UInt32 = 0

    /// How a completion of one callback type carries an error, with no value: a handle is NULL and a value 0.
    typealias Failure<Callback> = @MainActor @Sendable (Callback, UnsafeMutableRawPointer?, ntk_notification_error) -> Void

    static let doneFailure: Failure<ntk_notification_done_fn> = { callback, userData, error in callback(userData, error, systemCode) }
    static let permissionFailure: Failure<ntk_notification_permission_fn> = { callback, userData, error in callback(userData, error, systemCode, 0) }
    static let statusFailure: Failure<ntk_notification_status_fn> = { callback, userData, error in
        callback(userData, error, systemCode, ntk_notification_authorization_status(NTK_NOTIFICATION_STATUS_UNKNOWN))
    }
    static let listFailure: Failure<ntk_notification_list_fn> = { callback, userData, error in callback(userData, error, systemCode, nil) }

    // MARK: - OP-25

    /// The main-thread check is `installDelegate()`'s own: it goes by the thread and never waits (part 1, 1.4).
    static func install() -> ntk_notification_error {
        CApiLog.notification.debug("[install]")
        VersionCheck.run()
        return error(for: IosNotificationManager.installDelegate())
    }

    static func error(for result: NotificationDelegateInstallResult) -> ntk_notification_error {
        CApiLog.notification.debug("[error] result: \(String(describing: result), privacy: .public)")
        switch result {
        case .installed:
            return ntk_notification_error(NTK_NOTIFICATION_ERROR_NONE)
        case .notMainThread:
            CApiLog.notification.error("[install] WRONG_THREAD: not on the main thread")
            return ntk_notification_error(NTK_NOTIFICATION_ERROR_WRONG_THREAD)
        @unknown default:
            CApiLog.notification.error("[install] UNKNOWN: \(String(describing: result), privacy: .public)")
            return ntk_notification_error(NTK_NOTIFICATION_ERROR_UNKNOWN)
        }
    }

    // MARK: - Accepting

    /// Steps 2 to 7 of acceptance (part 1, 5.7): a NULL callback and what `input` throws are rejected, with
    /// `release` on this thread. What `input` returns holds no pointer of the caller. No notification operation
    /// can be cancelled, so the CANCELED row of the registry never runs for them.
    private static func accept<Input: Sendable, Callback>(
        _ callback: Callback?, _ userData: UnsafeMutableRawPointer?, _ release: ntk_release_fn?,
        failure: @escaping Failure<Callback>, function: String = #function,
        input: () throws(EntryError) -> Input,
        start: @escaping @MainActor @Sendable (Input, Registration<Callback>) -> Void
    ) -> ntk_notification_error {
        guard let callback else {
            CApiLog.notification.error("[accept] \(function, privacy: .public): the callback is NULL")
            return Entry.reject(.invalidParameter, userData: userData, release: release, function: function)
        }
        do throws(EntryError) {
            let value = try input()
            return Registry.accept(callback: callback, userData: userData, release: release,
                                   canceled: { callback, userData, _ in failure(callback, userData, unknown) },
                                   start: { start(value, $0) })
        } catch {
            return Entry.reject(error, userData: userData, release: release, function: function)
        }
    }

    /// The content's copy, taken on the calling thread: the caller may change or free the builder once the
    /// function returns (part 1, 1.1).
    private static func content(_ handle: OpaquePointer?) throws(EntryError) -> NotificationContentValue {
        guard let value = NotificationContentBuilders.snapshot(handle) else {
            CApiLog.notification.error("[content] rejected: NULL or not a content")
            throw .invalidParameter
        }
        return value
    }

    @MainActor
    static func finishDone(_ registration: Registration<ntk_notification_done_fn>, _ error: ntk_notification_error,
                           function: String = #function) {
        if error != none {
            CApiLog.notification.error("[finishDone] function: \(function, privacy: .public), error: \(error, privacy: .public)")
        }
        registration.complete { callback, userData, _ in callback(userData, error, systemCode) }
    }

    /// The pre-check and the add (part 2, 5.2; P2-10): in a task on the main actor that nothing cancels. Without
    /// permission the add is not called. A status that changes right after the check is not caught.
    @MainActor
    static func add(_ registration: Registration<ntk_notification_done_fn>, function: String = #function,
                    _ operation: @escaping @MainActor @Sendable (Adding) async throws -> Void) {
        CApiLog.notification.debug("[add] function: \(function, privacy: .public), id: \(registration.id, privacy: .public)")
        let calls = adding
        Task { @MainActor in
            let status = await calls.authorizationStatus()
            guard NotificationMapping.allowsAdding(status) else {
                CApiLog.notification.error("[add] function: \(function, privacy: .public), PERMISSION_DENIED: status \(status.rawValue, privacy: .public)")
                finishDone(registration, ntk_notification_error(NTK_NOTIFICATION_ERROR_PERMISSION_DENIED), function: function)
                return
            }
            do {
                try await operation(calls)
                finishDone(registration, none, function: function)
            } catch {
                finishDone(registration, NotificationMapping.error(for: error), function: function)
            }
        }
    }

    // MARK: - OP-26, OP-27, OP-28

    static func show(_ content: OpaquePointer?, _ trigger: UnsafePointer<ntk_notification_trigger>?, _ callback: ntk_notification_done_fn?,
                     _ userData: UnsafeMutableRawPointer?, _ release: ntk_release_fn?) -> ntk_notification_error {
        CApiLog.notification.debug("[show] content: \(content == nil ? "nil" : "provided", privacy: .public), trigger: \(trigger == nil ? "nil" : "provided", privacy: .public), callback: \(callback == nil ? "nil" : "provided", privacy: .public), userData: \(String(describing: userData), privacy: .private), release: \(release == nil ? "nil" : "provided", privacy: .public)")
        return accept(callback, userData, release, failure: doneFailure, input: { () throws(EntryError) in
            (try Self.content(content), try NotificationMapping.trigger(trigger))
        }, start: { input, registration in
            add(registration) { calls in try await calls.show(input.0, input.1) }
        })
    }

    static func update(_ identifier: UnsafePointer<CChar>?, _ content: OpaquePointer?, _ trigger: UnsafePointer<ntk_notification_trigger>?,
                       _ callback: ntk_notification_done_fn?, _ userData: UnsafeMutableRawPointer?,
                       _ release: ntk_release_fn?) -> ntk_notification_error {
        CApiLog.notification.debug("[update] identifier: \(identifier == nil ? "nil" : "provided", privacy: .public), content: \(content == nil ? "nil" : "provided", privacy: .public), trigger: \(trigger == nil ? "nil" : "provided", privacy: .public), callback: \(callback == nil ? "nil" : "provided", privacy: .public), userData: \(String(describing: userData), privacy: .private), release: \(release == nil ? "nil" : "provided", privacy: .public)")
        return accept(callback, userData, release, failure: doneFailure, input: { () throws(EntryError) in
            (try NotificationMapping.requiredIdentifier(identifier), try Self.content(content), try NotificationMapping.trigger(trigger))
        }, start: { input, registration in
            add(registration) { calls in try await calls.update(input.0, input.1, input.2) }
        })
    }

    static func schedule(_ identifier: UnsafePointer<CChar>?, _ content: OpaquePointer?, _ trigger: UnsafePointer<ntk_notification_trigger>?,
                         _ callback: ntk_notification_done_fn?, _ userData: UnsafeMutableRawPointer?,
                         _ release: ntk_release_fn?) -> ntk_notification_error {
        CApiLog.notification.debug("[schedule] identifier: \(identifier == nil ? "nil" : "provided", privacy: .public), content: \(content == nil ? "nil" : "provided", privacy: .public), trigger: \(trigger == nil ? "nil" : "provided", privacy: .public), callback: \(callback == nil ? "nil" : "provided", privacy: .public), userData: \(String(describing: userData), privacy: .private), release: \(release == nil ? "nil" : "provided", privacy: .public)")
        return accept(callback, userData, release, failure: doneFailure, input: { () throws(EntryError) in
            (try NotificationMapping.requiredIdentifier(identifier), try Self.content(content), try NotificationMapping.scheduledTrigger(trigger))
        }, start: { input, registration in
            add(registration) { calls in try await calls.schedule(input.0, input.1, input.2) }
        })
    }

    // MARK: - OP-29 to OP-32

    /// The identifier of a removal: NULL is rejected, "" removes nothing and completes with NONE (part 2, 6.3).
    static func removalIdentifier(_ identifier: UnsafePointer<CChar>?) throws(EntryError) -> String {
        try CApiString.required(identifier)
    }

    static func remove(_ identifier: UnsafePointer<CChar>?, _ callback: ntk_notification_done_fn?, _ userData: UnsafeMutableRawPointer?,
                       _ release: ntk_release_fn?) -> ntk_notification_error {
        CApiLog.notification.debug("[remove] identifier: \(identifier == nil ? "nil" : "provided", privacy: .public), callback: \(callback == nil ? "nil" : "provided", privacy: .public), userData: \(String(describing: userData), privacy: .private), release: \(release == nil ? "nil" : "provided", privacy: .public)")
        return accept(callback, userData, release, failure: doneFailure, input: { () throws(EntryError) in
            try removalIdentifier(identifier)
        }, start: { identifier, registration in
            IosNotificationManager.shared.removeDelivered(identifier: identifier) { finishDone(registration, none) }
        })
    }

    static func removeAll(_ callback: ntk_notification_done_fn?, _ userData: UnsafeMutableRawPointer?,
                          _ release: ntk_release_fn?) -> ntk_notification_error {
        CApiLog.notification.debug("[removeAll] callback: \(callback == nil ? "nil" : "provided", privacy: .public), userData: \(String(describing: userData), privacy: .private), release: \(release == nil ? "nil" : "provided", privacy: .public)")
        return accept(callback, userData, release, failure: doneFailure, input: { () throws(EntryError) in () }, start: { _, registration in
            IosNotificationManager.shared.removeAllDelivered { finishDone(registration, none) }
        })
    }

    static func cancelScheduled(_ identifier: UnsafePointer<CChar>?, _ callback: ntk_notification_done_fn?, _ userData: UnsafeMutableRawPointer?,
                                _ release: ntk_release_fn?) -> ntk_notification_error {
        CApiLog.notification.debug("[cancelScheduled] identifier: \(identifier == nil ? "nil" : "provided", privacy: .public), callback: \(callback == nil ? "nil" : "provided", privacy: .public), userData: \(String(describing: userData), privacy: .private), release: \(release == nil ? "nil" : "provided", privacy: .public)")
        return accept(callback, userData, release, failure: doneFailure, input: { () throws(EntryError) in
            try removalIdentifier(identifier)
        }, start: { identifier, registration in
            IosNotificationManager.shared.cancelScheduled(identifier: identifier) { finishDone(registration, none) }
        })
    }

    static func cancelAllScheduled(_ callback: ntk_notification_done_fn?, _ userData: UnsafeMutableRawPointer?,
                                   _ release: ntk_release_fn?) -> ntk_notification_error {
        CApiLog.notification.debug("[cancelAllScheduled] callback: \(callback == nil ? "nil" : "provided", privacy: .public), userData: \(String(describing: userData), privacy: .private), release: \(release == nil ? "nil" : "provided", privacy: .public)")
        return accept(callback, userData, release, failure: doneFailure, input: { () throws(EntryError) in () }, start: { _, registration in
            IosNotificationManager.shared.cancelAllScheduled { finishDone(registration, none) }
        })
    }

    // MARK: - OP-33, OP-34

    @MainActor
    static func finishList(_ registration: Registration<ntk_notification_list_fn>, _ entries: [NotificationListEntry]) {
        CApiLog.notification.debug("[finishList] id: \(registration.id, privacy: .public), count: \(entries.count, privacy: .public)")
        // The handle is made in the delivery, so that one that nobody would receive is not made.
        registration.complete { callback, userData, _ in callback(userData, none, systemCode, NotificationHandles.makeList(entries)) }
    }

    static func getScheduled(_ callback: ntk_notification_list_fn?, _ userData: UnsafeMutableRawPointer?,
                             _ release: ntk_release_fn?) -> ntk_notification_error {
        CApiLog.notification.debug("[getScheduled] callback: \(callback == nil ? "nil" : "provided", privacy: .public), userData: \(String(describing: userData), privacy: .private), release: \(release == nil ? "nil" : "provided", privacy: .public)")
        return accept(callback, userData, release, failure: listFailure, input: { () throws(EntryError) in () }, start: { _, registration in
            IosNotificationManager.shared.getScheduled { finishList(registration, NotificationMapping.entries(of: $0)) }
        })
    }

    static func getDelivered(_ callback: ntk_notification_list_fn?, _ userData: UnsafeMutableRawPointer?,
                             _ release: ntk_release_fn?) -> ntk_notification_error {
        CApiLog.notification.debug("[getDelivered] callback: \(callback == nil ? "nil" : "provided", privacy: .public), userData: \(String(describing: userData), privacy: .private), release: \(release == nil ? "nil" : "provided", privacy: .public)")
        return accept(callback, userData, release, failure: listFailure, input: { () throws(EntryError) in () }, start: { _, registration in
            IosNotificationManager.shared.getDelivered { finishList(registration, NotificationMapping.entries(of: $0)) }
        })
    }

    // MARK: - OP-35 to OP-37

    /// A denial is NONE with 0 (P2-10); `authorized`, `provisional` and `ephemeral` are 1 (the library's answer).
    @MainActor
    static func finishPermission(_ registration: Registration<ntk_notification_permission_fn>, _ result: Result<Bool, NotificationError>) {
        CApiLog.notification.debug("[finishPermission] id: \(registration.id, privacy: .public)")
        switch result {
        case .success(let granted):
            registration.complete { callback, userData, _ in callback(userData, none, systemCode, granted ? 1 : 0) }
        case .failure(let failure):
            let error = NotificationMapping.error(for: failure)
            CApiLog.notification.error("[finishPermission] error: \(error, privacy: .public)")
            registration.complete { callback, userData, _ in permissionFailure(callback, userData, error) }
        }
    }

    /// The manager's `.foreground` form (P2-1): undecided and not in the foreground is NOT_FOREGROUND. It cannot
    /// be cancelled.
    static func requestPermission(_ options: UInt32, _ callback: ntk_notification_permission_fn?, _ userData: UnsafeMutableRawPointer?,
                                  _ release: ntk_release_fn?) -> ntk_notification_error {
        CApiLog.notification.debug("[requestPermission] options: \(options, privacy: .public), callback: \(callback == nil ? "nil" : "provided", privacy: .public), userData: \(String(describing: userData), privacy: .private), release: \(release == nil ? "nil" : "provided", privacy: .public)")
        return accept(callback, userData, release, failure: permissionFailure, input: { () throws(EntryError) in
            try NotificationMapping.permissionOptions(options).rawValue
        }, start: { rawOptions, registration in
            IosNotificationManager.shared.requestPermission(options: .init(rawValue: rawOptions), presenter: .foreground) {
                finishPermission(registration, $0)
            }
        })
    }

    /// The status never fails (P2-14).
    @MainActor
    static func finishStatus(_ registration: Registration<ntk_notification_status_fn>, _ status: NotificationAuthorizationStatus) {
        CApiLog.notification.debug("[finishStatus] id: \(registration.id, privacy: .public), status: \(status.rawValue, privacy: .public)")
        let value = NotificationMapping.status(of: status)
        registration.complete { callback, userData, _ in callback(userData, none, systemCode, value) }
    }

    @MainActor
    static func finishHasPermission(_ registration: Registration<ntk_notification_permission_fn>, _ granted: Bool) {
        CApiLog.notification.debug("[finishHasPermission] id: \(registration.id, privacy: .public), granted: \(granted, privacy: .public)")
        registration.complete { callback, userData, _ in callback(userData, none, systemCode, granted ? 1 : 0) }
    }

    static func authorizationStatus(_ callback: ntk_notification_status_fn?, _ userData: UnsafeMutableRawPointer?,
                                    _ release: ntk_release_fn?) -> ntk_notification_error {
        CApiLog.notification.debug("[authorizationStatus] callback: \(callback == nil ? "nil" : "provided", privacy: .public), userData: \(String(describing: userData), privacy: .private), release: \(release == nil ? "nil" : "provided", privacy: .public)")
        return accept(callback, userData, release, failure: statusFailure, input: { () throws(EntryError) in () }, start: { _, registration in
            IosNotificationManager.shared.authorizationStatus { finishStatus(registration, $0) }
        })
    }

    /// `authorized` or `provisional` is 1; `ephemeral` is 0 (the library's answer; part 2, 6.3).
    static func hasPermission(_ callback: ntk_notification_permission_fn?, _ userData: UnsafeMutableRawPointer?,
                              _ release: ntk_release_fn?) -> ntk_notification_error {
        CApiLog.notification.debug("[hasPermission] callback: \(callback == nil ? "nil" : "provided", privacy: .public), userData: \(String(describing: userData), privacy: .private), release: \(release == nil ? "nil" : "provided", privacy: .public)")
        return accept(callback, userData, release, failure: permissionFailure, input: { () throws(EntryError) in () }, start: { _, registration in
            IosNotificationManager.shared.hasPermission { finishHasPermission(registration, $0) }
        })
    }

    // MARK: - OP-38, OP-39

    @MainActor
    static func finishSettings(_ registration: Registration<ntk_notification_done_fn>, _ result: Result<Void, NotificationError>) {
        CApiLog.notification.debug("[finishSettings] id: \(registration.id, privacy: .public)")
        switch result {
        case .success:
            finishDone(registration, none)
        case .failure(let failure):
            finishDone(registration, NotificationMapping.error(for: failure))
        }
    }

    static func openSettings(_ callback: ntk_notification_done_fn?, _ userData: UnsafeMutableRawPointer?,
                             _ release: ntk_release_fn?) -> ntk_notification_error {
        CApiLog.notification.debug("[openSettings] callback: \(callback == nil ? "nil" : "provided", privacy: .public), userData: \(String(describing: userData), privacy: .private), release: \(release == nil ? "nil" : "provided", privacy: .public)")
        return accept(callback, userData, release, failure: doneFailure, input: { () throws(EntryError) in () }, start: { _, registration in
            IosNotificationManager.shared.openNotificationSettings(presenter: .foreground) { finishSettings(registration, $0) }
        })
    }

    static func setBadgeCount(_ count: Int32, _ callback: ntk_notification_done_fn?, _ userData: UnsafeMutableRawPointer?,
                              _ release: ntk_release_fn?) -> ntk_notification_error {
        CApiLog.notification.debug("[setBadgeCount] count: \(count, privacy: .public), callback: \(callback == nil ? "nil" : "provided", privacy: .public), userData: \(String(describing: userData), privacy: .private), release: \(release == nil ? "nil" : "provided", privacy: .public)")
        return accept(callback, userData, release, failure: doneFailure, input: { () throws(EntryError) in
            guard count >= 0 else {
                CApiLog.notification.error("[setBadgeCount] rejected: the count is negative")
                throw .invalidParameter
            }
            return Int(count)
        }, start: { count, registration in
            Task { @MainActor in
                do {
                    try await IosNotificationManager.shared.setBadgeCount(count)
                    finishDone(registration, none)
                } catch {
                    finishDone(registration, NotificationMapping.error(for: error))
                }
            }
        })
    }

    // MARK: - OP-40, OP-41

    /// The completion comes after the write and one read-back; what the read-back finds is only logged by the
    /// library (part 2, 6.3).
    static func registerCategory(_ category: UnsafePointer<ntk_notification_category>?, _ callback: ntk_notification_done_fn?,
                                 _ userData: UnsafeMutableRawPointer?, _ release: ntk_release_fn?) -> ntk_notification_error {
        CApiLog.notification.debug("[registerCategory] category: \(category == nil ? "nil" : "provided", privacy: .public), callback: \(callback == nil ? "nil" : "provided", privacy: .public), userData: \(String(describing: userData), privacy: .private), release: \(release == nil ? "nil" : "provided", privacy: .public)")
        return accept(callback, userData, release, failure: doneFailure, input: { () throws(EntryError) in
            try NotificationMapping.category(category)
        }, start: { category, registration in
            IosNotificationManager.shared.registerCategory(category) { finishDone(registration, none) }
        })
    }

    static func removeCategory(_ identifier: UnsafePointer<CChar>?, _ callback: ntk_notification_done_fn?, _ userData: UnsafeMutableRawPointer?,
                               _ release: ntk_release_fn?) -> ntk_notification_error {
        CApiLog.notification.debug("[removeCategory] identifier: \(identifier == nil ? "nil" : "provided", privacy: .public), callback: \(callback == nil ? "nil" : "provided", privacy: .public), userData: \(String(describing: userData), privacy: .private), release: \(release == nil ? "nil" : "provided", privacy: .public)")
        return accept(callback, userData, release, failure: doneFailure, input: { () throws(EntryError) in
            try removalIdentifier(identifier)
        }, start: { identifier, registration in
            IosNotificationManager.shared.removeCategory(identifier: identifier) { finishDone(registration, none) }
        })
    }
}
