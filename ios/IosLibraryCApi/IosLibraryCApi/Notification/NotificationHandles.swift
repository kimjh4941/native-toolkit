//
//  NotificationHandles.swift
//  IosLibraryCApi
//

/// What an `ntk_notification_list*` points to.
final class NotificationListHandle {
    final class Item {
        let identifier: HandleBuffer
        let title: HandleBuffer
        let subtitle: HandleBuffer?
        let body: HandleBuffer?
        let categoryIdentifier: HandleBuffer
        let dateMillis: Int64

        init(_ entry: NotificationListEntry) {
            identifier = NotificationHandles.buffer(entry.identifier)
            title = NotificationHandles.buffer(entry.title)
            subtitle = entry.subtitle.map(NotificationHandles.buffer)
            body = entry.body.map(NotificationHandles.buffer)
            categoryIdentifier = NotificationHandles.buffer(entry.categoryIdentifier)
            dateMillis = entry.dateMillis
        }
    }

    let items: [Item]

    init(_ entries: [NotificationListEntry]) {
        items = entries.map(Item.init)
    }
}

/// The readers of the list. NULL, a handle of another type and an index out of range read as nothing: NULL
/// with an `out_size` of 0, or 0 (part 2, 12.1). Reads and frees are not logged (part 1, 5.15), and the
/// values themselves never are: titles and bodies may be secrets.
enum NotificationHandles {
    fileprivate static func buffer(_ value: String) -> HandleBuffer {
        HandleBuffer(CApiString.outputUTF8(value))
    }

    static func makeList(_ entries: [NotificationListEntry]) -> OpaquePointer {
        CApiLog.notification.debug("[makeList] count: \(entries.count, privacy: .public)")
        return Handle.retained(NotificationListHandle(entries))
    }

    /// `size_t` arrives as `Int`: an index above `Int.max` is negative here, and out of range like any other.
    private static func item(_ handle: OpaquePointer?, _ index: Int) -> NotificationListHandle.Item? {
        guard let items = Handle.borrow(handle, as: NotificationListHandle.self)?.items, items.indices.contains(index) else {
            return nil
        }
        return items[index]
    }

    static func count(_ handle: OpaquePointer?) -> Int {
        Handle.borrow(handle, as: NotificationListHandle.self)?.items.count ?? 0
    }

    static func identifier(_ handle: OpaquePointer?, _ index: Int, _ outSize: UnsafeMutablePointer<Int>?) -> UnsafePointer<CChar>? {
        Handle.text(of: item(handle, index)?.identifier, outSize)
    }

    static func title(_ handle: OpaquePointer?, _ index: Int, _ outSize: UnsafeMutablePointer<Int>?) -> UnsafePointer<CChar>? {
        Handle.text(of: item(handle, index)?.title, outSize)
    }

    /// NULL when the notification has no subtitle.
    static func subtitle(_ handle: OpaquePointer?, _ index: Int, _ outSize: UnsafeMutablePointer<Int>?) -> UnsafePointer<CChar>? {
        Handle.text(of: item(handle, index)?.subtitle, outSize)
    }

    /// NULL when the notification has no body.
    static func body(_ handle: OpaquePointer?, _ index: Int, _ outSize: UnsafeMutablePointer<Int>?) -> UnsafePointer<CChar>? {
        Handle.text(of: item(handle, index)?.body, outSize)
    }

    static func category(_ handle: OpaquePointer?, _ index: Int, _ outSize: UnsafeMutablePointer<Int>?) -> UnsafePointer<CChar>? {
        Handle.text(of: item(handle, index)?.categoryIdentifier, outSize)
    }

    static func dateMillis(_ handle: OpaquePointer?, _ index: Int) -> Int64 {
        item(handle, index)?.dateMillis ?? 0
    }
}

