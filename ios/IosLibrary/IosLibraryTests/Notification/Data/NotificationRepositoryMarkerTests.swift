//
//  NotificationRepositoryMarkerTests.swift
//  IosLibraryTests
//
//  UT-17 (design 13.1, 8.3.3): the repository marks what it adds, rejects the reserved key before
//  anything else (`update` leaves the pending request in place and calls nothing, SR-9), and
//  removes the marker from what it hands back. The requests go to a stand-in for the center: the
//  test host app has no notification permission, and the system keeps no request then.
//

import Foundation
import Testing
import UserNotifications
@testable import IosLibrary

/// Keeps the requests added, in order, and what was removed.
///
/// `@unchecked Sendable` (test code only): `UNNotificationRequest` is not `Sendable`; every access
/// to the stored requests is under the lock, and the tests read them after the calls returned.
private final class FakeRequestCenter: NotificationRequestCenter, @unchecked Sendable {
    private let lock = NSLock()
    private var requests: [UNNotificationRequest] = []
    private var recordedCalls: [String] = []

    var calls: [String] { lock.withLock { recordedCalls } }

    func request(_ identifier: String) -> UNNotificationRequest? {
        lock.withLock { requests.last { $0.identifier == identifier } }
    }

    func add(_ request: UNNotificationRequest) async throws {
        lock.withLock {
            recordedCalls.append("add \(request.identifier)")
            requests.removeAll { $0.identifier == request.identifier }
            requests.append(request)
        }
    }

    func removePendingNotificationRequests(withIdentifiers identifiers: [String]) {
        lock.withLock {
            recordedCalls.append("remove \(identifiers.joined(separator: ","))")
            requests.removeAll { identifiers.contains($0.identifier) }
        }
    }

    func removeAllPendingNotificationRequests() {
        lock.withLock {
            recordedCalls.append("removeAll")
            requests.removeAll()
        }
    }

    func pendingNotificationRequests() async -> [UNNotificationRequest] {
        lock.withLock { requests }
    }
}

struct NotificationRepositoryMarkerTests {

    private func content(_ identifier: String, userInfo: [String: Any]) -> NotificationContent {
        NotificationContent(id: identifier, title: "UT-17", body: "marker", userInfo: userInfo)
    }

    private func isReservedKeyError(_ error: any Error) -> Bool {
        if case NotificationError.reservedUserInfoKey = error { return true }
        return false
    }

    /// What the repository adds carries the marker; `getScheduled` hands it back without.
    @Test func whatTheRepositoryAddsIsMarkedAndHandedBackWithoutTheMarker() async throws {
        let center = FakeRequestCenter()
        let repository = NotificationRepositoryImpl(requestCenter: center)

        try await repository.schedule(content: content("s", userInfo: ["k": "v"]), trigger: .timeInterval(3600, repeats: false), identifier: "s")

        let request = try #require(center.request("s"))
        #expect(request.content.userInfo[NotificationMarker.key] as? Int == NotificationMarker.value)
        #expect(request.content.userInfo["k"] as? String == "v")
        let scheduled = try #require(await repository.getScheduled().first { $0.identifier == "s" })
        #expect(scheduled.userInfo[NotificationMarker.key] == nil)
        #expect(scheduled.userInfo["k"] as? String == "v")
        #expect(scheduled.userInfo.count == 1)
    }

    /// `show` and `update` mark too.
    @Test func showAndUpdateMarkWhatTheyAdd() async throws {
        let center = FakeRequestCenter()
        let repository = NotificationRepositoryImpl(requestCenter: center)

        try await repository.show(content: content("n", userInfo: [:]), trigger: nil)
        #expect(center.request("n")?.content.userInfo[NotificationMarker.key] as? Int == NotificationMarker.value)

        try await repository.update(identifier: "n", content: content("n", userInfo: ["after": 1]), trigger: .timeInterval(3600, repeats: false))
        let updated = try #require(center.request("n"))
        #expect(updated.content.userInfo[NotificationMarker.key] as? Int == NotificationMarker.value)
        #expect(updated.content.userInfo["after"] as? Int == 1)
        #expect(center.calls == ["add n", "remove n", "add n"])
    }

    /// `show` and `schedule` reject the reserved key without adding anything.
    @Test func showAndScheduleRejectTheReservedKey() async {
        let center = FakeRequestCenter()
        let repository = NotificationRepositoryImpl(requestCenter: center)

        await #expect(performing: {
            try await repository.show(content: content("n", userInfo: [NotificationMarker.key: 1]), trigger: nil)
        }, throws: isReservedKeyError)
        await #expect(performing: {
            try await repository.schedule(content: content("n", userInfo: [NotificationMarker.key: "x", "k": "v"]),
                                          trigger: .timeInterval(3600, repeats: false), identifier: "n")
        }, throws: isReservedKeyError)
        #expect(center.calls.isEmpty)
    }

    /// `update` rejects the reserved key before it removes the pending request (SR-9).
    @Test func updateWithTheReservedKeyLeavesThePendingRequest() async throws {
        let center = FakeRequestCenter()
        let repository = NotificationRepositoryImpl(requestCenter: center)
        try await repository.schedule(content: content("u", userInfo: ["before": 1]), trigger: .timeInterval(3600, repeats: false), identifier: "u")

        await #expect(performing: {
            try await repository.update(identifier: "u", content: content("u", userInfo: [NotificationMarker.key: 1]),
                                        trigger: .timeInterval(3600, repeats: false))
        }, throws: isReservedKeyError)

        let kept = try #require(center.request("u"), "update removed the pending request before it rejected the key")
        #expect(kept.content.userInfo["before"] as? Int == 1)
        #expect(center.calls == ["add u"])
    }

    /// `getDelivered` hands the delivered userInfo back without the marker, like `getScheduled`
    /// (tests cannot make a `UNNotification`, so the content's mapping is checked directly).
    @Test func aDeliveredNotificationIsHandedBackWithoutTheMarker() {
        let content = UNMutableNotificationContent()
        content.title = "UT-17"
        content.categoryIdentifier = "category"
        content.userInfo = [NotificationMarker.key: NotificationMarker.value, "k": "v"]
        let date = Date(timeIntervalSince1970: 1_000)

        let delivered = NotificationRepositoryImpl.activeNotification(identifier: "d", date: date, content: content)

        #expect(delivered.identifier == "d")
        #expect(delivered.date == date)
        #expect(delivered.categoryIdentifier == "category")
        #expect(delivered.userInfo[NotificationMarker.key] == nil)
        #expect(delivered.userInfo["k"] as? String == "v")
        #expect(delivered.userInfo.count == 1)
    }

    /// Removing every pending request goes through the same center as adding them.
    @Test func cancelAllAndCancelAllScheduledRemoveThroughTheCenter() async throws {
        let center = FakeRequestCenter()
        let repository = NotificationRepositoryImpl(requestCenter: center)
        try await repository.schedule(content: content("a", userInfo: [:]), trigger: .timeInterval(3600, repeats: false), identifier: "a")

        await repository.cancelAll()
        #expect(await center.pendingNotificationRequests().isEmpty)
        try await repository.schedule(content: content("b", userInfo: [:]), trigger: .timeInterval(3600, repeats: false), identifier: "b")
        await repository.cancelAllScheduled()

        #expect(await center.pendingNotificationRequests().isEmpty)
        #expect(center.calls == ["add a", "removeAll", "add b", "removeAll"])
    }
}
