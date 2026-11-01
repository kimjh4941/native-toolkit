//
//  IosLibraryExampleApp.swift
//  IosLibraryExample
//
//  Created by Kim Jong Hyun on 2025/04/12.
//

import SwiftUI
import IosLibrary
import os
import UIKit

private let delegateLogger = Logger(subsystem: "com.jonghyunkim.ios.nativetoolkit.example", category: "SampleAppDelegate")

@main
struct IosLibraryExampleApp: App {
    @UIApplicationDelegateAdaptor(SampleAppDelegate.self) private var appDelegate

    var body: some Scene {
        WindowGroup {
            ContentView()
        }
    }
}

/// Sets the library's notification delegate up while the launch is in progress.
///
/// `App.init` works too (the library takes the app for not active yet while the application object
/// does not exist; `installDelegate()` DocC). The sample uses the application delegate, the place
/// a UIKit app uses as well.
final class SampleAppDelegate: NSObject, UIApplicationDelegate {
    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        delegateLogger.debug("[didFinishLaunchingWithOptions] launchOptions: \(launchOptions?.count ?? 0, privacy: .public)")
        // Installs the library's notification delegate and adds the listeners before the launch
        // returns, so that a response that launched the app reaches the sample (D-7). The test
        // shape of the launch (SA-18) chooses the path: `installDelegate()` and a listener of
        // `responses` by default, the deprecated receivers and `setup()`, or a delayed listener.
        NotificationEventRouting.shared.start()
        return true
    }
}
