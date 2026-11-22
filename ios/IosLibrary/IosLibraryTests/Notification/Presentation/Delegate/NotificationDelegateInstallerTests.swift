//
//  NotificationDelegateInstallerTests.swift
//  IosLibraryTests
//

import Foundation
import OSLog
import Synchronization
import Testing
import UIKit
import UserNotifications
@testable import IosLibrary

/// UT-24: installing the delegate (design 8.3.1; part 1, 5.12.6), on a stand-in center.
@MainActor
struct NotificationDelegateInstallerTests {

    /// An installer with its own notification center for `didBecomeActive`.
    private func makeInstaller(_ sink: any NotificationDelegateEventSink = IgnoringSink()) -> (NotificationDelegateInstaller, NotificationCenter) {
        let notifications = NotificationCenter()
        let installer = NotificationDelegateInstaller(sink: sink, presentationOptions: { libraryTestOptions },
                                                      notificationCenter: notifications)
        return (installer, notifications)
    }

    /// The installer observes the center it first installed on; stop that before both go away.
    private func stopObserving(_ center: FakeNotificationCenter, _ installer: NotificationDelegateInstaller) {
        center.removeObserver(installer.proxy, forKeyPath: NotificationDelegateProxy.delegateKeyPath)
    }

    @Test func theFirstInstallSetsTheProxyAndTheFlag() {
        let (installer, _) = makeInstaller()
        let center = FakeNotificationCenter()
        let host = FullHostDelegate()
        center.delegate = host
        defer { stopObserving(center, installer) }
        #expect(!installer.isInstalled)

        #expect(installer.install(on: center, applicationIsActive: false) == .installed)

        #expect(center.delegate === installer.proxy)
        #expect(installer.proxy.previousDelegate === host)
        #expect(installer.isInstalled)
        // The center is observed before the proxy is set; that assignment is not a replacement.
        #expect(installer.proxy.replacementCount == 0)
    }

    /// The system may call the proxy on another thread as soon as it is the delegate. A call made
    /// inside the delegate's setter (the earliest possible) already sees the previous delegate and
    /// that the app was active at the first install, so it is forwarded and never becomes the
    /// launch response; the flag comes last.
    @Test func aCallDuringTheAssignmentSeesThePreparedState() async {
        let sink = RecordingSink()
        let (installer, _) = makeInstaller(sink)
        let center = FakeNotificationCenter()
        let host = FullHostDelegate()
        center.delegate = host
        defer { stopObserving(center, installer) }
        var seen: (forwardsToHost: Bool, settled: Bool, installed: Bool)?
        center.onDelegateSet = { [unowned center] in
            guard center.delegate === installer.proxy else { return }
            seen = (
                installer.proxy.previousDelegate(responding: NotificationDelegateProxy.didReceiveSelector) === host,
                installer.proxy.router.isLaunchResponseSettled,
                installer.isInstalled
            )
            installer.proxy.router.didReceive(TestNotificationKind.library.response(), previous: nil, completion: {})
        }

        _ = installer.install(on: center, applicationIsActive: true)
        center.onDelegateSet = nil
        await settle()

        #expect(seen?.forwardsToHost == true, "the previous delegate is set before the proxy is published")
        #expect(seen?.settled == true, "the first install's state is noted before the proxy is published")
        #expect(seen?.installed == false, "the flag is published after everything else")
        #expect(sink.responses.map { $0.isLaunchResponse } == [false])
        #expect(installer.proxy.replacementCount == 0)
    }

    /// The same when installing again after a replacement: a call during the assignment already
    /// goes to the object that replaced the proxy, not to the earlier previous delegate.
    @Test func aCallDuringAReinstallSeesTheNewPreviousDelegate() {
        let (installer, _) = makeInstaller()
        let center = FakeNotificationCenter()
        let host = FullHostDelegate()
        let other = FullHostDelegate()
        center.delegate = host
        defer { stopObserving(center, installer) }
        _ = installer.install(on: center, applicationIsActive: false)
        center.delegate = other
        var previousDuringTheAssignment: AnyObject?
        center.onDelegateSet = { [unowned center] in
            guard center.delegate === installer.proxy else { return }
            previousDuringTheAssignment = installer.proxy.previousDelegate
        }

        _ = installer.install(on: center, applicationIsActive: false)
        center.onDelegateSet = nil

        #expect(previousDuringTheAssignment === other)
        #expect(installer.proxy.replacementCount == 1, "only the other object's assignment is a replacement")
    }

