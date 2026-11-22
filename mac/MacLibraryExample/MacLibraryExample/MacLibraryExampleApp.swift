//
//  MacLibraryExampleApp.swift
//  MacLibraryExample
//
//  Created by Kim Jong Hyun on 2025/04/20.
//

import SwiftUI
import MacLibrary

@main
struct MacLibraryExampleApp: App {

    private let TAG = "MacLibraryExampleApp"

    init() {
        Log.d(TAG, "init")
        // The only place the receivers are set (the Notification screen no longer replaces them),
        // and before `setup()` makes the library the notification delegate, so that a response
        // that launched the app reaches them. Each receiver writes to the app-wide store
        // synchronously; the screen reads it from there.
        MacNotificationManager.shared.setActionReceivedHandler { notificationId, actionId, userInfoJson in
            Log.d("MacLibraryExampleApp", "[ActionReceived] notificationId: \(notificationId), actionId: \(actionId), userInfoJson: \(userInfoJson)")
            NotificationEventLog.shared.record(
                kind: .action,
                notificationId: notificationId,
                actionId: actionId,
                userText: nil,
                userInfoJson: userInfoJson
            )
        }
        MacNotificationManager.shared.setTextInputActionReceivedHandler { notificationId, actionId, userText, userInfoJson in
            Log.d("MacLibraryExampleApp", "[TextActionReceived] notificationId: \(notificationId), actionId: \(actionId), userText: \(userText), userInfoJson: \(userInfoJson)")
            NotificationEventLog.shared.record(
                kind: .textInput,
                notificationId: notificationId,
                actionId: actionId,
                userText: userText,
                userInfoJson: userInfoJson
            )
        }
        MacNotificationManager.shared.setup()
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
        }
    }
}
