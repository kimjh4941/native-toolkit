//
//  NotificationRepositoryImpl.swift
//  IosLibrary
//

import CoreLocation
import Foundation
import os
import UIKit
import UserNotifications

private let logger = Logger(subsystem: "com.jonghyunkim.nativetoolkit.IosLibrary", category: "NotificationRepositoryImpl")

/// The requests part of `UNUserNotificationCenter` the repository uses to add, remove and list
/// requests. The library's is ``CurrentNotificationRequestCenter``; tests pass a stand-in, because
/// the test host app has no notification permission and the system keeps no request then.
protocol NotificationRequestCenter: Sendable {
    func add(_ request: UNNotificationRequest) async throws
    func removePendingNotificationRequests(withIdentifiers identifiers: [String])
    func removeAllPendingNotificationRequests()
    func pendingNotificationRequests() async -> [UNNotificationRequest]
}

/// `UNUserNotificationCenter.current()`, read per call (it is not `Sendable`).
struct CurrentNotificationRequestCenter: NotificationRequestCenter {
    func add(_ request: UNNotificationRequest) async throws {
        logger.log(level: .libraryDebug, "[CurrentNotificationRequestCenter.add] identifier: \(request.identifier, privacy: .public)")
        try await UNUserNotificationCenter.current().add(request)
    }

    func removePendingNotificationRequests(withIdentifiers identifiers: [String]) {
        logger.log(level: .libraryDebug, "[CurrentNotificationRequestCenter.removePendingNotificationRequests] identifiers: \(identifiers, privacy: .public)")
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: identifiers)
    }

    func removeAllPendingNotificationRequests() {
        logger.log(level: .libraryDebug, "[CurrentNotificationRequestCenter.removeAllPendingNotificationRequests]")
        UNUserNotificationCenter.current().removeAllPendingNotificationRequests()
    }

    func pendingNotificationRequests() async -> [UNNotificationRequest] {
        logger.log(level: .libraryDebug, "[CurrentNotificationRequestCenter.pendingNotificationRequests]")
        return await UNUserNotificationCenter.current().pendingNotificationRequests()
    }
}

/// Concrete implementation of `NotificationRepository` backed by `UNUserNotificationCenter`.
///
/// `show`, `update` and `schedule` check the userInfo first, before anything is removed or added
/// (design 8.3.3, 8.5.3, SR-9): the library's reserved key (``NotificationError/reservedUserInfoKey``),
/// then whether it is a property list (``NotificationError/invalidUserInfo``). Before any attachment
/// is made, the file of every attachment must exist: a file that does not exist (or that the
/// process cannot see) is ``NotificationError/attachmentLoadFailed(identifier:detail:)`` with
/// `NSCocoaErrorDomain` and `NSFileReadNoSuchFileError` (the system would only reject the whole
/// request in `add`). Only file URLs (`isFileURL`) are checked; any other URL is left to the system
/// as before (`update` may then have removed the pending request when `add` fails). `update` also
/// makes the content (with its attachments) and the trigger before it removes the pending request,
/// so an `update` rejected by a check or a failed attachment leaves the pending request it would
/// replace in place. A file removed after the check still fails in `add`
/// (``NotificationError/addRequestFailed(_:)``), after `update` removed the pending request. The
/// changes to the categories go through
/// the one queue of the process (`NotificationCategoryQueue`, design 8.5.6), whichever repository
/// makes them.
///
/// ## Threading
/// The repository is `Sendable` and may be called from any thread. It holds no mutable state and
/// does not store the notification center: `UNUserNotificationCenter` is not `Sendable`, and
/// `UNUserNotificationCenter.current()` is the only instance an app can obtain, so each operation
/// reads it when it runs.
public final class NotificationRepositoryImpl: NotificationRepository {

    /// The app's notification center, read per operation (see the type's Threading section).
    private var center: UNUserNotificationCenter { .current() }
    /// Where requests are added, removed and listed (`center` in the library).
    private let requestCenter: any NotificationRequestCenter
    /// Where the changes to the categories are queued (the process's queue in the library).
    let categoryQueue: NotificationCategoryQueue

