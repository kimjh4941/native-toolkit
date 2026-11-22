//
//  OtherApps.swift
//  MacLibraryExampleUITests
//
//  Apps other than the sample that a test brings up (UI test design 6.1). Stage 0c (Dialog and
//  Share) needs only Mail: ShareViaMail opens it on the VM (S11), and it is stopped afterwards only
//  when it was not running before the test. Finder, System Settings and the Dock are added with the
//  Notification tests.
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
