//
//  OtherApps.swift
//  MacLibraryExampleUITests
//
//  Apps other than the sample that a test brings up (UI test design 6.1). Mail: ShareViaMail opens
//  it on the VM (S11), and it is stopped afterwards only when it was not running before the test.
//  Finder is brought to the front to put the sample behind (the means stage 0a checked. U-15);
//  System Settings is waited for in front and stopped only when it was not running before (N3).
//  Nothing in them is read or pressed. The Dock's badge is not readable (stage 0c 2.3: N19 is HC3).
//  Trusted Support file.
//

import AppKit
import XCTest
import Foundation

struct OtherApps {

    private let session: UITestSession

    init(_ token: RealServiceToken) {
        session = token.session
    }

    /// Whether Mail runs now.
    var isMailRunning: Bool {
        !NSRunningApplication.runningApplications(withBundleIdentifier: SystemLabels.mailBundleIdentifier).isEmpty
    }

    /// Stops Mail when it was not running before the test (`wasRunning`), and waits until it has gone.
    /// Through XCTest: the sandboxed runner's `NSRunningApplication.terminate()` did not stop Mail on
    /// the VM (stage 0c).
    func stopMail(wasRunning: Bool) throws {
        guard !wasRunning else { return }
        let mail = XCUIApplication(bundleIdentifier: SystemLabels.mailBundleIdentifier)
        if mail.state != .notRunning {
            mail.terminate()
        }
        guard mail.wait(for: .notRunning, timeout: 10), !isMailRunning else {
            throw SampleUITestError(.otherApp, "Mail did not stop")
        }
        try session.checkInterruption()
    }
}

/// Finder in front of the sample (`NotificationToken`: only the Notification tests need it).
struct FinderFront {

    private let session: UITestSession

    init(_ token: NotificationToken) {
        session = token.session
    }

    /// Activates Finder and waits until it is the frontmost app and the sample is behind.
    func bringToFront(behind sample: SampleApp) throws {
        let finder = XCUIApplication(bundleIdentifier: SystemLabels.finderBundleIdentifier)
        finder.activate()
        let deadline = Date().addingTimeInterval(SampleApp.launchTimeout)
        while true {
            let finders = OverlayCheck.pids(of: SystemLabels.finderBundleIdentifier)
            if let front = OverlayCheck.frontmostPID(), finders.contains(front), sample.state == .runningBackground {
                break
            }
            guard Date() < deadline else {
                let front = OverlayCheck.frontmostPID().flatMap { NSRunningApplication(processIdentifier: $0)?.bundleIdentifier } ?? "-"
                throw SampleUITestError(.finder, "Finder did not come to the front with the sample behind (front \(front), sample \(sample.state.rawValue))")
            }
            Thread.sleep(forTimeInterval: 0.1)
        }
        try session.checkInterruption()
    }
}

/// System Settings (N3. `SettingsToken`). Its content is not read or pressed.
struct SystemSettingsApp {

    private let session: UITestSession
    private let app = XCUIApplication(bundleIdentifier: SystemLabels.systemSettingsBundleIdentifier)

    init(_ token: SettingsToken) {
        session = token.session
    }

    var isRunning: Bool {
        !OverlayCheck.pids(of: SystemLabels.systemSettingsBundleIdentifier).isEmpty
    }

    /// Waits until System Settings is the foreground app (10 s).
    func waitForeground() throws {
        guard app.wait(for: .runningForeground, timeout: SampleApp.launchTimeout) else {
            throw SampleUITestError(.settings, "System Settings did not come to the front")
        }
        try session.checkInterruption()
    }

    /// Stops System Settings when it was not running before the test (`wasRunning`).
    func stop(wasRunning: Bool) throws {
        guard !wasRunning else { return }
        if app.state != .notRunning {
            app.terminate()
        }
        guard app.wait(for: .notRunning, timeout: SampleApp.launchTimeout) else {
            throw SampleUITestError(.settings, "System Settings did not stop")
        }
        try session.checkInterruption()
    }
}