    /// Creates a repository backed by `UNUserNotificationCenter.current()`.
    public init() {
        logger.log(level: .libraryDebug, "[init]")
        requestCenter = CurrentNotificationRequestCenter()
        categoryQueue = .shared
    }

    /// For tests: adds, removes and lists the requests through `requestCenter`, and queues the
    /// category changes on `categoryQueue`.
    init(requestCenter: any NotificationRequestCenter, categoryQueue: NotificationCategoryQueue = .shared) {
        logger.log(level: .libraryDebug, "[init] requestCenter: \(String(describing: type(of: requestCenter)), privacy: .public), categoryQueue: \(categoryQueue === NotificationCategoryQueue.shared ? "shared" : "provided", privacy: .public)")
        self.requestCenter = requestCenter
        self.categoryQueue = categoryQueue
    }

    // MARK: - Throwing operations

    public func show(content: NotificationContent, trigger: NotificationTrigger?) async throws {
        logger.log(level: .libraryDebug, "[show] content.id: \(content.id, privacy: .public), trigger: \(String(describing: trigger), privacy: .private)")
        try checkUserInfo(of: content, method: "show")
        let unContent = try makeUNContent(from: content)
        let unTrigger = trigger.map { makeTrigger(from: $0) }
        let request = UNNotificationRequest(identifier: content.id, content: unContent, trigger: unTrigger)
        try await add(request, method: "show")
    }

    public func update(identifier: String, content: NotificationContent, trigger: NotificationTrigger?) async throws {
        logger.log(level: .libraryDebug, "[update] identifier: \(identifier, privacy: .public), content.id: \(content.id, privacy: .public), trigger: \(String(describing: trigger), privacy: .private)")
        // Before anything is removed (design 8.3.3, 8.5.3, SR-9): the checks, then the content
        // and the trigger, whose attachments can fail (`attachmentLoadFailed`, also for a missing
        // file).
        try checkUserInfo(of: content, method: "update")
        let unContent = try makeUNContent(from: content)
        let unTrigger = trigger.map { makeTrigger(from: $0) }
        let request = UNNotificationRequest(identifier: identifier, content: unContent, trigger: unTrigger)
        requestCenter.removePendingNotificationRequests(withIdentifiers: [identifier])
        try await add(request, method: "update")
    }

    public func schedule(content: NotificationContent, trigger: NotificationTrigger, identifier: String) async throws {
        logger.log(level: .libraryDebug, "[schedule] identifier: \(identifier, privacy: .public), trigger: \(String(describing: trigger), privacy: .private)")
        try checkUserInfo(of: content, method: "schedule")
        let unContent = try makeUNContent(from: content)
        let unTrigger = makeTrigger(from: trigger)
        let request = UNNotificationRequest(identifier: identifier, content: unContent, trigger: unTrigger)
        try await add(request, method: "schedule")
    }

    public func requestPermission(options: UNAuthorizationOptions) async throws -> Bool {
        logger.log(level: .libraryDebug, "[requestPermission] options: \(options.rawValue, privacy: .public)")
        do {
            return try await center.requestAuthorization(options: options)
        } catch {
            let detail = FailureDetail(systemError: error)
            logger.error("[requestPermission] failed: domain=\(detail.domain, privacy: .public), code=\(detail.code, privacy: .public)")
            throw NotificationError.authorizationFailed(detail)
        }
    }

    public func setBadgeCount(_ count: Int) async throws {
        logger.log(level: .libraryDebug, "[setBadgeCount] count: \(count, privacy: .public)")
        do {
            try await center.setBadgeCount(count)
        } catch {
            let detail = FailureDetail(systemError: error)
            logger.error("[setBadgeCount] failed: domain=\(detail.domain, privacy: .public), code=\(detail.code, privacy: .public)")
            throw NotificationError.setBadgeCountFailed(detail)
        }
    }

    // MARK: - Non-throwing operations

    public func cancel(identifier: String) async {
        logger.log(level: .libraryDebug, "[cancel] identifier: \(identifier, privacy: .public)")
        removePendingRequests(withIdentifiers: [identifier])
    }

