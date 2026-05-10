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
        MacNotificationManager.shared.setup()
        MacNotificationManager.shared.setActionReceivedHandler { notificationId, actionId, userInfoJson in
            Log.d("MacLibraryExampleApp", "[ActionReceived] notificationId: \(notificationId), actionId: \(actionId), userInfoJson: \(userInfoJson)")
        }
        MacNotificationManager.shared.setTextInputActionReceivedHandler { notificationId, actionId, userText, userInfoJson in
            Log.d("MacLibraryExampleApp", "[TextActionReceived] notificationId: \(notificationId), actionId: \(actionId), userText: \(userText), userInfoJson: \(userInfoJson)")
        }
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
        }
    }
}