    @Test func installingWithoutADelegateKeepsNoPrevious() {
        let (installer, _) = makeInstaller()
        let center = FakeNotificationCenter()
        defer { stopObserving(center, installer) }

        _ = installer.install(on: center, applicationIsActive: false)

        #expect(center.delegate === installer.proxy)
        #expect(installer.proxy.previousDelegate == nil)
    }

    /// Idempotent: a second install changes nothing, and the proxy never becomes its own previous
    /// delegate (part 1, 5.12.6).
    @Test func aSecondInstallKeepsThePreviousDelegate() {
        let (installer, _) = makeInstaller()
        let center = FakeNotificationCenter()
        let host = FullHostDelegate()
        center.delegate = host
        defer { stopObserving(center, installer) }

        _ = installer.install(on: center, applicationIsActive: false)
        #expect(installer.install(on: center, applicationIsActive: false) == .installed)

        #expect(center.delegate === installer.proxy)
        #expect(installer.proxy.previousDelegate === host)
        #expect(installer.proxy.previousDelegate !== installer.proxy)
    }

    /// H2-3 / 1a-10: another object replaces the delegate. The library logs it and does not
    /// install itself again; installing again puts the proxy in front of that object.
    @Test func aReplacementIsWatchedAndInstallingAgainRestoresTheProxy() async {
        let (installer, _) = makeInstaller()
        let center = FakeNotificationCenter()
        let host = FullHostDelegate()
        let other = FullHostDelegate()
        center.delegate = host
        defer { stopObserving(center, installer) }
        _ = installer.install(on: center, applicationIsActive: false)

        center.delegate = other
        await drainMainQueue(times: 2)

        #expect(installer.proxy.replacementCount == 1)
        #expect(center.delegate === other, "the library does not install itself again")

        #expect(installer.install(on: center, applicationIsActive: false) == .installed)
        #expect(center.delegate === installer.proxy)
        #expect(installer.proxy.previousDelegate === other)
        #expect(installer.proxy.replacementCount == 1, "the library's own install is not a replacement")
    }

    /// The observers are registered once: a second replacement after a reinstall is counted
    /// once, not twice.
    @Test func theCenterIsObservedOnlyOnce() {
        let (installer, _) = makeInstaller()
        let center = FakeNotificationCenter()
        defer { stopObserving(center, installer) }
        _ = installer.install(on: center, applicationIsActive: false)

        let first = FullHostDelegate()
        let second = BareHostDelegate()
        center.delegate = first
        _ = installer.install(on: center, applicationIsActive: false)
        center.delegate = second

        #expect(installer.proxy.replacementCount == 2)
    }

    @Test func clearingTheDelegateIsAReplacementToo() {
        let (installer, _) = makeInstaller()
        let center = FakeNotificationCenter()
        defer { stopObserving(center, installer) }
        _ = installer.install(on: center, applicationIsActive: false)

        center.delegate = nil

        #expect(installer.proxy.replacementCount == 1)
    }

    /// The previous delegate is weak: once its owner lets it go, it is as if there were none.
    @Test func thePreviousDelegateIsHeldWeakly() {
        let (installer, _) = makeInstaller()
        let center = FakeNotificationCenter()
        defer { stopObserving(center, installer) }
        // The pool lets go of the autoreleased references too (the Thread Sanitizer build keeps
        // more of them).
        autoreleasepool {
            let host = FullHostDelegate()
            center.delegate = host
            _ = installer.install(on: center, applicationIsActive: false)
            #expect(installer.proxy.previousDelegate === host)
        }

        #expect(installer.proxy.previousDelegate == nil)
        #expect(installer.proxy.previousDelegate(responding: NotificationDelegateProxy.didReceiveSelector) == nil)
    }

    @Test func aFirstInstallWhileActiveLeavesNoLaunchResponse() async {
        let sink = RecordingSink()
        let (installer, _) = makeInstaller(sink)
        let center = FakeNotificationCenter()
        defer { stopObserving(center, installer) }

        _ = installer.install(on: center, applicationIsActive: true)
        installer.proxy.router.didReceive(TestNotificationKind.library.response(), previous: nil, completion: {})
        await settle()

        #expect(sink.responses.map { $0.isLaunchResponse } == [false])
    }

