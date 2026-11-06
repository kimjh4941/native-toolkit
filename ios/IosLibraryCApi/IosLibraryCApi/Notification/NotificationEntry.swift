//
//  NotificationEntry.swift
//  IosLibraryCApi
//

// The entry points of Notification.h (C ABI design part 1, 5.3). Only @c @implementation functions;
// what they do is in NotificationReceiver.swift, NotificationContentBuilder.swift and NotificationHandles.swift.

@c @implementation
public func ntk_notification_install() -> ntk_notification_error {
    NotificationReceiver.install()
}

@c @implementation
public func ntk_notification_show_async(_ content: OpaquePointer?, _ trigger: UnsafePointer<ntk_notification_trigger>?,
                                        _ callback: ntk_notification_done_fn?, _ userData: UnsafeMutableRawPointer?, _ release: ntk_release_fn?) -> ntk_notification_error {
    NotificationReceiver.show(content, trigger, callback, userData, release)
}

@c @implementation
public func ntk_notification_update_async(_ identifier: UnsafePointer<CChar>?, _ content: OpaquePointer?,
                                          _ trigger: UnsafePointer<ntk_notification_trigger>?,
                                          _ callback: ntk_notification_done_fn?, _ userData: UnsafeMutableRawPointer?, _ release: ntk_release_fn?) -> ntk_notification_error {
    NotificationReceiver.update(identifier, content, trigger, callback, userData, release)
}

@c @implementation
public func ntk_notification_schedule_async(_ identifier: UnsafePointer<CChar>?, _ content: OpaquePointer?,
                                            _ trigger: UnsafePointer<ntk_notification_trigger>?,
                                            _ callback: ntk_notification_done_fn?, _ userData: UnsafeMutableRawPointer?, _ release: ntk_release_fn?) -> ntk_notification_error {
    NotificationReceiver.schedule(identifier, content, trigger, callback, userData, release)
}

@c @implementation
public func ntk_notification_remove_async(_ identifier: UnsafePointer<CChar>?, _ callback: ntk_notification_done_fn?,
                                          _ userData: UnsafeMutableRawPointer?, _ release: ntk_release_fn?) -> ntk_notification_error {
    NotificationReceiver.remove(identifier, callback, userData, release)
}

@c @implementation
public func ntk_notification_remove_all_async(_ callback: ntk_notification_done_fn?, _ userData: UnsafeMutableRawPointer?, _ release: ntk_release_fn?) -> ntk_notification_error {
    NotificationReceiver.removeAll(callback, userData, release)
}

@c @implementation
public func ntk_notification_cancel_scheduled_async(_ identifier: UnsafePointer<CChar>?, _ callback: ntk_notification_done_fn?,
                                                    _ userData: UnsafeMutableRawPointer?, _ release: ntk_release_fn?) -> ntk_notification_error {
    NotificationReceiver.cancelScheduled(identifier, callback, userData, release)
}

@c @implementation
public func ntk_notification_cancel_all_scheduled_async(_ callback: ntk_notification_done_fn?, _ userData: UnsafeMutableRawPointer?, _ release: ntk_release_fn?) -> ntk_notification_error {
    NotificationReceiver.cancelAllScheduled(callback, userData, release)
}

@c @implementation
public func ntk_notification_get_scheduled_async(_ callback: ntk_notification_list_fn?, _ userData: UnsafeMutableRawPointer?, _ release: ntk_release_fn?) -> ntk_notification_error {
    NotificationReceiver.getScheduled(callback, userData, release)
}

@c @implementation
public func ntk_notification_get_delivered_async(_ callback: ntk_notification_list_fn?, _ userData: UnsafeMutableRawPointer?, _ release: ntk_release_fn?) -> ntk_notification_error {
    NotificationReceiver.getDelivered(callback, userData, release)
}

@c @implementation
public func ntk_notification_request_permission_async(_ options: UInt32, _ callback: ntk_notification_permission_fn?,
                                                      _ userData: UnsafeMutableRawPointer?, _ release: ntk_release_fn?) -> ntk_notification_error {
    NotificationReceiver.requestPermission(options, callback, userData, release)
}

@c @implementation
public func ntk_notification_get_authorization_status_async(_ callback: ntk_notification_status_fn?,
                                                            _ userData: UnsafeMutableRawPointer?, _ release: ntk_release_fn?) -> ntk_notification_error {
    NotificationReceiver.authorizationStatus(callback, userData, release)
}

@c @implementation
public func ntk_notification_has_permission_async(_ callback: ntk_notification_permission_fn?,
                                                  _ userData: UnsafeMutableRawPointer?, _ release: ntk_release_fn?) -> ntk_notification_error {
    NotificationReceiver.hasPermission(callback, userData, release)
}

@c @implementation
public func ntk_notification_open_settings_async(_ callback: ntk_notification_done_fn?, _ userData: UnsafeMutableRawPointer?, _ release: ntk_release_fn?) -> ntk_notification_error {
    NotificationReceiver.openSettings(callback, userData, release)
}

@c @implementation
public func ntk_notification_set_badge_count_async(_ count: Int32, _ callback: ntk_notification_done_fn?,
                                                   _ userData: UnsafeMutableRawPointer?, _ release: ntk_release_fn?) -> ntk_notification_error {
    NotificationReceiver.setBadgeCount(count, callback, userData, release)
}

@c @implementation
public func ntk_notification_register_category_async(_ category: UnsafePointer<ntk_notification_category>?,
                                                     _ callback: ntk_notification_done_fn?, _ userData: UnsafeMutableRawPointer?, _ release: ntk_release_fn?) -> ntk_notification_error {
    NotificationReceiver.registerCategory(category, callback, userData, release)
}

