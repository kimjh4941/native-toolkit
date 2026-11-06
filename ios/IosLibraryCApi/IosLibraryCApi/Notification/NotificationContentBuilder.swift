//
//  NotificationContentBuilder.swift
//  IosLibraryCApi
//

import Foundation
import IosLibrary

/// What an operation takes from the builder: a copy, so that the caller may change or free the builder as soon
/// as the call returns (part 1, 1.1; part 2, 6.3). `Sendable`, unlike `NotificationContent`, whose userInfo is
/// `Any`: that is made on the main thread, from this (part 2, 5.2).
struct NotificationContentValue: Sendable {
    var id: String
    var title: String
    var subtitle: String?
    var body: String?
    var badge: Int?
    var sound: NotificationSound? = .default
    var categoryIdentifier: String?
    var interruptionLevel: NotificationInterruptionLevel?
    var threadIdentifier: String?
    var targetContentIdentifier: String?
    var relevanceScore: Double?
    var filterCriteria: String?
    var userInfo: [String: NotificationUserInfoValue] = [:]
    var attachments: [NotificationAttachment] = []

    /// The library's content, with its defaults for what was not set (part 2, 6.3).
    func makeContent() -> NotificationContent {
        CApiLog.notification.debug("[makeContent] id length: \(id.utf8.count, privacy: .public)")
        return NotificationContent(id: id, title: title, subtitle: subtitle, body: body, badge: badge, sound: sound,
                                   categoryIdentifier: categoryIdentifier, interruptionLevel: interruptionLevel,
                                   threadIdentifier: threadIdentifier, targetContentIdentifier: targetContentIdentifier,
                                   relevanceScore: relevanceScore, filterCriteria: filterCriteria,
                                   userInfo: NotificationJson.propertyList(of: userInfo), attachments: attachments)
    }
}

/// What an `ntk_notification_content*` points to. Not thread safe, as the header says: the caller builds it on
/// one thread. A setter that rejects its value leaves the builder as it was.
final class NotificationContentBuilder {
    private(set) var value: NotificationContentValue

    init(_ value: NotificationContentValue) {
        CApiLog.notification.debug("[NotificationContentBuilder.init] id length: \(value.id.utf8.count, privacy: .public), title length: \(value.title.utf8.count, privacy: .public)")
        self.value = value
    }

    func update(_ change: (inout NotificationContentValue) -> Void) {
        CApiLog.notification.debug("[update] id length: \(self.value.id.utf8.count, privacy: .public), change: provided")
        change(&value)
    }
}

/// The builder's functions (part 2, 6.3). The id, title, subtitle, body and userInfo may be secrets: only whether
/// they are there and their length are logged.
enum NotificationContentBuilders {
    private static let none = ntk_notification_error(NTK_NOTIFICATION_ERROR_NONE)
    private static let invalid = ntk_notification_error(NTK_NOTIFICATION_ERROR_INVALID_PARAMETER)

    private static func builder(_ handle: OpaquePointer?) -> NotificationContentBuilder? {
        CApiLog.notification.debug("[builder] handle: \(handle == nil ? "nil" : "provided", privacy: .public)")
        return Handle.borrow(handle, as: NotificationContentBuilder.self)
    }

    /// The copy an operation takes on the calling thread, or nil for NULL and a handle of another type.
    static func snapshot(_ handle: OpaquePointer?) -> NotificationContentValue? {
        CApiLog.notification.debug("[snapshot] content: \(handle == nil ? "nil" : "provided", privacy: .public)")
        return builder(handle)?.value
    }

    /// The output is NULL on every path but success (R-8). An empty id is rejected: nothing would be left (M5).
    static func create(_ id: UnsafePointer<CChar>?, _ title: UnsafePointer<CChar>?,
                       _ outContent: UnsafeMutablePointer<OpaquePointer?>?) -> ntk_notification_error {
        CApiLog.notification.debug("[create] id: \(id == nil ? "nil" : "provided", privacy: .public), title: \(title == nil ? "nil" : "provided", privacy: .public), outContent: \(outContent == nil ? "nil" : "provided", privacy: .public)")
        outContent?.pointee = nil
        guard let outContent else {
            CApiLog.notification.error("[create] rejected: the output is NULL")
            return invalid
        }
        do throws(EntryError) {
            let identifier = try CApiString.required(id)
            guard !identifier.isEmpty else {
                CApiLog.notification.error("[create] rejected: the id is empty")
                return invalid
            }
            let text = try CApiString.required(title)
            outContent.pointee = Handle.retained(NotificationContentBuilder(NotificationContentValue(id: identifier, title: text)))
            CApiLog.notification.debug("[create] id length: \(identifier.utf8.count, privacy: .public), title length: \(text.utf8.count, privacy: .public)")
            return none
        } catch {
            return error.rawValue
        }
    }

