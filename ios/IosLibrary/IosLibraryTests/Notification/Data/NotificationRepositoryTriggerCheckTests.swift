//
//  NotificationRepositoryTriggerCheckTests.swift
//  IosLibraryTests
//
//  C ABI part 2, P2-26: a time interval that makes the system raise an exception is reported as
//  `invalidTrigger` before anything is added or removed. Every other trigger keeps working as
//  before, also one the system accepts and never fires.
//

import Foundation
import Testing
import UserNotifications
@testable import IosLibrary

struct NotificationRepositoryTriggerCheckTests {

    private func content(_ identifier: String) -> NotificationContent {
        NotificationContent(id: identifier, title: "P2-26", body: "check")
    }

    /// The values measured on the simulators (C ABI part 2, M5 and M8): these end the process.
    private static let invalid: [NotificationTrigger] = [
        .timeInterval(0, repeats: false),
        .timeInterval(-1, repeats: false),
        .timeInterval(.nan, repeats: false),
        .timeInterval(-.infinity, repeats: false),
        .timeInterval(0, repeats: true),
        .timeInterval(-1, repeats: true),
        .timeInterval(.nan, repeats: true),
        .timeInterval(30, repeats: true),
        .timeInterval(59.9, repeats: true),
    ]

    /// These do not, also when they never fire (the infinite interval stays pending).
    private static let valid: [NotificationTrigger] = [
        .timeInterval(0.001, repeats: false),
        .timeInterval(.leastNonzeroMagnitude, repeats: false),
        .timeInterval(30, repeats: false),
        .timeInterval(.infinity, repeats: false),
        .timeInterval(60, repeats: true),
        .timeInterval(.infinity, repeats: true),
        .calendar(DateComponents(), repeats: false),
        .calendar(DateComponents(hour: 9), repeats: true),
        .location(identifier: "", latitude: 0, longitude: 0, radius: 0, notifyOnEntry: true, notifyOnExit: false),
    ]

    @Test func isValidIsFalseOnlyForTheTimeIntervalsTheSystemRejects() {
        for trigger in Self.invalid {
            #expect(!trigger.isValid, "\(trigger)")
        }
        for trigger in Self.valid {
            #expect(trigger.isValid, "\(trigger)")
        }
    }

    @Test func showAndScheduleRejectAnInvalidTriggerAndCallNothing() async {
        for trigger in Self.invalid {
            let center = FakeRequestCenter()
            let repository = NotificationRepositoryImpl(requestCenter: center)
            await #expect(throws: NotificationError.invalidTrigger) {
                try await repository.show(content: content("n"), trigger: trigger)
            }
            await #expect(throws: NotificationError.invalidTrigger) {
                try await repository.schedule(content: content("n"), trigger: trigger, identifier: "n")
            }
            #expect(center.calls.isEmpty, "\(trigger)")
        }
    }

    /// `update` rejects it before it removes the pending request.
    @Test func updateWithAnInvalidTriggerLeavesThePendingRequest() async throws {
        let center = FakeRequestCenter()
        let repository = NotificationRepositoryImpl(requestCenter: center)
        try await repository.schedule(content: content("u"), trigger: .timeInterval(3600, repeats: false), identifier: "u")
        let before = center.calls

        await #expect(throws: NotificationError.invalidTrigger) {
            try await repository.update(identifier: "u", content: content("u"), trigger: .timeInterval(0, repeats: false))
        }

        #expect(center.calls == before)
        #expect(center.request("u") != nil, "update removed the pending request before it checked the trigger")
    }

    /// The trigger is checked before the attachments: a rejected request does not use up their
    /// files, so the missing file below is not what is reported.
    @Test func theTriggerIsCheckedBeforeTheAttachments() async throws {
        let missing = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("p2-26-\(UUID().uuidString).png")
        func withAttachment(_ identifier: String) -> NotificationContent {
            NotificationContent(id: identifier, title: "P2-26", attachments: [NotificationAttachment(identifier: "a", fileURL: missing)])
        }
        let center = FakeRequestCenter()
        let repository = NotificationRepositoryImpl(requestCenter: center)
        let invalid = NotificationTrigger.timeInterval(0, repeats: false)

        await #expect(throws: NotificationError.invalidTrigger) {
            try await repository.show(content: withAttachment("n"), trigger: invalid)
        }
        await #expect(throws: NotificationError.invalidTrigger) {
            try await repository.update(identifier: "n", content: withAttachment("n"), trigger: invalid)
        }
        await #expect(throws: NotificationError.invalidTrigger) {
            try await repository.schedule(content: withAttachment("n"), trigger: invalid, identifier: "n")
        }
        #expect(center.calls.isEmpty)
    }

    /// `update` without a trigger delivers now, as before.
    @Test func updateWithoutATriggerIsNotRejected() async throws {
        let center = FakeRequestCenter()
        let repository = NotificationRepositoryImpl(requestCenter: center)
        try await repository.update(identifier: "u", content: content("u"), trigger: nil)
        #expect(center.request("u") != nil)
    }

    /// The system still receives a trigger it accepts, also one that never fires.
    @Test func aValidTriggerReachesTheSystem() async throws {
        for trigger in Self.valid {
            let center = FakeRequestCenter()
            let repository = NotificationRepositoryImpl(requestCenter: center)
            try await repository.schedule(content: content("v"), trigger: trigger, identifier: "v")
            #expect(center.request("v") != nil, "\(trigger)")
        }
    }

    /// No trigger means now: nothing to reject.
    @Test func noTriggerIsNotRejected() async throws {
        let center = FakeRequestCenter()
        let repository = NotificationRepositoryImpl(requestCenter: center)
        try await repository.show(content: content("s"), trigger: nil)
        #expect(center.request("s") != nil)
    }
}