    public func cancelAll() async {
        logger.log(level: .libraryDebug, "[cancelAll]")
        removeAllPendingRequests()
    }

    public func removeDelivered(identifier: String) async {
        logger.log(level: .libraryDebug, "[removeDelivered] identifier: \(identifier, privacy: .public)")
        center.removeDeliveredNotifications(withIdentifiers: [identifier])
    }

    public func removeAllDelivered() async {
        logger.log(level: .libraryDebug, "[removeAllDelivered]")
        center.removeAllDeliveredNotifications()
    }

    public func cancelScheduled(identifier: String) async {
        logger.log(level: .libraryDebug, "[cancelScheduled] identifier: \(identifier, privacy: .public)")
        removePendingRequests(withIdentifiers: [identifier])
    }

    public func cancelAllScheduled() async {
        logger.log(level: .libraryDebug, "[cancelAllScheduled]")
        removeAllPendingRequests()
    }

    public func getScheduled() async -> [ScheduledNotification] {
        logger.log(level: .libraryDebug, "[getScheduled]")
        let requests = await requestCenter.pendingNotificationRequests()
        return requests.map { request in
            let content = request.content
            return ScheduledNotification(
                identifier: request.identifier,
                title: content.title,
                subtitle: content.subtitle.isEmpty ? nil : content.subtitle,
                body: content.body.isEmpty ? nil : content.body,
                categoryIdentifier: content.categoryIdentifier,
                userInfo: NotificationMarker.removing(from: content.userInfo)
            )
        }
    }

    public func getDelivered() async -> [ActiveNotification] {
        logger.log(level: .libraryDebug, "[getDelivered]")
        let delivered = await center.deliveredNotifications()
        return delivered.map { notification in
            Self.activeNotification(identifier: notification.request.identifier, date: notification.date,
                                    content: notification.request.content)
        }
    }

    /// The delivered notification handed back for `content`: its values, and the userInfo without
    /// the library's marker (design 8.3.3). Separate from ``getDelivered()`` so that tests can
    /// check it with a `UNMutableNotificationContent` (they cannot make a `UNNotification`).
    static func activeNotification(identifier: String, date: Date, content: UNNotificationContent) -> ActiveNotification {
        logger.log(level: .libraryDebug, "[activeNotification] identifier: \(identifier, privacy: .public), date: \(date.timeIntervalSince1970, privacy: .public), content.userInfoKeys: \(content.userInfo.count, privacy: .public)")
        return ActiveNotification(
            identifier: identifier,
            title: content.title,
            subtitle: content.subtitle.isEmpty ? nil : content.subtitle,
            body: content.body.isEmpty ? nil : content.body,
            categoryIdentifier: content.categoryIdentifier,
            date: date,
            userInfo: NotificationMarker.removing(from: content.userInfo)
        )
    }

    public func authorizationStatus() async -> NotificationAuthorizationStatus {
        logger.log(level: .libraryDebug, "[authorizationStatus]")
        let settings = await center.notificationSettings()
        switch settings.authorizationStatus {
        case .notDetermined:
            return .notDetermined
        case .denied:
            return .denied
        case .authorized:
            return .authorized
        case .provisional:
            return .provisional
        case .ephemeral:
            return .ephemeral
        @unknown default:
            return .unknown
        }
    }

    /// Opens `UIApplication.openNotificationSettingsURLString` on the main actor and returns
    /// what `UIApplication.open(_:)` reported.
    public func openNotificationSettings() async -> Bool {
        logger.log(level: .libraryDebug, "[openNotificationSettings]")
        guard let url = URL(string: UIKit.UIApplication.openNotificationSettingsURLString) else {
            logger.error("[openNotificationSettings] the settings URL could not be made")
            return false
        }
        let opened = await Self.open(url)
        if !opened {
            logger.error("[openNotificationSettings] the system did not open the settings page")
        }
        return opened
    }

    /// `UIApplication.shared.open(_:)`, which is main actor only.
    @MainActor
    private static func open(_ url: URL) async -> Bool {
        logger.log(level: .libraryDebug, "[open] url: \(url.absoluteString, privacy: .public)")
        return await UIKit.UIApplication.shared.open(url)
    }