    /// The common shape of a setter: NULL or a handle of another type is rejected, and so is what `change` throws,
    /// before anything changes.
    private static func set(_ handle: OpaquePointer?, function: String = #function,
                            _ change: () throws(EntryError) -> (inout NotificationContentValue) -> Void) -> ntk_notification_error {
        CApiLog.notification.debug("[set] function: \(function, privacy: .public), handle: \(handle == nil ? "nil" : "provided", privacy: .public), change: provided")
        guard let builder = builder(handle) else {
            CApiLog.notification.error("[\(function, privacy: .public)] rejected: not a builder")
            return invalid
        }
        do throws(EntryError) {
            builder.update(try change())
            return none
        } catch {
            CApiLog.notification.error("[\(function, privacy: .public)] rejected: \(error.rawValue, privacy: .public)")
            return error.rawValue
        }
    }

    // MARK: - Texts: NULL restores the default (none)

    static func setSubtitle(_ handle: OpaquePointer?, _ text: UnsafePointer<CChar>?) -> ntk_notification_error {
        CApiLog.notification.debug("[setSubtitle] content: \(handle == nil ? "nil" : "provided", privacy: .public), subtitle: \(text == nil ? "nil" : "provided", privacy: .public)")
        return set(handle) { () throws(EntryError) in
            let value = try CApiString.optional(text)
            return { $0.subtitle = value }
        }
    }

    static func setBody(_ handle: OpaquePointer?, _ text: UnsafePointer<CChar>?) -> ntk_notification_error {
        CApiLog.notification.debug("[setBody] content: \(handle == nil ? "nil" : "provided", privacy: .public), body: \(text == nil ? "nil" : "provided", privacy: .public)")
        return set(handle) { () throws(EntryError) in
            let value = try CApiString.optional(text)
            return { $0.body = value }
        }
    }

    static func setCategory(_ handle: OpaquePointer?, _ text: UnsafePointer<CChar>?) -> ntk_notification_error {
        CApiLog.notification.debug("[setCategory] content: \(handle == nil ? "nil" : "provided", privacy: .public), identifier: \(text == nil ? "nil" : "provided", privacy: .public)")
        return set(handle) { () throws(EntryError) in
            let value = try CApiString.optional(text)
            return { $0.categoryIdentifier = value }
        }
    }

    static func setThread(_ handle: OpaquePointer?, _ text: UnsafePointer<CChar>?) -> ntk_notification_error {
        CApiLog.notification.debug("[setThread] content: \(handle == nil ? "nil" : "provided", privacy: .public), identifier: \(text == nil ? "nil" : "provided", privacy: .public)")
        return set(handle) { () throws(EntryError) in
            let value = try CApiString.optional(text)
            return { $0.threadIdentifier = value }
        }
    }

    static func setTargetContent(_ handle: OpaquePointer?, _ text: UnsafePointer<CChar>?) -> ntk_notification_error {
        CApiLog.notification.debug("[setTargetContent] content: \(handle == nil ? "nil" : "provided", privacy: .public), identifier: \(text == nil ? "nil" : "provided", privacy: .public)")
        return set(handle) { () throws(EntryError) in
            let value = try CApiString.optional(text)
            return { $0.targetContentIdentifier = value }
        }
    }

    static func setFilterCriteria(_ handle: OpaquePointer?, _ text: UnsafePointer<CChar>?) -> ntk_notification_error {
        CApiLog.notification.debug("[setFilterCriteria] content: \(handle == nil ? "nil" : "provided", privacy: .public), criteria: \(text == nil ? "nil" : "provided", privacy: .public)")
        return set(handle) { () throws(EntryError) in
            let value = try CApiString.optional(text)
            return { $0.filterCriteria = value }
        }
    }

    // MARK: - Values

    /// 0 or more; -1 restores "not set".
    static func setBadge(_ handle: OpaquePointer?, _ badge: Int32) -> ntk_notification_error {
        CApiLog.notification.debug("[setBadge] content: \(handle == nil ? "nil" : "provided", privacy: .public), badge: \(badge, privacy: .public)")
        return set(handle) { () throws(EntryError) in
            guard badge >= -1 else { throw .invalidParameter }
            let value = badge == -1 ? nil : Int(badge)
            return { $0.badge = value }
        }
    }

