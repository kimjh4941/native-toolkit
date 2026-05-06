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
        IosNotificationManager.setup()

        IosNotificationManager.shared.onActionReceived = { notificationId, actionId, _ in
            Log.d("IosLibraryExampleApp", "[onActionReceived] notificationId: \(notificationId), actionId: \(actionId)")
        }

        IosNotificationManager.shared.onTextInputActionReceived = { notificationId, actionId, userText, _ in
            Log.d(
                "IosLibraryExampleApp",
                "[onTextInputActionReceived] notificationId: \(notificationId), actionId: \(actionId), userText: \(userText)"
            )
        }
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
        }
    }
}
