//
//  CApiRoundTripUITests.swift
//  IosLibraryCApiUITests
//

import XCTest

/// The path of the C ABI's UI tests with the functions that exist so far: test -> app -> C function ->
/// result line -> test, in the foreground and with the call made in the background (TB-2b).
final class CApiRoundTripUITests: CApiUITestCase {

    func testTheLaunchInstallsTheDelegateThroughC() throws {
        let app = try launchApp(section: .notification)
        XCTAssertEqual(try app.waitForLine(ofRow: "launch.install"), "[launch.install@none] \(NotificationError.none)")
    }

    func testTheVersionComesFromC() throws {
        let app = try launchApp(section: .common)
        XCTAssertEqual(try app.run("common.version"), "[common.version@foregroundActive] 0x020000")
    }

    func testTheLastSystemCodeComesFromC() throws {
        let app = try launchApp(section: .common)
        XCTAssertEqual(try app.run("common.lastSystemCode"), "[common.lastSystemCode@foregroundActive] 0")
    }

    func testInstallingOnTheMainThreadReturnsNone() throws {
        let app = try launchApp(section: .notification)
        XCTAssertEqual(try app.run("notification.install"), "[notification.install@foregroundActive] \(NotificationError.none)")
    }

    func testInstallingOffTheMainThreadReturnsWrongThread() throws {
        let app = try launchApp(section: .notification)
        XCTAssertEqual(try app.run("notification.installOffMain"),
                       "[notification.installOffMain@foregroundActive] \(NotificationError.wrongThread)")
    }

    /// What keeps a tap short when the rows of all features are there (working notes 5.10).
    func testOnlyTheNamedSectionIsDrawn() throws {
        let app = try launchApp(section: .common)
        XCTAssertTrue(app.isDrawn("common.version"))
        XCTAssertFalse(app.isDrawn("notification.install"))
    }

    /// The way a foreground row of part 2, 12.1 reaches C: the state in the line says that the call
    /// was really made in the background.
    func testACallCanBeMadeInTheBackground() throws {
        let app = try launchApp(section: .common)
        XCTAssertEqual(try app.runInTheBackground("common.version"), "[common.version@background] 0x020000")
    }
}

/// The numbers of `ntk_notification_error` (`Notification.h`, `scripts/c_abi_error_numbers.json`).
private enum NotificationError {
    static let none = 0
    static let wrongThread = 16
}
