//
//  NotificationRows.swift
//  IosLibraryCApiUITestApp
//

import Foundation
import IosLibraryCApi
import os

private let logger = Logger(subsystem: "com.jonghyunkim.nativetoolkit.IosLibraryCApiUITestApp", category: "NotificationRows")

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
    ])

    /// What a host calls while the launch is in progress (part 1, 1.4).
    @MainActor
    static func runAtLaunch() {
        logger.debug("[runAtLaunch]")
        RowReport(rowId: "launch.install", sceneState: SceneState.current())(String(ntk_notification_install()))
    }
}
