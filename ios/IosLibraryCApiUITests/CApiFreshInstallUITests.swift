//
//  CApiFreshInstallUITests.swift
//  IosLibraryCApiUITests
//

import XCTest

/// The tests that start from a new install, where the notification permission is undetermined: the deletion
/// itself, and the notification permission asked from C (TB-7). The runner deletes the app before each test
/// of this class and runs them one per xcodebuild (`CAPI_UI_CLASSES` in `scripts/ios_ui_runner.py`). The
/// deletion is what returns the permission (stage 2 working notes, chapter 5).
final class CApiFreshInstallUITests: CApiUITestCase {

    /// The second launch says that the first one's `true` means something: the marker survives a
    /// launch, so only the deletion can have removed it.
    func testTheRunnerDeletedTheApp() throws {
        let app = try launchApp(section: .common)
        XCTAssertEqual(try app.waitForLine(ofRow: "launch.freshInstall"), "[launch.freshInstall@none] true", "the app was not deleted before this test")
        try app.terminate()
        try app.launch()
        XCTAssertEqual(try app.waitForLine(ofRow: "launch.freshInstall"), "[launch.freshInstall@none] false")
    }

    /// 12.2, "Dialog と権限" (the permission dialog asked from C) and 12.1, "前面" and "権限の事前の確かめ": the
    /// pre-check stops the three adds while undetermined, the background gets NOT_FOREGROUND while undetermined
    /// and the value once decided.
    func testAskingForTheNotificationPermissionFromC() throws {
        let app = try launchApp(section: .notification)
        XCTAssertEqual(try app.run("notification.status"), notificationLine("status", "0 0 status=\(NotificationStatus.notDetermined)"),
                       "the permission is not undetermined: the runner did not delete the app")
        XCTAssertEqual(try app.run("notification.hasPermission"), notificationLine("hasPermission", "0 0 granted=0"))
        let denied = "\(NotificationError.permissionDenied) 0"
        XCTAssertEqual(try app.run("notification.showNow"), notificationLine("showNow", denied))
        XCTAssertEqual(try app.run("notification.scheduleFirst"), notificationLine("scheduleFirst", denied))
        XCTAssertEqual(try app.run("notification.updateSecond"), notificationLine("updateSecond", denied))
        // Nothing was added: without the pre-check the immediate one would be in the delivered list (M2). The
        // list is read after a wait, so that one that comes late is not missed.
        Thread.sleep(forTimeInterval: 2)
        XCTAssertEqual(try app.run("notification.delivered"), notificationLine("delivered", "0 0 count=0 "))
        XCTAssertEqual(try app.run("notification.scheduled"), notificationLine("scheduled", "0 0 count=0 "))
        XCTAssertEqual(try app.runInTheBackground("notification.requestPermission"),
                       notificationLine("requestPermission", "\(NotificationError.notForeground) 0 granted=0", state: "background"))
        XCTAssertEqual(try app.runInTheBackground("notification.openSettings"),
                       notificationLine("openSettings", "\(NotificationError.notForeground) 0", state: "background"))
        XCTAssertEqual(try app.run("notification.status"), notificationLine("status", "0 0 status=\(NotificationStatus.notDetermined)"))

        try app.start("notification.requestPermission")
        try app.allowNotifications()
        XCTAssertEqual(try app.waitForLine(ofRow: "notification.requestPermission", occurrence: 1),
                       notificationLine("requestPermission", "0 0 granted=1"))
        // Decided: the current answer, without asking, also from the background.
        XCTAssertEqual(try app.runInTheBackground("notification.requestPermission"),
                       notificationLine("requestPermission", "0 0 granted=1", state: "background"))
        XCTAssertEqual(try app.run("notification.status"), notificationLine("status", "0 0 status=\(NotificationStatus.authorized)"))
        XCTAssertEqual(try app.run("notification.hasPermission"), notificationLine("hasPermission", "0 0 granted=1"))
    }

    /// 12.2 "通知のイベント", `openSettingsFor` (TB-10): the first request of the new install asks for the app's own
    /// notification settings, and the link Settings then shows reaches the C listener registered at launch as a
    /// settings request without a notification. Settings is operated on iOS 26.2 only (its labels are measured there,
    /// in English; stage 2 working notes, 13): on another OS the test ends after the request, which it still checks.
    func testTheSettingsLinkReachesCAsASettingsRequest() throws {
        let app = try launchApp(section: .notification, listensAtLaunch: true)
        XCTAssertEqual(try app.waitForLine(ofRow: "launch.shape"), "[launch.shape@none] source=environment section=notification listen=1 saved=1")
        XCTAssertEqual(try app.run("notification.status"), notificationLine("status", "0 0 status=\(NotificationStatus.notDetermined)"),
                       "the permission is not undetermined: the runner did not delete the app")
        try app.start("notification.requestPermissionWithAppSettings")
        try app.allowNotifications()
        XCTAssertEqual(try app.waitForLine(ofRow: "notification.requestPermissionWithAppSettings"),
                       notificationLine("requestPermissionWithAppSettings", "0 0 granted=1"))
        let version = ProcessInfo.processInfo.operatingSystemVersion
        guard version.majorVersion == 26, version.minorVersion == 2 else {
            print("[CApiFreshInstallUITests] Settings is not operated on iOS \(version.majorVersion).\(version.minorVersion): the test ends after the request")
            return
        }
        try app.openTheAppsNotificationSettingsLink()
        XCTAssertEqual(try app.waitForLine(ofRow: "launch.settings", timeout: 15), "[launch.settings@none] settings id=NULL")
        Thread.sleep(forTimeInterval: 1)
        XCTAssertFalse(app.isDrawnLine(ofRow: "launch.settings", occurrence: 1), "one request for the link")
        XCTAssertFalse(app.isDrawnLine(ofRow: "launch.interaction", occurrence: 0), "an interaction for the link")
    }
}
