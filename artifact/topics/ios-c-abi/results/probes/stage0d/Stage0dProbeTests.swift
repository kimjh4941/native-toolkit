import XCTest
import Foundation

// Temporary probe (stage 0d review R-1): the hierarchy around the reply text view and Send.
final class Stage0dProbeTests: SampleUITestCase {

    private var sample: SampleApp!

    override func setUpAfterGate() throws {
        sample = try launchSample()
        try sample.open(.notification)
        try NotificationCleanup.inApp(sample)
    }

    override func tearDownAfterGate() throws {
        try NotificationCleanup.inApp(sample)
        sample = nil
    }

    @MainActor
    func testP1_replyHierarchy() throws {
        let token = try systemUIToken()
        let springboard = Springboard(token)
        _ = try sample.press(.registerCategory)
        _ = try sample.press(.showTimeInterval, token)
        try springboard.goHome()
        XCTAssertTrue(try springboard.waitForBanner(title: "5s Notification", body: "Will be shown after 5 seconds", timeout: 20))
        try springboard.expandBanner(title: "5s Notification", body: "Will be shown after 5 seconds")
        print("NTKPROBE-BEFORE-BEGIN\n\(springboard.debugDescriptionOnSimulator())\nNTKPROBE-BEFORE-END")
        try springboard.tapAction("Reply")
        sample.observeQuietly(for: 2)
        print("NTKPROBE-AFTER-BEGIN\n\(springboard.debugDescriptionOnSimulator())\nNTKPROBE-AFTER-END")
        try springboard.sendReply("probe reply")
        try sample.activate()
    }
}
