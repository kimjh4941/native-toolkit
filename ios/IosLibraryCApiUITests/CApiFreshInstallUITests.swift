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
}
