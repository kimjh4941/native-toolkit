//
//  UITestAppMain.swift
//  IosLibraryCApiUITestApp
//

import SwiftUI
import UIKit
import os

private let logger = Logger(subsystem: "com.jonghyunkim.nativetoolkit.IosLibraryCApiUITestApp", category: "UITestAppDelegate")

/// The app the C ABI's UI tests operate (C ABI design part 2, TB-2b, 12.1 and 12.2). Only the files of
/// `Rows/` call the library, and only through the C functions of the `IosLibraryCApi` module: the
/// sample shows the Swift API, this app the C one.
///
/// Its bundle identifier differs from `IosLibraryCApiTestHost`, whose tests expect a permission that
/// was never requested: the UI tests of this app press the permission alert (part 2, 12.1). It runs
/// on the simulator only (part 2, 12.2); `scripts/test_ios.sh --capi-ui` runs its tests.
@main
struct UITestApp: App {
    @UIApplicationDelegateAdaptor(UITestAppDelegate.self) private var appDelegate

    var body: some Scene {
        WindowGroup {
            RowListView()
        }
    }
}

/// Runs the calls that belong to the launch, before it returns, as a host of the C ABI does
/// (part 1, 1.4). A cold start from a notification needs them there.
final class UITestAppDelegate: NSObject, UIApplicationDelegate {
    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        logger.debug("[didFinishLaunchingWithOptions] launchOptions: \(launchOptions?.count ?? 0, privacy: .public)")
        RowReport(rowId: "launch.section", sceneState: SceneState.current())(CApiRowCatalog.drawnDescription)
        let shape = LaunchShape.current
        RowReport(rowId: "launch.shape", sceneState: SceneState.current())(LaunchShape.line)
        NotificationRows.runAtLaunch(listening: shape.shape.listensAtLaunch)
        RowReport(rowId: "launch.freshInstall", sceneState: SceneState.current())(String(FreshInstallMarker.consume()))
        return true
    }
}
