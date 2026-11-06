//
//  NotificationRows.swift
//  IosLibraryCApiUITestApp
//

import Foundation
import IosLibraryCApi
import os

private let logger = Logger(subsystem: "com.jonghyunkim.nativetoolkit.IosLibraryCApiUITestApp", category: "NotificationRows")

/// What a C completion reports through: `user_data` is this object, retained until `release`.
private final class RowCompletion {
    let report: RowReport

    init(_ report: RowReport) {
        self.report = report
    }

    static func userData(_ report: RowReport) -> UnsafeMutableRawPointer {
        logger.debug("[userData] rowId: \(report.rowId, privacy: .public)")
        return Unmanaged.passRetained(RowCompletion(report)).toOpaque()
    }

    static func from(_ userData: UnsafeMutableRawPointer?) -> RowCompletion {
        Unmanaged<RowCompletion>.fromOpaque(userData!).takeUnretainedValue()
    }
}

private func releaseRow(_ userData: UnsafeMutableRawPointer?) {
    Unmanaged<RowCompletion>.fromOpaque(userData!).release()
}

private func reportRejection(_ error: Int32, _ report: RowReport) {
    logger.debug("[reportRejection] rowId: \(report.rowId, privacy: .public), error: \(error, privacy: .public)")
    if error != 0 {
        report("rejected \(error)")
    }
}

/// `<error> <system code>`.
private func doneRow(_ userData: UnsafeMutableRawPointer?, _ error: Int32, _ systemCode: UInt32) {
    RowCompletion.from(userData).report("\(error) \(systemCode)")
}

/// `<error> <system code> granted=<0|1>`.
private func permissionRow(_ userData: UnsafeMutableRawPointer?, _ error: Int32, _ systemCode: UInt32, _ granted: Int32) {
    RowCompletion.from(userData).report("\(error) \(systemCode) granted=\(granted)")
}

/// `<error> <system code> status=<n>`.
private func statusRow(_ userData: UnsafeMutableRawPointer?, _ error: Int32, _ systemCode: UInt32, _ status: Int32) {
    RowCompletion.from(userData).report("\(error) \(systemCode) status=\(status)")
}

private func optionalText(_ pointer: UnsafePointer<CChar>?) -> String {
    pointer.map { String(cString: $0) } ?? "NULL"
}

/// `<error> <system code> count=<n> [<id>|<title>|<subtitle>|<body>|<category>|<date>]...`, sorted by identifier, where
/// `<date>` is `0` or `set` (a delivered one's time is not fixed). The values are the test's own: these rows run on
/// the simulator only.
private func listRow(_ userData: UnsafeMutableRawPointer?, _ error: Int32, _ systemCode: UInt32, _ list: OpaquePointer?) {
    defer { ntk_notification_list_free(list) }
    let count = ntk_notification_list_count(list)
    let items = (0..<count).map { index in
        let date = ntk_notification_list_date_millis_at(list, index)
        return "[\(optionalText(ntk_notification_list_identifier_at(list, index, nil)))|\(optionalText(ntk_notification_list_title_at(list, index, nil)))|\(optionalText(ntk_notification_list_subtitle_at(list, index, nil)))|\(optionalText(ntk_notification_list_body_at(list, index, nil)))|\(optionalText(ntk_notification_list_category_at(list, index, nil)))|\(date > 0 ? "set" : String(date))]"
    }.sorted()
    RowCompletion.from(userData).report("\(error) \(systemCode) count=\(count) \(items.joined())")
}

/// A content that lives for the call only: the library copies it.
private func withContent<Result>(id: String, title: String, body: String?, _ call: (OpaquePointer?) -> Result) -> Result {
    var content: OpaquePointer?
    let created = ntk_notification_content_create(id, title, &content)
    logger.debug("[withContent] created: \(created, privacy: .public)")
    defer { ntk_notification_content_free(content) }
    if let body {
        _ = ntk_notification_content_set_body(content, body)
    }
    return call(content)
}

/// In an hour: the request stays pending for the whole test.
private func withLaterTrigger<Result>(_ call: (UnsafePointer<ntk_notification_trigger>) -> Result) -> Result {
    withTrigger(seconds: 3600, call)
}

/// The completion of the cancellation adds the next request: the order of part 2, 6.3 (M6).
private func cancelThenScheduleRow(_ userData: UnsafeMutableRawPointer?, _ error: Int32, _ systemCode: UInt32) {
    let report = RowCompletion.from(userData).report
    let scheduled = withContent(id: "unused", title: "After", body: nil) { content in
        withLaterTrigger { ntk_notification_schedule_async("ntk.after", content, $0, doneRow, RowCompletion.userData(report), releaseRow) }
    }
    report("\(error) \(systemCode) schedule=\(scheduled)")
}

