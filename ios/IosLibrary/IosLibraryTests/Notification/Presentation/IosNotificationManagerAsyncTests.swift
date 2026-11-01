//
//  IosNotificationManagerAsyncTests.swift
//  IosLibraryTests
//
//  UT-29 (design 13.1, S-P13): the `async` forms of the notification operations return what their
//  use case returns and throw what it throws. UT-32 (S-P25, SR-2): their results are `Sendable`,
//  so a main-actor task can await them (this file builds in Swift 6 with complete checking).
//  The callback forms' `errorMessage` is the fixed text (S-P7).
//

import Foundation
import Synchronization
import Testing
@testable import IosLibrary

/// The messages of the callbacks; any thread.
private final class Messages: Sendable {
    private let values = Mutex<[String?]>([])
    func append(_ message: String?) { values.withLock { $0.append(message) } }
    var all: [String?] { values.withLock { $0 } }
}

struct IosNotificationManagerAsyncTests {

    private static let failure = NotificationError.addRequestFailed(FailureDetail(systemError: TestError.stub))

    private func makeManager(_ repository: MockNotificationRepository) -> IosNotificationManager {
        IosNotificationManager(repository: repository)
    }

    // MARK: - UT-29

    @Test func theThrowingFormsSucceedThroughTheirUseCases() async throws {
        let repository = MockNotificationRepository()
        let manager = makeManager(repository)

        try await manager.show(content: NotificationContent(id: "s", title: "t"), trigger: nil)
        try await manager.update(identifier: "u", content: NotificationContent(id: "u", title: "t"), trigger: nil)
        try await manager.schedule(content: NotificationContent(id: "c", title: "t"), trigger: .timeInterval(60, repeats: false), identifier: "c")
        try await manager.setBadgeCount(3)

        #expect(repository.showCallCount == 1)
        #expect(repository.updateCallCount == 1)
        #expect(repository.scheduleCallCount == 1)
        #expect(repository.setBadgeCountCallCount == 1)
    }

    @Test func theThrowingFormsThrowWhatTheirUseCasesThrow() async {
        let repository = MockNotificationRepository()
        repository.shouldFail = true
        let manager = makeManager(repository)

        await #expect(throws: Self.failure) {
            try await manager.show(content: NotificationContent(id: "s", title: "t"), trigger: nil)
        }
        await #expect(throws: Self.failure) {
            try await manager.update(identifier: "u", content: NotificationContent(id: "u", title: "t"), trigger: nil)
        }
        await #expect(throws: Self.failure) {
            try await manager.schedule(content: NotificationContent(id: "c", title: "t"), trigger: .timeInterval(60, repeats: false), identifier: "c")
        }
        await #expect(throws: NotificationError.setBadgeCountFailed(FailureDetail(systemError: TestError.stub))) {
            try await manager.setBadgeCount(3)
        }
    }

    /// The checks of the library's repository reach the `async` forms as their cases.
    @Test func theUserInfoChecksReachTheAsyncForms() async {
        let center = FakeRequestCenter()
        let manager = IosNotificationManager(repository: NotificationRepositoryImpl(requestCenter: center))

        await #expect(throws: NotificationError.invalidUserInfo) {
            try await manager.show(content: NotificationContent(id: "s", title: "t", userInfo: ["object": NSObject()]), trigger: nil)
        }
        await #expect(throws: NotificationError.reservedUserInfoKey) {
            try await manager.update(identifier: "u", content: NotificationContent(id: "u", title: "t", userInfo: [NotificationMarker.key: 1]), trigger: nil)
        }
        #expect(center.calls.isEmpty)
    }

    @Test func theQueriesReturnWhatTheirUseCasesReturn() async {
        let repository = MockNotificationRepository()
        repository.stubbedAuthorizationStatus = .provisional
        repository.makeScheduled = { [ScheduledNotification(identifier: "s1", title: "t", subtitle: nil, body: nil, categoryIdentifier: "", userInfo: ["k": 1])] }
        repository.makeDelivered = { [ActiveNotification(identifier: "d1", title: "t", subtitle: nil, body: nil, categoryIdentifier: "", date: Date(), userInfo: [:])] }
        let manager = makeManager(repository)

        #expect(await manager.getScheduled().map(\.identifier) == ["s1"])
        #expect(await manager.getDelivered().map(\.identifier) == ["d1"])
        #expect(await manager.hasPermission() == true)
        #expect(await manager.authorizationStatus() == .provisional)
    }

    /// The callback forms report the fixed English text of the case (not the device language's).
    @Test func theCallbackFormsReportTheFixedText() async throws {
        let repository = MockNotificationRepository()
        repository.shouldFail = true
        let manager = makeManager(repository)
        let messages = Messages()

        manager.show(content: NotificationContent(id: "s", title: "t")) { _, message in messages.append(message) }
        manager.setBadgeCount(1) { _, message in messages.append(message) }
        for _ in 0..<500 where messages.all.count < 2 {
            try await Task.sleep(nanoseconds: 10_000_000)
        }

        #expect(Set(messages.all.compactMap { $0 }) == ["Failed to add the notification request.", "Failed to set the badge count."])
    }

    // MARK: - UT-32

    /// A main-actor task awaits the `async` forms and keeps their results (Swift 6: the results
    /// cross from the nonisolated forms to the main actor, so they must be `Sendable`).
    @MainActor
    @Test func aMainActorTaskAwaitsTheAsyncForms() async throws {
        let repository = MockNotificationRepository()
        repository.makeScheduled = { [ScheduledNotification(identifier: "s1", title: "t", subtitle: nil, body: nil, categoryIdentifier: "", userInfo: ["k": "v"])] }
        repository.makeDelivered = { [ActiveNotification(identifier: "d1", title: "t", subtitle: nil, body: nil, categoryIdentifier: "", date: Date(), userInfo: ["n": 2])] }
        let manager = makeManager(repository)

        let results = await Task { @MainActor in
            let scheduled = await manager.getScheduled()
            let delivered = await manager.getDelivered()
            let granted = try await manager.requestPermission(options: [.alert], presenter: .firstActiveScene)
            let status = await manager.authorizationStatus()
            return (scheduled, delivered, granted, status)
        }.result

        let (scheduled, delivered, granted, status) = try results.get()
        #expect(scheduled.first?.userInfo["k"] as? String == "v")
        #expect(delivered.first?.userInfoValues["n"] == .integer(2))
        #expect(granted)
        #expect(status == .authorized)
    }
}