    @Test func didBecomeActiveIsObservedFromTheFirstInstall() async {
        let sink = RecordingSink()
        let (installer, notifications) = makeInstaller(sink)
        let center = FakeNotificationCenter()
        defer { stopObserving(center, installer) }

        _ = installer.install(on: center, applicationIsActive: false)
        #expect(!installer.proxy.router.isLaunchResponseSettled)
        notifications.post(name: UIApplication.didBecomeActiveNotification, object: nil)
        #expect(installer.proxy.router.isLaunchResponseSettled)

        installer.proxy.router.didReceive(TestNotificationKind.library.response(), previous: nil, completion: {})
        await settle()
        #expect(sink.responses.map { $0.isLaunchResponse } == [false])
    }

    /// Before the first install, `didBecomeActive` is not observed (nothing to observe for).
    @Test func didBecomeActiveBeforeTheFirstInstallIsNotObserved() {
        let (installer, notifications) = makeInstaller()

        notifications.post(name: UIApplication.didBecomeActiveNotification, object: nil)

        #expect(!installer.proxy.router.isLaunchResponseSettled)
    }

    /// B-4 of the C5 review: before `UIApplicationMain` (a SwiftUI `App.init`, MS-12) there is no
    /// application object. It is read as optional and taken for "not active yet", so the first
    /// install still allows a launch response. In the test host the object exists.
    @Test func withoutTheApplicationObjectTheAppIsNotActiveYet() async throws {
        #expect(!NotificationDelegateInstaller.isActive(nil))
        let application = try #require(NotificationDelegateInstaller.sharedApplication())
        #expect(application === UIApplication.shared)
        #expect(NotificationDelegateInstaller.isActive(application) == (UIApplication.shared.applicationState == .active))

        let sink = RecordingSink()
        let (installer, _) = makeInstaller(sink)
        let center = FakeNotificationCenter()
        defer { stopObserving(center, installer) }
        _ = installer.install(on: center, applicationIsActive: NotificationDelegateInstaller.isActive(nil))
        installer.proxy.router.didReceive(TestNotificationKind.library.response(), previous: nil, completion: {})
        await settle()

        #expect(sink.responses.map { $0.isLaunchResponse } == [true])
    }

    /// 1a-11: installing while the app is active logs at `.info` that this may be after launch;
    /// installing while it is not logs nothing at that level. The calls between the two canary
    /// lines run on the main actor without a suspension, so no other test's install is between.
    @Test func installingWhileActiveLogsThatItMayBeAfterLaunch() throws {
        let start = Date().addingTimeInterval(-1)
        let token = UUID().uuidString
        let canary = Logger(subsystem: "com.jonghyunkim.nativetoolkit.IosLibrary", category: "NotificationDelegateInstallerTests")
        let (inactiveInstaller, _) = makeInstaller()
        let (activeInstaller, _) = makeInstaller()
        let inactiveCenter = FakeNotificationCenter()
        let activeCenter = FakeNotificationCenter()
        defer {
            stopObserving(inactiveCenter, inactiveInstaller)
            stopObserving(activeCenter, activeInstaller)
        }

        canary.info("canary \(token, privacy: .public) inactive")
        _ = inactiveInstaller.install(on: inactiveCenter, applicationIsActive: false)
        canary.info("canary \(token, privacy: .public) active")
        _ = activeInstaller.install(on: activeCenter, applicationIsActive: true)
        canary.info("canary \(token, privacy: .public) end")

        let store = try OSLogStore(scope: .currentProcessIdentifier)
        let entries = try store.getEntries(at: store.position(date: start)).compactMap { $0 as? OSLogEntryLog }
        let marks = ["inactive", "active", "end"].map { mark in
            entries.firstIndex { $0.composedMessage == "canary \(token) \(mark)" }
        }
        let inactive = try #require(marks[0]), active = try #require(marks[1]), end = try #require(marks[2])
        func afterLaunchLines(_ range: Range<Int>) -> [OSLogEntryLog] {
            entries[range].filter {
                $0.category == "NotificationDelegateInstaller" && $0.composedMessage.hasPrefix("[install] the app is already active")
            }
        }
        #expect(afterLaunchLines(inactive..<active).isEmpty)
        let lines = afterLaunchLines(active..<end)
        #expect(lines.count == 1)
        #expect(lines.first?.level == .info)
    }
}

/// UT-24 (thread), MS-06, and H2-3 with the real `UNUserNotificationCenter` of the test host.
///
/// These install the library's proxy into the test process for good (it is never removed), so
/// `IosNotificationManager.isDelegateInstalled` is `true` after them. A test that needs a process
/// where the delegate was never installed must use its own `NotificationDelegateInstaller`.
@Suite(.serialized)
@MainActor
struct NotificationDelegateRealCenterTests {

    private static let subsystem = "com.jonghyunkim.nativetoolkit.IosLibrary"