/// `kind=<n> id=<id> action=<id> category=<id> text=<text|NULL> userInfo=<json> launch=<0|1>`. The values are the test's
/// own: these rows run on the simulator only.
private func describeInteraction(_ event: OpaquePointer?) -> String {
    "kind=\(ntk_notification_interaction_kind(event)) id=\(optionalText(ntk_notification_interaction_notification_id(event, nil))) action=\(optionalText(ntk_notification_interaction_action_id(event, nil))) category=\(optionalText(ntk_notification_interaction_category_id(event, nil))) text=\(optionalText(ntk_notification_interaction_user_text(event, nil))) userInfo=\(optionalText(ntk_notification_interaction_user_info_json(event, nil))) launch=\(ntk_notification_interaction_is_launch(event))"
}

/// An event listener reports each event as a line of its row; `user_data` lives until `release`.
private func interactionRow(_ userData: UnsafeMutableRawPointer?, _ event: OpaquePointer?) {
    defer { ntk_notification_interaction_free(event) }
    RowCompletion.from(userData).report(describeInteraction(event))
}

private func settingsRequestRow(_ userData: UnsafeMutableRawPointer?, _ request: OpaquePointer?) {
    defer { ntk_notification_settings_request_free(request) }
    RowCompletion.from(userData).report("settings id=\(optionalText(ntk_notification_settings_request_notification_id(request, nil)))")
}

private func launchRow(_ userData: UnsafeMutableRawPointer?, _ error: Int32, _ systemCode: UInt32, _ response: OpaquePointer?) {
    defer { ntk_notification_interaction_free(response) }
    RowCompletion.from(userData).report("\(error) \(systemCode) response=\(response == nil ? "NULL" : describeInteraction(response))")
}

/// The listeners the rows registered, so that a row can remove them. Main thread only.
@MainActor
private enum Listeners {
    static var interaction: OpaquePointer?
    static var settings: OpaquePointer?
}

/// The event notification: its category has an action that opens the app, a reply and the custom dismiss action.
private let eventCategory = "ntk.events"

/// In `seconds`: long enough for a UI test to leave the app or terminate it.
private func withTrigger<Result>(seconds: Double, _ call: (UnsafePointer<ntk_notification_trigger>) -> Result) -> Result {
    var trigger = ntk_notification_trigger()
    trigger.struct_size = UInt32(MemoryLayout<ntk_notification_trigger>.size)
    trigger.kind = Int32(NTK_NOTIFICATION_TRIGGER_TIME_INTERVAL)
    trigger.interval_seconds = seconds
    return withUnsafePointer(to: &trigger, call)
}

/// The event notification's content, for the call only: the library copies it.
private func withEventContent<Result>(_ call: (OpaquePointer?) -> Result) -> Result {
    var content: OpaquePointer?
    let created = ntk_notification_content_create("ntk.event", "Event", &content)
    defer { ntk_notification_content_free(content) }
    logger.debug("[withEventContent] created: \(created, privacy: .public)")
    _ = ntk_notification_content_set_body(content, "Tap the event")
    _ = ntk_notification_content_set_category(content, eventCategory)
    _ = ntk_notification_content_set_user_info_json(content, "{\"k\":1}")
    return call(content)
}