@c @implementation
public func ntk_notification_remove_category_async(_ identifier: UnsafePointer<CChar>?, _ callback: ntk_notification_done_fn?,
                                                   _ userData: UnsafeMutableRawPointer?, _ release: ntk_release_fn?) -> ntk_notification_error {
    NotificationReceiver.removeCategory(identifier, callback, userData, release)
}

@c @implementation
public func ntk_notification_content_create(_ id: UnsafePointer<CChar>?, _ title: UnsafePointer<CChar>?,
                                            _ outContent: UnsafeMutablePointer<OpaquePointer?>?) -> ntk_notification_error {
    NotificationContentBuilders.create(id, title, outContent)
}

@c @implementation
public func ntk_notification_content_free(_ content: OpaquePointer?) {
    Handle.free(content)
}

@c @implementation
public func ntk_notification_content_set_subtitle(_ content: OpaquePointer?, _ subtitle: UnsafePointer<CChar>?) -> ntk_notification_error {
    NotificationContentBuilders.setSubtitle(content, subtitle)
}

@c @implementation
public func ntk_notification_content_set_body(_ content: OpaquePointer?, _ body: UnsafePointer<CChar>?) -> ntk_notification_error {
    NotificationContentBuilders.setBody(content, body)
}

@c @implementation
public func ntk_notification_content_set_badge(_ content: OpaquePointer?, _ badge: Int32) -> ntk_notification_error {
    NotificationContentBuilders.setBadge(content, badge)
}

@c @implementation
public func ntk_notification_content_set_sound(_ content: OpaquePointer?, _ kind: ntk_notification_sound_kind,
                                               _ name: UnsafePointer<CChar>?) -> ntk_notification_error {
    NotificationContentBuilders.setSound(content, kind, name)
}

@c @implementation
public func ntk_notification_content_set_category(_ content: OpaquePointer?, _ identifier: UnsafePointer<CChar>?) -> ntk_notification_error {
    NotificationContentBuilders.setCategory(content, identifier)
}

@c @implementation
public func ntk_notification_content_set_interruption_level(_ content: OpaquePointer?,
                                                            _ level: ntk_notification_interruption_level) -> ntk_notification_error {
    NotificationContentBuilders.setInterruptionLevel(content, level)
}

@c @implementation
public func ntk_notification_content_set_thread(_ content: OpaquePointer?, _ identifier: UnsafePointer<CChar>?) -> ntk_notification_error {
    NotificationContentBuilders.setThread(content, identifier)
}

@c @implementation
public func ntk_notification_content_set_target_content(_ content: OpaquePointer?, _ identifier: UnsafePointer<CChar>?) -> ntk_notification_error {
    NotificationContentBuilders.setTargetContent(content, identifier)
}

@c @implementation
public func ntk_notification_content_set_relevance_score(_ content: OpaquePointer?, _ score: Double) -> ntk_notification_error {
    NotificationContentBuilders.setRelevanceScore(content, score)
}

@c @implementation
public func ntk_notification_content_set_filter_criteria(_ content: OpaquePointer?, _ criteria: UnsafePointer<CChar>?) -> ntk_notification_error {
    NotificationContentBuilders.setFilterCriteria(content, criteria)
}

@c @implementation
public func ntk_notification_content_set_user_info_json(_ content: OpaquePointer?, _ json: UnsafePointer<CChar>?) -> ntk_notification_error {
    NotificationContentBuilders.setUserInfoJson(content, json)
}

@c @implementation
public func ntk_notification_content_add_attachment(_ content: OpaquePointer?, _ identifier: UnsafePointer<CChar>?,
                                                    _ fileURL: UnsafePointer<CChar>?) -> ntk_notification_error {
    NotificationContentBuilders.addAttachment(content, identifier, fileURL)
}

@c @implementation
public func ntk_notification_list_count(_ list: OpaquePointer?) -> Int {
    NotificationHandles.count(list)
}

@c @implementation
public func ntk_notification_list_identifier_at(_ list: OpaquePointer?, _ index: Int, _ outSize: UnsafeMutablePointer<Int>?) -> UnsafePointer<CChar>? {
    NotificationHandles.identifier(list, index, outSize)
}

@c @implementation
public func ntk_notification_list_title_at(_ list: OpaquePointer?, _ index: Int, _ outSize: UnsafeMutablePointer<Int>?) -> UnsafePointer<CChar>? {
    NotificationHandles.title(list, index, outSize)
}

@c @implementation
public func ntk_notification_list_subtitle_at(_ list: OpaquePointer?, _ index: Int, _ outSize: UnsafeMutablePointer<Int>?) -> UnsafePointer<CChar>? {
    NotificationHandles.subtitle(list, index, outSize)
}

@c @implementation
public func ntk_notification_list_body_at(_ list: OpaquePointer?, _ index: Int, _ outSize: UnsafeMutablePointer<Int>?) -> UnsafePointer<CChar>? {
    NotificationHandles.body(list, index, outSize)
}

@c @implementation
public func ntk_notification_list_category_at(_ list: OpaquePointer?, _ index: Int, _ outSize: UnsafeMutablePointer<Int>?) -> UnsafePointer<CChar>? {
    NotificationHandles.category(list, index, outSize)
}

@c @implementation
public func ntk_notification_list_date_millis_at(_ list: OpaquePointer?, _ index: Int) -> Int64 {
    NotificationHandles.dateMillis(list, index)
}

@c @implementation
public func ntk_notification_list_free(_ list: OpaquePointer?) {
    Handle.free(list)
}