    /// Queues the registration on the process's category queue and returns once it is applied.
    public func registerCategory(_ category: NotificationCategory) async {
        logger.log(level: .libraryDebug, "[registerCategory] identifier: \(category.identifier, privacy: .public)")
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            categoryQueue.enqueue(.register(category)) { continuation.resume() }
        }
    }

    /// Queues the removal on the process's category queue and returns once it is applied.
    public func removeCategory(identifier: String) async {
        logger.log(level: .libraryDebug, "[removeCategory] identifier: \(identifier, privacy: .public)")
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            categoryQueue.enqueue(.remove(identifier: identifier)) { continuation.resume() }
        }
    }

    /// Appends the change to the process's category queue inside this call (design S-P28).
    public func enqueueCategoryChange(_ change: NotificationCategoryChange, completion: @escaping @Sendable () -> Void) {
        logger.log(level: .libraryDebug, "[enqueueCategoryChange] change: \(change.logSummary, privacy: .public), completion: provided")
        categoryQueue.enqueue(change, completion: completion)
    }

    // MARK: - Private helpers

    /// The checks of the userInfo, first in `show`, `update` and `schedule`, before anything is
    /// removed or added (design 8.3.3, 8.5.3): the reserved key, then the property list.
    private func checkUserInfo(of content: NotificationContent, method: String) throws {
        logger.log(level: .libraryDebug, "[checkUserInfo] content.id: \(content.id, privacy: .public), method: \(method, privacy: .public), userInfoKeys: \(content.userInfo.count, privacy: .public)")
        if NotificationMarker.isReserved(in: content.userInfo) {
            logger.error("[\(method, privacy: .public)] content.id: \(content.id, privacy: .public): the userInfo uses the key the library reserves; nothing was changed")
            throw NotificationError.reservedUserInfoKey
        }
        if !Self.isPropertyList(content.userInfo) {
            logger.error("[\(method, privacy: .public)] content.id: \(content.id, privacy: .public): the userInfo holds a value that is not a property-list value; nothing was changed")
            throw NotificationError.invalidUserInfo
        }
    }

    /// Whether `userInfo` can be written as a binary property list (design S-P15): every value is
    /// a string, a number, a Boolean, a date, data, or an array or a dictionary (with string
    /// keys) of those.
    static func isPropertyList(_ userInfo: [String: Any]) -> Bool {
        logger.log(level: .libraryDebug, "[isPropertyList] keyCount: \(userInfo.count, privacy: .public)")
        return PropertyListSerialization.propertyList(userInfo, isValidFor: .binary)
    }

    /// Adds `request`, reporting a failure as ``NotificationError/addRequestFailed(_:)``.
    private func add(_ request: UNNotificationRequest, method: String) async throws {
        logger.log(level: .libraryDebug, "[add] identifier: \(request.identifier, privacy: .public), method: \(method, privacy: .public)")
        do {
            try await requestCenter.add(request)
        } catch {
            let detail = FailureDetail(systemError: error)
            logger.error("[\(method, privacy: .public)] identifier: \(request.identifier, privacy: .public): the system did not add the request: domain=\(detail.domain, privacy: .public), code=\(detail.code, privacy: .public)")
            throw NotificationError.addRequestFailed(detail)
        }
    }

    private func makeUNContent(from content: NotificationContent) throws -> UNMutableNotificationContent {
        let unContent = UNMutableNotificationContent()
        unContent.title = content.title
        if let subtitle = content.subtitle { unContent.subtitle = subtitle }
        if let body = content.body { unContent.body = body }
        if let badge = content.badge { unContent.badge = NSNumber(value: badge) }
        if let sound = content.sound { unContent.sound = makeUNSound(from: sound) }
        if let categoryIdentifier = content.categoryIdentifier {
            unContent.categoryIdentifier = categoryIdentifier
        }
        if let level = content.interruptionLevel {
            unContent.interruptionLevel = makeInterruptionLevel(from: level)
        }
        if let threadIdentifier = content.threadIdentifier {
            unContent.threadIdentifier = threadIdentifier
        }
        if let targetContentIdentifier = content.targetContentIdentifier {
            unContent.targetContentIdentifier = targetContentIdentifier
        }
        if let relevanceScore = content.relevanceScore {
            unContent.relevanceScore = relevanceScore
        }
        if let filterCriteria = content.filterCriteria {
            unContent.filterCriteria = filterCriteria
        }
        // The marker tells the library's notifications from the others (design 8.3.3, P1-9).
        unContent.userInfo = NotificationMarker.attaching(to: content.userInfo)
        try checkAttachmentFilesExist(content.attachments)
        unContent.attachments = try content.attachments.map { try makeUNAttachment(from: $0) }
        return unContent
    }

    private func removePendingRequests(withIdentifiers identifiers: [String]) {
        requestCenter.removePendingNotificationRequests(withIdentifiers: identifiers)
    }

    private func removeAllPendingRequests() {
        requestCenter.removeAllPendingNotificationRequests()
    }

    private func makeUNSound(from sound: NotificationSound) -> UNNotificationSound {
        switch sound {
        case .default: return .default
        case .defaultCritical: return .defaultCritical
        case .named(let name): return .init(named: UNNotificationSoundName(name))
        }
    }

    private func makeInterruptionLevel(from level: NotificationInterruptionLevel) -> UNNotificationInterruptionLevel {
        switch level {
        case .passive: return .passive
        case .active: return .active
        case .timeSensitive: return .timeSensitive
        case .critical: return .critical
        }
    }

    /// Checks that the file of every attachment exists, before any attachment is made (1b working
    /// notes, chapters 21 and 23). `UNNotificationAttachment` takes a missing file, and the system
    /// then rejects the whole request in `add` (`UNErrorDomain` 100), after `update` removed the
    /// pending request. Only file URLs (`isFileURL`) are checked; the system reports the others as
    /// before. A file the process cannot see is reported as missing too.
    private func checkAttachmentFilesExist(_ attachments: [NotificationAttachment]) throws {
        logger.log(level: .libraryDebug, "[checkAttachmentFilesExist] attachments: \(attachments.count, privacy: .public)")
        for attachment in attachments where attachment.fileURL.isFileURL {
            if !FileManager.default.fileExists(atPath: attachment.fileURL.path) {
                let detail = FailureDetail(domain: NSCocoaErrorDomain, code: NSFileReadNoSuchFileError)
                logger.error("[checkAttachmentFilesExist] identifier: \(attachment.identifier, privacy: .public): the file does not exist; nothing was changed: domain=\(detail.domain, privacy: .public), code=\(detail.code, privacy: .public)")
                throw NotificationError.attachmentLoadFailed(identifier: attachment.identifier, detail: detail)
            }
        }
    }

    private func makeUNAttachment(from attachment: NotificationAttachment) throws -> UNNotificationAttachment {
        do {
            return try UNNotificationAttachment(identifier: attachment.identifier, url: attachment.fileURL)
        } catch {
            let detail = FailureDetail(systemError: error)
            logger.error("[makeUNAttachment] identifier: \(attachment.identifier, privacy: .public): failed: domain=\(detail.domain, privacy: .public), code=\(detail.code, privacy: .public)")
            throw NotificationError.attachmentLoadFailed(identifier: attachment.identifier, detail: detail)
        }
    }

    private func makeTrigger(from trigger: NotificationTrigger) -> UNNotificationTrigger {
        switch trigger {
        case .timeInterval(let interval, let repeats):
            return UNTimeIntervalNotificationTrigger(timeInterval: interval, repeats: repeats)
        case .calendar(let components, let repeats):
            return UNCalendarNotificationTrigger(dateMatching: components, repeats: repeats)
        case .location(let identifier, let latitude, let longitude, let radius, let notifyOnEntry, let notifyOnExit):
            let center = CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
            let region = CLCircularRegion(center: center, radius: radius, identifier: identifier)
            region.notifyOnEntry = notifyOnEntry
            region.notifyOnExit = notifyOnExit
            return UNLocationNotificationTrigger(region: region, repeats: false)
        }
    }
}