/// The category of the event notification: `Open` brings the app forward, `Reply` takes text, and the custom
/// dismiss action is asked for.
private func withEventCategory<Result>(_ call: (UnsafePointer<ntk_notification_category>) -> Result) -> Result {
    eventCategory.withCString { identifier in
        "ntk.open".withCString { openIdentifier in
            "Open".withCString { openTitle in
                "ntk.reply".withCString { replyIdentifier in
                    "Reply".withCString { replyTitle in
                        "Send".withCString { button in
                            "IosLibraryCApiUITestApp reply".withCString { placeholder in
                                var open = ntk_notification_action()
                                open.struct_size = UInt32(MemoryLayout<ntk_notification_action>.size)
                                open.identifier = openIdentifier
                                open.title = openTitle
                                open.options = UInt32(NTK_NOTIFICATION_ACTION_FOREGROUND)
                                var reply = ntk_notification_text_input_action()
                                reply.struct_size = UInt32(MemoryLayout<ntk_notification_text_input_action>.size)
                                reply.identifier = replyIdentifier
                                reply.title = replyTitle
                                reply.button_title = button
                                reply.placeholder = placeholder
                                return withUnsafePointer(to: &open) { actions in
                                    withUnsafePointer(to: &reply) { replies in
                                        var category = ntk_notification_category()
                                        category.struct_size = UInt32(MemoryLayout<ntk_notification_category>.size)
                                        category.identifier = identifier
                                        category.options = UInt32(NTK_NOTIFICATION_CATEGORY_CUSTOM_DISMISS_ACTION)
                                        category.actions = actions
                                        category.action_count = 1
                                        category.text_input_actions = replies
                                        category.text_input_action_count = 1
                                        return withUnsafePointer(to: &category, call)
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }
    }
}

/// Notification.h. The values are the numbers of `ntk_notification_error`.
enum NotificationRows {
    static let section = CApiRowSection(id: "notification", rows: [
        CApiRow(id: "notification.install") { report in
            report(String(ntk_notification_install()))
        },
        CApiRow(id: "notification.installOffMain") { report in
            DispatchQueue.global().async {
                report(String(ntk_notification_install()))
            }
        },
        // Events (OP-42 to OP-45).
        // A new registration replaces the row's previous one, which is removed first.
        CApiRow(id: "notification.listen") { report in
            ntk_notification_listener_remove(Listeners.interaction)
            Listeners.interaction = nil
            var listener: OpaquePointer?
            reportRejection(ntk_notification_add_interaction_listener(interactionRow, RowCompletion.userData(report), releaseRow, &listener), report)
            Listeners.interaction = listener
        },
        CApiRow(id: "notification.unlisten") { report in
            ntk_notification_listener_remove(Listeners.interaction)
            Listeners.interaction = nil
            report("removed")
        },
        CApiRow(id: "notification.listenSettings") { report in
            ntk_notification_listener_remove(Listeners.settings)
            Listeners.settings = nil
            var listener: OpaquePointer?
            reportRejection(ntk_notification_add_settings_request_listener(settingsRequestRow, RowCompletion.userData(report), releaseRow, &listener), report)
            Listeners.settings = listener
        },
        CApiRow(id: "notification.unlistenSettings") { report in
            ntk_notification_listener_remove(Listeners.settings)
            Listeners.settings = nil
            report("removed")
        },
        CApiRow(id: "notification.launchResponse") { report in
            reportRejection(ntk_notification_get_launch_response_async(launchRow, RowCompletion.userData(report), releaseRow), report)
        },
        CApiRow(id: "notification.registerEventCategory") { report in
            reportRejection(withEventCategory { ntk_notification_register_category_async($0, doneRow, RowCompletion.userData(report), releaseRow) },
                            report)
        },
        CApiRow(id: "notification.showEventSoon") { report in
            reportRejection(withEventContent { content in
                withTrigger(seconds: 3) { ntk_notification_show_async(content, $0, doneRow, RowCompletion.userData(report), releaseRow) }
            }, report)
        },
        // Permission (OP-35 to OP-38).
        CApiRow(id: "notification.status") { report in
            reportRejection(ntk_notification_get_authorization_status_async(statusRow, RowCompletion.userData(report), releaseRow), report)
        },
        CApiRow(id: "notification.hasPermission") { report in
            reportRejection(ntk_notification_has_permission_async(permissionRow, RowCompletion.userData(report), releaseRow), report)
        },
        CApiRow(id: "notification.requestPermission") { report in
            reportRejection(ntk_notification_request_permission_async(0, permissionRow, RowCompletion.userData(report), releaseRow), report)
        },
        CApiRow(id: "notification.openSettings") { report in
            reportRejection(ntk_notification_open_settings_async(doneRow, RowCompletion.userData(report), releaseRow), report)
        },
        // Adding (OP-26 to OP-28).
        CApiRow(id: "notification.showNow") { report in
            reportRejection(withContent(id: "ntk.now", title: "Now", body: "Body") {
                ntk_notification_show_async($0, nil, doneRow, RowCompletion.userData(report), releaseRow)
            }, report)
        },
        CApiRow(id: "notification.showLater") { report in
            reportRejection(withContent(id: "ntk.later", title: "Later", body: nil) { content in
                withLaterTrigger { ntk_notification_show_async(content, $0, doneRow, RowCompletion.userData(report), releaseRow) }
            }, report)
        },
        // A file that is not there fails in the completion (M4).
        CApiRow(id: "notification.showMissingAttachment") { report in
            reportRejection(withContent(id: "ntk.attachment", title: "Attachment", body: nil) { content in
                _ = ntk_notification_content_add_attachment(content, "image", "file:///nonexistent/ntk-capi.png")
                return ntk_notification_show_async(content, nil, doneRow, RowCompletion.userData(report), releaseRow)
            }, report)
        },
        CApiRow(id: "notification.scheduleFirst") { report in
            reportRejection(withContent(id: "unused", title: "First", body: nil) { content in
                withLaterTrigger { ntk_notification_schedule_async("ntk.order", content, $0, doneRow, RowCompletion.userData(report), releaseRow) }
            }, report)
        },
        CApiRow(id: "notification.updateSecond") { report in
            reportRejection(withContent(id: "unused", title: "Second", body: nil) { content in
                withLaterTrigger { ntk_notification_update_async("ntk.order", content, $0, doneRow, RowCompletion.userData(report), releaseRow) }
            }, report)
        },
        // Lists (OP-33, OP-34).
        CApiRow(id: "notification.scheduled") { report in
            reportRejection(ntk_notification_get_scheduled_async(listRow, RowCompletion.userData(report), releaseRow), report)
        },
        CApiRow(id: "notification.delivered") { report in
            reportRejection(ntk_notification_get_delivered_async(listRow, RowCompletion.userData(report), releaseRow), report)
        },
        // Removing (OP-29 to OP-32).
        CApiRow(id: "notification.removeNow") { report in
            reportRejection(ntk_notification_remove_async("ntk.now", doneRow, RowCompletion.userData(report), releaseRow), report)
        },
        CApiRow(id: "notification.removeAll") { report in
            reportRejection(ntk_notification_remove_all_async(doneRow, RowCompletion.userData(report), releaseRow), report)
        },
        CApiRow(id: "notification.cancelLater") { report in
            reportRejection(ntk_notification_cancel_scheduled_async("ntk.later", doneRow, RowCompletion.userData(report), releaseRow), report)
        },
        CApiRow(id: "notification.cancelAllThenSchedule") { report in
            reportRejection(ntk_notification_cancel_all_scheduled_async(cancelThenScheduleRow, RowCompletion.userData(report), releaseRow), report)
        },
        // "" removes nothing and completes with NONE (part 2, 6.3).
        CApiRow(id: "notification.removeEmpty") { report in
            reportRejection(ntk_notification_remove_async("", doneRow, RowCompletion.userData(report), releaseRow), report)
        },
        CApiRow(id: "notification.cancelScheduledEmpty") { report in
            reportRejection(ntk_notification_cancel_scheduled_async("", doneRow, RowCompletion.userData(report), releaseRow), report)
        },
        CApiRow(id: "notification.removeCategoryEmpty") { report in
            reportRejection(ntk_notification_remove_category_async("", doneRow, RowCompletion.userData(report), releaseRow), report)
        },
        CApiRow(id: "notification.cancelAll") { report in
            reportRejection(ntk_notification_cancel_all_scheduled_async(doneRow, RowCompletion.userData(report), releaseRow), report)
        },
        // The badge and the category (OP-39 to OP-41).
        CApiRow(id: "notification.badge") { report in
            reportRejection(ntk_notification_set_badge_count_async(0, doneRow, RowCompletion.userData(report), releaseRow), report)
        },
        CApiRow(id: "notification.registerCategory") { report in
            let error = "ntk.category".withCString { identifier in
                "ntk.reply".withCString { action in
                    "Reply".withCString { title in
                        "Send".withCString { button in
                            "Message".withCString { placeholder in
                                var reply = ntk_notification_text_input_action()
                                reply.struct_size = UInt32(MemoryLayout<ntk_notification_text_input_action>.size)
                                reply.identifier = action
                                reply.title = title
                                reply.button_title = button
                                reply.placeholder = placeholder
                                return withUnsafePointer(to: &reply) { replies in
                                    var category = ntk_notification_category()
                                    category.struct_size = UInt32(MemoryLayout<ntk_notification_category>.size)
                                    category.identifier = identifier
                                    category.text_input_actions = replies
                                    category.text_input_action_count = 1
                                    return withUnsafePointer(to: &category) {
                                        ntk_notification_register_category_async($0, doneRow, RowCompletion.userData(report), releaseRow)
                                    }
                                }
                            }
                        }
                    }
                }
            }
            reportRejection(error, report)
        },
        CApiRow(id: "notification.removeCategory") { report in
            reportRejection(ntk_notification_remove_category_async("ntk.category", doneRow, RowCompletion.userData(report), releaseRow), report)
        },
    ])

    /// What a host calls while the launch is in progress (part 1, 1.4): the install, and with `listening` the two
    /// event listeners, so that a cold start from a notification reaches C (part 2, TB-8). They are never removed.
    @MainActor
    static func runAtLaunch(listening: Bool) {
        logger.debug("[runAtLaunch] listening: \(listening, privacy: .public)")
        RowReport(rowId: "launch.install", sceneState: SceneState.current())(String(ntk_notification_install()))
        guard listening else { return }
        let interactions = RowReport(rowId: "launch.interaction", sceneState: SceneState.current())
        var listener: OpaquePointer?
        reportRejection(ntk_notification_add_interaction_listener(interactionRow, RowCompletion.userData(interactions), releaseRow, &listener),
                        interactions)
        let settings = RowReport(rowId: "launch.settings", sceneState: SceneState.current())
        var settingsListener: OpaquePointer?
        reportRejection(ntk_notification_add_settings_request_listener(settingsRequestRow, RowCompletion.userData(settings), releaseRow,
                                                                        &settingsListener), settings)
    }
}