    /// `name` is read only for NAMED, and must be there and not be empty then.
    static func setSound(_ handle: OpaquePointer?, _ kind: ntk_notification_sound_kind, _ name: UnsafePointer<CChar>?) -> ntk_notification_error {
        CApiLog.notification.debug("[setSound] content: \(handle == nil ? "nil" : "provided", privacy: .public), kind: \(kind, privacy: .public), name: \(name == nil ? "nil" : "provided", privacy: .public)")
        return set(handle) { () throws(EntryError) in
            let sound: NotificationSound?
            switch Int(kind) {
            case Int(NTK_NOTIFICATION_SOUND_DEFAULT): sound = .default
            case Int(NTK_NOTIFICATION_SOUND_DEFAULT_CRITICAL): sound = .defaultCritical
            case Int(NTK_NOTIFICATION_SOUND_NAMED):
                let file = try CApiString.required(name)
                guard !file.isEmpty else { throw .invalidParameter }
                sound = .named(file)
            case Int(NTK_NOTIFICATION_SOUND_NONE): sound = nil
            default: throw .invalidParameter
            }
            return { $0.sound = sound }
        }
    }

    static func setInterruptionLevel(_ handle: OpaquePointer?, _ level: ntk_notification_interruption_level) -> ntk_notification_error {
        CApiLog.notification.debug("[setInterruptionLevel] content: \(handle == nil ? "nil" : "provided", privacy: .public), level: \(level, privacy: .public)")
        return set(handle) { () throws(EntryError) in
            let value: NotificationInterruptionLevel?
            switch Int(level) {
            case Int(NTK_NOTIFICATION_INTERRUPTION_NOT_SET): value = nil
            case Int(NTK_NOTIFICATION_INTERRUPTION_PASSIVE): value = .passive
            case Int(NTK_NOTIFICATION_INTERRUPTION_ACTIVE): value = .active
            case Int(NTK_NOTIFICATION_INTERRUPTION_TIME_SENSITIVE): value = .timeSensitive
            case Int(NTK_NOTIFICATION_INTERRUPTION_CRITICAL): value = .critical
            default: throw .invalidParameter
            }
            return { $0.interruptionLevel = value }
        }
    }

    /// Finite, 0.0 to 1.0.
    static func setRelevanceScore(_ handle: OpaquePointer?, _ score: Double) -> ntk_notification_error {
        CApiLog.notification.debug("[setRelevanceScore] content: \(handle == nil ? "nil" : "provided", privacy: .public), score: \(score, privacy: .public)")
        return set(handle) { () throws(EntryError) in
            guard score.isFinite, (0.0...1.0).contains(score) else { throw .invalidParameter }
            return { $0.relevanceScore = score }
        }
    }

    /// NULL restores an empty userInfo.
    static func setUserInfoJson(_ handle: OpaquePointer?, _ json: UnsafePointer<CChar>?) -> ntk_notification_error {
        CApiLog.notification.debug("[setUserInfoJson] content: \(handle == nil ? "nil" : "provided", privacy: .public), json: \(json == nil ? "nil" : "provided", privacy: .public)")
        return set(handle) { () throws(EntryError) in
            let text = try CApiString.optional(json)
            let values = try text.map(NotificationJson.userInfo) ?? [:]
            return { $0.userInfo = values }
        }
    }

    /// Only an absolute `file://` URL with no host, or `localhost` (part 2, 6.3): anything else would fail only when
    /// the request is added (M4), so the entry rejects it. The scheme is matched without case, as the URL standard
    /// does (RFC 3986, 3.1). A space is taken as `URL(string:)` takes it: it encodes it.
    static func addAttachment(_ handle: OpaquePointer?, _ identifier: UnsafePointer<CChar>?, _ fileURL: UnsafePointer<CChar>?) -> ntk_notification_error {
        CApiLog.notification.debug("[addAttachment] content: \(handle == nil ? "nil" : "provided", privacy: .public), identifier: \(identifier == nil ? "nil" : "provided", privacy: .public), fileURL: \(fileURL == nil ? "nil" : "provided", privacy: .public)")
        return set(handle) { () throws(EntryError) in
            let name = try CApiString.required(identifier)
            let url = try attachmentURL(try CApiString.required(fileURL))
            let attachment = NotificationAttachment(identifier: name, fileURL: url)
            return { $0.attachments.append(attachment) }
        }
    }

    /// The URL of an attachment, or `invalidParameter`. The text may name what the user attaches: it is not logged.
    static func attachmentURL(_ text: String) throws(EntryError) -> URL {
        CApiLog.notification.debug("[attachmentURL] length: \(text.utf8.count, privacy: .public)")
        guard text.lowercased().hasPrefix("file://"), let url = URL(string: text), url.scheme?.lowercased() == "file", url.isFileURL else {
            CApiLog.notification.error("[attachmentURL] rejected: not a file:// URL")
            throw .invalidParameter
        }
        guard url.host == nil || url.host == "" || url.host?.lowercased() == "localhost" else {
            CApiLog.notification.error("[attachmentURL] rejected: a host")
            throw .invalidParameter
        }
        guard url.path.hasPrefix("/") else {
            CApiLog.notification.error("[attachmentURL] rejected: not an absolute path")
            throw .invalidParameter
        }
        return url
    }
}
