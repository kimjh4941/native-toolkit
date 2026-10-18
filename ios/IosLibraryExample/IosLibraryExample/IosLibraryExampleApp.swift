//
//  IosLibraryExampleApp.swift
//  IosLibraryExample
//
//  Created by Kim Jong Hyun on 2025/04/12.
//

import SwiftUI
import IosLibrary

@main
struct IosLibraryExampleApp: App {
    init() {
        // Set the receivers before `setup()` installs the notification delegate, so that no
        // response can arrive while they are still unset.
        IosNotificationManager.shared.onActionReceived = { notificationId, actionId, _ in
            Log.d("IosLibraryExampleApp", "[onActionReceived] notificationId: \(notificationId), actionId: \(actionId)")
            NotificationEventLog.shared.record(
                kind: .action,
                notificationId: notificationId,
                actionId: actionId,
                userText: nil
            )
        }

        IosNotificationManager.shared.onTextInputActionReceived = { notificationId, actionId, userText, _ in
            Log.d(
                "IosLibraryExampleApp",
                "[onTextInputActionReceived] notificationId: \(notificationId), actionId: \(actionId), userText: \(userText)"
            )
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