    /// Off the main thread nothing is touched; `.notMainThread` comes back at once.
    @Test func offTheMainThreadNothingChanges() async {
        let before = UNUserNotificationCenter.current().delegate.map(ObjectIdentifier.init)
        let wasInstalled = IosNotificationManager.isDelegateInstalled

        let results = await withCheckedContinuation { (continuation: CheckedContinuation<[NotificationDelegateInstallResult], Never>) in
            Thread {
                var results = [IosNotificationManager.installDelegate()]
                deprecatedNotification.setup()
                results.append(DispatchQueue.global().sync { IosNotificationManager.installDelegate() })
                continuation.resume(returning: results)
            }.start()
        }

        #expect(results == [.notMainThread, .notMainThread])
        #expect(UNUserNotificationCenter.current().delegate.map(ObjectIdentifier.init) == before)
        #expect(IosNotificationManager.isDelegateInstalled == wasInstalled)
    }

    /// MS-06: on the main thread inside `DispatchQueue(label:).sync` (main thread, not the main
    /// queue), `MainActor.assumeIsolated` does not stop, and the install goes through.
    @Test func insideASyncBlockOnTheMainThreadTheInstallGoesThrough() {
        let queue = DispatchQueue(label: "ms06")
        let (isMainThread, assumed) = queue.sync {
            (pthread_main_np() != 0, MainActor.assumeIsolated { true })
        }
        #expect(isMainThread)
        #expect(assumed)

        let result = queue.sync { IosNotificationManager.installDelegate() }

        #expect(result == .installed)
        #expect(UNUserNotificationCenter.current().delegate === IosNotificationManager.delegateInstaller.proxy)
        #expect(IosNotificationManager.isDelegateInstalled)
    }

    /// The library's manager reads the library's installer: once `installDelegate()` has
    /// installed the proxy, its hubs and `launchResponse()` no longer throw, and the launch
    /// response is the library router's (none in the test host, which is already active).
    @Test func theSharedManagerReadsTheLibraryInstaller() throws {
        #expect(IosNotificationManager.installDelegate() == .installed)
        #expect(IosNotificationManager.isDelegateInstalled)
        let manager = IosNotificationManager.shared

        let response = try manager.launchResponse()
        #expect(response == nil)
        #expect(IosNotificationManager.delegateInstaller.proxy.router.launchResponse == nil)
        try manager.responses.addListener { _, _ in }.remove()
        try manager.settingsRequests.addListener { _, _ in }.remove()
    }

    /// H2-3: another component replaces `UNUserNotificationCenter.delegate`; the library logs a
    /// warning and does not install itself again; installing again restores it in front of that
    /// component.
    @Test func aReplacedRealDelegateIsLoggedAndRestoredByInstallingAgain() async throws {
        let start = Date().addingTimeInterval(-1)
        let center = UNUserNotificationCenter.current()
        let proxy = IosNotificationManager.delegateInstaller.proxy
        #expect(IosNotificationManager.installDelegate() == .installed)
        #expect(center.delegate === proxy)
        let replacementsBefore = proxy.replacementCount

        let package = PackageLikeDelegate()
        center.delegate = package
        await drainMainQueue(times: 2)

        #expect(proxy.replacementCount == replacementsBefore + 1)
        #expect(center.delegate === package, "the library does not install itself again")
        let warnings = try OSLogStore(scope: .currentProcessIdentifier)
            .getEntries(at: try OSLogStore(scope: .currentProcessIdentifier).position(date: start))
            .compactMap { $0 as? OSLogEntryLog }
            .filter { $0.subsystem == Self.subsystem && $0.category == "NotificationDelegateProxy" && $0.level == .error }
            .map(\.composedMessage)
            .filter { $0.contains("warning: UNUserNotificationCenter.delegate was replaced by PackageLikeDelegate") }
        #expect(warnings.count == 1)

        #expect(IosNotificationManager.installDelegate() == .installed)
        #expect(center.delegate === proxy)
        #expect(proxy.previousDelegate === package)
        #expect(proxy.replacementCount == replacementsBefore + 1)
    }
}

/// A delegate like the Unity notification package's: it replaces the delegate and does not
/// forward (hand-off 2, U-4). Only the real-center test uses this type, so its warning can be
/// told from the stand-in centers' ones.
private final class PackageLikeDelegate: NSObject, UNUserNotificationCenterDelegate {
    func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse,
                                withCompletionHandler completionHandler: @escaping @Sendable () -> Void) {
        completionHandler()
    }
}