/// What an `ntk_notification_interaction*` points to.
final class NotificationInteractionHandle {
    let kind: ntk_notification_event_kind
    let notificationIdentifier: HandleBuffer
    let actionIdentifier: HandleBuffer
    let categoryIdentifier: HandleBuffer
    let userText: HandleBuffer?
    let userInfoJson: HandleBuffer
    let isLaunch: Bool

    init(_ value: NotificationInteractionValue) {
        kind = value.kind
        notificationIdentifier = NotificationHandles.buffer(value.notificationIdentifier)
        actionIdentifier = NotificationHandles.buffer(value.actionIdentifier)
        categoryIdentifier = NotificationHandles.buffer(value.categoryIdentifier)
        userText = value.userText.map(NotificationHandles.buffer)
        userInfoJson = NotificationHandles.buffer(value.userInfoJson)
        isLaunch = value.isLaunch
    }
}

/// What an `ntk_notification_settings_request*` points to.
final class NotificationSettingsRequestHandle {
    let notificationIdentifier: HandleBuffer?

    init(_ notificationIdentifier: String?) {
        self.notificationIdentifier = notificationIdentifier.map(NotificationHandles.buffer)
    }
}

/// The readers of the event handles. NULL and a handle of another type read as nothing: NULL with an `out_size`
/// of 0, -1 for the kind (P2-29), 0 for `_is_launch`. The values are never logged.
extension NotificationHandles {
    static func makeInteraction(_ value: NotificationInteractionValue) -> OpaquePointer {
        CApiLog.notification.debug("[makeInteraction] kind: \(value.kind, privacy: .public), isLaunch: \(value.isLaunch, privacy: .public)")
        return Handle.retained(NotificationInteractionHandle(value))
    }

    static func makeSettingsRequest(_ notificationIdentifier: String?) -> OpaquePointer {
        CApiLog.notification.debug("[makeSettingsRequest] notificationIdentifier: \(notificationIdentifier == nil ? "nil" : "provided", privacy: .public)")
        return Handle.retained(NotificationSettingsRequestHandle(notificationIdentifier))
    }

    private static func interaction(_ handle: OpaquePointer?) -> NotificationInteractionHandle? {
        Handle.borrow(handle, as: NotificationInteractionHandle.self)
    }

    static func interactionKind(_ handle: OpaquePointer?) -> ntk_notification_event_kind {
        interaction(handle)?.kind ?? -1
    }

    static func interactionNotificationId(_ handle: OpaquePointer?, _ outSize: UnsafeMutablePointer<Int>?) -> UnsafePointer<CChar>? {
        Handle.text(of: interaction(handle)?.notificationIdentifier, outSize)
    }

    static func interactionActionId(_ handle: OpaquePointer?, _ outSize: UnsafeMutablePointer<Int>?) -> UnsafePointer<CChar>? {
        Handle.text(of: interaction(handle)?.actionIdentifier, outSize)
    }

    static func interactionCategoryId(_ handle: OpaquePointer?, _ outSize: UnsafeMutablePointer<Int>?) -> UnsafePointer<CChar>? {
        Handle.text(of: interaction(handle)?.categoryIdentifier, outSize)
    }

    static func interactionUserText(_ handle: OpaquePointer?, _ outSize: UnsafeMutablePointer<Int>?) -> UnsafePointer<CChar>? {
        Handle.text(of: interaction(handle)?.userText, outSize)
    }

    static func interactionUserInfoJson(_ handle: OpaquePointer?, _ outSize: UnsafeMutablePointer<Int>?) -> UnsafePointer<CChar>? {
        Handle.text(of: interaction(handle)?.userInfoJson, outSize)
    }

    static func interactionIsLaunch(_ handle: OpaquePointer?) -> Int32 {
        interaction(handle)?.isLaunch == true ? 1 : 0
    }

    static func settingsRequestNotificationId(_ handle: OpaquePointer?, _ outSize: UnsafeMutablePointer<Int>?) -> UnsafePointer<CChar>? {
        Handle.text(of: Handle.borrow(handle, as: NotificationSettingsRequestHandle.self)?.notificationIdentifier, outSize)
    }
}
