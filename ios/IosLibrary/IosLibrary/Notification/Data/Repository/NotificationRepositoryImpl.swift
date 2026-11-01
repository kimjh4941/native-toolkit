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

    /// Creates a repository backed by `UNUserNotificationCenter.current()`.
    public init() {
        logger.log(level: .libraryDebug, "[init]")
        requestCenter = CurrentNotificationRequestCenter()
    }

    /// For tests: adds, removes and lists the requests through `requestCenter`.
    init(requestCenter: any NotificationRequestCenter) {
        logger.log(level: .libraryDebug, "[init] requestCenter: \(String(describing: type(of: requestCenter)), privacy: .public)")
        self.requestCenter = requestCenter
    }

    // MARK: - Throwing operations

    public func show(content: NotificationContent, trigger: NotificationTrigger?) async throws {
        logger.log(level: .libraryDebug, "[show] content.id: \(content.id, privacy: .public), trigger: \(String(describing: trigger), privacy: .private)")
        try rejectReservedKey(in: content, method: "show")
        let unContent = try makeUNContent(from: content)
        let unTrigger = trigger.map { makeTrigger(from: $0) }
        let request = UNNotificationRequest(identifier: content.id, content: unContent, trigger: unTrigger)
        do {
            try await requestCenter.add(request)
        } catch {
            throw NotificationError.addRequestFailed(error)
        }
    }

    public func update(identifier: String, content: NotificationContent, trigger: NotificationTrigger?) async throws {
        logger.log(level: .libraryDebug, "[update] identifier: \(identifier, privacy: .public), content.id: \(content.id, privacy: .public), trigger: \(String(describing: trigger), privacy: .private)")
        // Before anything is removed (design 8.3.3, SR-9).
        try rejectReservedKey(in: content, method: "update")
        requestCenter.removePendingNotificationRequests(withIdentifiers: [identifier])
        let unContent = try makeUNContent(from: content)
        let unTrigger = trigger.map { makeTrigger(from: $0) }
        let request = UNNotificationRequest(identifier: identifier, content: unContent, trigger: unTrigger)
        do {
            try await requestCenter.add(request)
        } catch {
            throw NotificationError.addRequestFailed(error)
        }
    }

    public func schedule(content: NotificationContent, trigger: NotificationTrigger, identifier: String) async throws {
        logger.log(level: .libraryDebug, "[schedule] identifier: \(identifier, privacy: .public), trigger: \(String(describing: trigger), privacy: .private)")
        try rejectReservedKey(in: content, method: "schedule")
        let unContent = try makeUNContent(from: content)
        let unTrigger = makeTrigger(from: trigger)
        let request = UNNotificationRequest(identifier: identifier, content: unContent, trigger: unTrigger)
        do {
            try await requestCenter.add(request)
        } catch {
            throw NotificationError.addRequestFailed(error)
        }
    }

    public func requestPermission(options: UNAuthorizationOptions) async throws -> Bool {
        logger.log(level: .libraryDebug, "[requestPermission] options: \(options.rawValue, privacy: .public)")
        do {
            return try await center.requestAuthorization(options: options)
        } catch {
            throw NotificationError.unknown(error)
        }
    }

    public func setBadgeCount(_ count: Int) async throws {
        logger.log(level: .libraryDebug, "[setBadgeCount] count: \(count, privacy: .public)")
        do {
            try await center.setBadgeCount(count)
        } catch {
            throw NotificationError.setBadgeCountFailed(error)
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

    public func openNotificationSettings() {
        logger.log(level: .libraryDebug, "[openNotificationSettings]")
        guard let url = URL(string: UIKit.UIApplication.openNotificationSettingsURLString) else { return }
        Task { @MainActor in
            await UIKit.UIApplication.shared.open(url)
        }
    }

    public func registerCategory(_ category: NotificationCategory) async {
        logger.log(level: .libraryDebug, "[registerCategory] identifier: \(category.identifier, privacy: .public)")
        var existing = await center.notificationCategories()
        existing.insert(makeUNCategory(from: category))
        center.setNotificationCategories(existing)
    }

    public func removeCategory(identifier: String) async {
        logger.log(level: .libraryDebug, "[removeCategory] identifier: \(identifier, privacy: .public)")
        var existing = await center.notificationCategories()
        existing = existing.filter { $0.identifier != identifier }
        center.setNotificationCategories(existing)
    }

    // MARK: - Private helpers

    /// Fails with ``NotificationError/reservedUserInfoKey`` when the userInfo uses the library's
    /// marker key. Called first, before anything is removed or added (design 8.3.3).
    private func rejectReservedKey(in content: NotificationContent, method: String) throws {
        logger.log(level: .libraryDebug, "[rejectReservedKey] content.id: \(content.id, privacy: .public), method: \(method, privacy: .public)")
        guard NotificationMarker.isReserved(in: content.userInfo) else { return }
        logger.error("[\(method, privacy: .public)] content.id: \(content.id, privacy: .public): the userInfo uses the key the library reserves; nothing was changed")
        throw NotificationError.reservedUserInfoKey
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

    private func makeUNAttachment(from attachment: NotificationAttachment) throws -> UNNotificationAttachment {
        do {
            return try UNNotificationAttachment(identifier: attachment.identifier, url: attachment.fileURL)
        } catch {
            throw NotificationError.attachmentLoadFailed(error)
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

    private func makeUNCategory(from category: NotificationCategory) -> UNNotificationCategory {
        let unActions: [UNNotificationAction] = category.actions.map { action in
            var options: UNNotificationActionOptions = []
            if action.options.contains(.authenticationRequired) { options.insert(.authenticationRequired) }
            if action.options.contains(.destructive) { options.insert(.destructive) }
            if action.options.contains(.foreground) { options.insert(.foreground) }
            if let symbolName = action.sfSymbolName {
                let icon = UNNotificationActionIcon(systemImageName: symbolName)
                return UNNotificationAction(identifier: action.identifier, title: action.title, options: options, icon: icon)
            }
            return UNNotificationAction(identifier: action.identifier, title: action.title, options: options)
        }
        let unTextInputActions: [UNTextInputNotificationAction] = category.textInputActions.map { action in
            return UNTextInputNotificationAction(
                identifier: action.identifier,
                title: action.title,
                options: [],
                icon: nil,
                textInputButtonTitle: action.buttonTitle,
                textInputPlaceholder: action.textInputPlaceholder
            )
        }
        let allActions: [UNNotificationAction] = unActions + unTextInputActions
        var unOptions: UNNotificationCategoryOptions = []
        if category.options.contains(.customDismissAction) { unOptions.insert(.customDismissAction) }
        if category.options.contains(.allowInCarPlay) { unOptions.insert(.allowInCarPlay) }
        if category.options.contains(.hiddenPreviewsShowTitle) { unOptions.insert(.hiddenPreviewsShowTitle) }
        // `allowAnnouncement` is not passed on: the system ignores it since iOS 15.
        return UNNotificationCategory(
            identifier: category.identifier,
            actions: allActions,
            intentIdentifiers: [],
            options: unOptions
        )
    }
}
