//
//  IosLibraryExampleApp.swift
//  IosLibraryExample
//
//  Created by Kim Jong Hyun on 2025/04/12.
//

import SwiftUI
import IosLibrary
import os

private let logger = Logger(subsystem: "com.jonghyunkim.ios.nativetoolkit.example", category: "IosLibraryExampleApp")

@main
struct IosLibraryExampleApp: App {
    init() {
        // Set the receivers before `setup()` installs the notification delegate, so that no
        // response can arrive while they are still unset.
        IosNotificationManager.shared.onActionReceived = { notificationId, actionId, _ in
            logger.debug("[onActionReceived] notificationId: \(notificationId, privacy: .public), actionId: \(actionId, privacy: .public)")
            NotificationEventLog.shared.record(
                kind: .action,
                notificationId: notificationId,
                actionId: actionId,
                userText: nil
            )
        }

        IosNotificationManager.shared.onTextInputActionReceived = { notificationId, actionId, userText, _ in
            logger.debug("[onTextInputActionReceived] notificationId: \(notificationId, privacy: .public), actionId: \(actionId, privacy: .public), userTextLength: \(userText.utf8.count, privacy: .public)")
            NotificationEventLog.shared.record(
                kind: .textInput,
                notificationId: notificationId,
                actionId: actionId,
                userText: userText
            )
        }

        IosNotificationManager.setup()
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
        }
    }
}
