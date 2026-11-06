//
//  NotificationEntry.swift
//  IosLibraryCApi
//

// The entry points of Notification.h (C ABI design part 1, 5.3). Only @c @implementation functions;
// what they do is in NotificationReceiver.swift and NotificationContentBuilder.swift.

@c @implementation
public func ntk_notification_install() -> ntk_notification_error {
    NotificationReceiver.install()
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
