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
    var trigger = ntk_notification_trigger()
    trigger.struct_size = UInt32(MemoryLayout<ntk_notification_trigger>.size)
    trigger.kind = Int32(NTK_NOTIFICATION_TRIGGER_TIME_INTERVAL)
    trigger.interval_seconds = 3600
    return withUnsafePointer(to: &trigger, call)
}

/// The completion of the cancellation adds the next request: the order of part 2, 6.3 (M6).
private func cancelThenScheduleRow(_ userData: UnsafeMutableRawPointer?, _ error: Int32, _ systemCode: UInt32) {
    let report = RowCompletion.from(userData).report
    let scheduled = withContent(id: "unused", title: "After", body: nil) { content in
        withLaterTrigger { ntk_notification_schedule_async("ntk.after", content, $0, doneRow, RowCompletion.userData(report), releaseRow) }
    }
    report("\(error) \(systemCode) schedule=\(scheduled)")
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

    /// What a host calls while the launch is in progress (part 1, 1.4).
    @MainActor
    static func runAtLaunch() {
        logger.debug("[runAtLaunch]")
        RowReport(rowId: "launch.install", sceneState: SceneState.current())(String(ntk_notification_install()))
    }
}
