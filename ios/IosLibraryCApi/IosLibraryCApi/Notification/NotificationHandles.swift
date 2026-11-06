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
