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
    ///
    /// "Behind" is read from AppKit's activation, the same observation as the checks before each press
    /// (`SampleStateAtPress.sampleIsBehind`): the frontmost application is Finder, and the sample runs and
    /// is not active. `XCUIApplication.state` is not used here: on the VM it stayed `runningForeground`
    /// for the whole wait while Finder was already in front (stage 0d, 2026-11-24: N23 and N24, the same
    /// `finder` step as N21 since 0c). The main run loop is given a turn before every look, so AppKit can
    /// bring its values up to date; a look is still a moment's view, and the checks right before each
    /// press stay the boundary.
    @MainActor
    func bringToFront(behind sample: SampleApp) throws {
        let finder = XCUIApplication(bundleIdentifier: SystemLabels.finderBundleIdentifier)
        finder.activate()
        let deadline = Date().addingTimeInterval(SampleApp.launchTimeout)
        RunLoop.current.run(until: Date().addingTimeInterval(0.05))
        while true {
            let finders = OverlayCheck.pids(of: SystemLabels.finderBundleIdentifier)
            let samples = NSRunningApplication.runningApplications(withBundleIdentifier: SystemLabels.sampleBundleIdentifier)
            if let front = OverlayCheck.frontmostPID(), finders.contains(front), !samples.isEmpty,
               samples.allSatisfy({ !$0.isActive && $0.processIdentifier != front }) {
                break
            }
            guard Date() < deadline else {
                let front = OverlayCheck.frontmostPID().flatMap { NSRunningApplication(processIdentifier: $0)?.bundleIdentifier } ?? "-"
                let active = samples.map { $0.isActive ? "active" : "inactive" }.joined(separator: ",")
                throw SampleUITestError(.finder, "Finder did not come to the front with the sample behind (front \(front), sample \(active.isEmpty ? "not running" : active), XCUITest state \(sample.state.rawValue))")
            }
            RunLoop.current.run(until: Date().addingTimeInterval(0.1))
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
