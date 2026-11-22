//
//  NotificationInstallTests.swift
//  IosLibraryCApiTests
//

import IosLibrary
import UserNotifications
import XCTest
@testable import IosLibraryCApi

private final class HostDelegate: NSObject, UNUserNotificationCenterDelegate {}

/// `ntk_notification_install` (part 1, 1.4). What the delegate forwards is tested in `IosLibraryTests`.
final class NotificationInstallTests: XCTestCase {
    private let none = ntk_notification_error(NTK_NOTIFICATION_ERROR_NONE)
    private let wrongThread = ntk_notification_error(NTK_NOTIFICATION_ERROR_WRONG_THREAD)
    private var delegateBefore: (any UNUserNotificationCenterDelegate)?

    override func setUp() {
        super.setUp()
        delegateBefore = UNUserNotificationCenter.current().delegate
    }

    override func tearDown() {
        UNUserNotificationCenter.current().delegate = delegateBefore
        super.tearDown()
    }

    func testTheNumbersAreThoseOfTheTable() {
        XCTAssertEqual(none, 0)
        XCTAssertEqual(wrongThread, 16)
    }

    func testOnTheMainThreadTheDelegateIsInstalledBeforeItReturns() {
        let center = UNUserNotificationCenter.current()
        let host = HostDelegate()
        center.delegate = host

        XCTAssertEqual(ntk_notification_install(), none)

        XCTAssertNotNil(center.delegate)
        XCTAssertFalse(center.delegate === host)
        // Once true it stays true, so this says something only when this test runs alone.
        XCTAssertTrue(IosNotificationManager.isDelegateInstalled)
    }

    func testSecondCallChangesNothing() {
        let center = UNUserNotificationCenter.current()
        XCTAssertEqual(ntk_notification_install(), none)
        let proxy = center.delegate
        XCTAssertNotNil(proxy)

        XCTAssertEqual(ntk_notification_install(), none)

        XCTAssertTrue(center.delegate === proxy)
    }

    func testCallAfterTheHostReplacedTheDelegateInstallsItAgain() {
        let center = UNUserNotificationCenter.current()
        XCTAssertEqual(ntk_notification_install(), none)
        let proxy = center.delegate
        XCTAssertNotNil(proxy)
        let host = HostDelegate()
        center.delegate = host

        XCTAssertEqual(ntk_notification_install(), none)

        XCTAssertTrue(center.delegate === proxy)
    }

    /// The main thread waits while the other thread calls, so a call that needed it would time out.
    func testOffTheMainThreadItReturnsWrongThreadAtOnceAndChangesNothing() {
        let center = UNUserNotificationCenter.current()
        let host = HostDelegate()
        center.delegate = host

        XCTAssertEqual(onAnotherThread { ntk_notification_install() }, wrongThread)

        XCTAssertTrue(center.delegate === host)
        // Nothing was queued for later either.
        RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.1))
        XCTAssertTrue(center.delegate === host)
    }

    /// The thread decides, not the queue (part 1, 1.3).
    func testInsideASerialQueueOnTheMainThreadItIsTheMainThread() {
        let center = UNUserNotificationCenter.current()
        let host = HostDelegate()
        center.delegate = host

        let (onMain, error) = DispatchQueue(label: "NotificationInstallTests").sync {
            (Thread.isMainThread, ntk_notification_install())
        }

        XCTAssertTrue(onMain, "this test needs sync to stay on the main thread")
        XCTAssertEqual(error, none)
        XCTAssertFalse(center.delegate === host)
    }

    func testEveryResultOfTheLibraryIsMapped() {
        XCTAssertEqual(NotificationReceiver.error(for: .installed), none)
        XCTAssertEqual(NotificationReceiver.error(for: .notMainThread), wrongThread)
    }
}
