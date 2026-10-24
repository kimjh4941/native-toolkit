//
//  IosNotificationManagerTests.swift
//  IosLibraryTests
//

import Foundation
import Synchronization
import Testing
import UserNotifications
@testable import IosLibrary

struct IosNotificationManagerTests {

    private func makeManager(repo: MockNotificationRepository) -> IosNotificationManager {
        let helper = NotificationPermissionHelper(repository: repo)
        return IosNotificationManager(repository: repo, permissionHelper: helper)
    }

    @Test func foregroundPresentationOptionsContainsListByDefault() {
        let repo = MockNotificationRepository()
        let manager = makeManager(repo: repo)
        #expect(manager.foregroundPresentationOptions.contains(.banner))
        #expect(manager.foregroundPresentationOptions.contains(.list))
    }

    @Test func openNotificationSettingsCallsRepository() {
        let repo = MockNotificationRepository()
        let manager = makeManager(repo: repo)

        manager.openNotificationSettings()

        #expect(repo.openSettingsCallCount == 1)
    }

    @Test func authorizationStatusReturnsUseCaseValue() async {
        let repo = MockNotificationRepository()
        repo.stubbedAuthorizationStatus = .provisional
        let manager = makeManager(repo: repo)

        let result = await withCheckedContinuation { continuation in
            manager.authorizationStatus { status in
                continuation.resume(returning: status)
            }
        }

        #expect(result == .provisional)
    }

    @Test func getScheduledReturnsUseCaseValue() async {
        let repo = MockNotificationRepository()
        repo.makeScheduled = {
            [
                ScheduledNotification(
                    identifier: "scheduled-1",
                    title: "title",
                    subtitle: nil,
                    body: "body",
                    categoryIdentifier: "sample",
                    userInfo: [:]
                )
            ]
        }
        let manager = makeManager(repo: repo)

        // `ScheduledNotification` is not `Sendable`, so only the checked fields leave the callback.
        let result = await withCheckedContinuation { continuation in
            manager.getScheduled { scheduled in
                continuation.resume(returning: scheduled.map { ($0.identifier, $0.body) })
            }
        }

        #expect(result.count == 1)
        #expect(result[0].0 == "scheduled-1")
        #expect(result[0].1 == "body")
    }

    @Test func delegateSettingsCanBeChangedFromAnotherThread() async {
        let repo = MockNotificationRepository()
        let manager = makeManager(repo: repo)

        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            DispatchQueue.global().async {
                manager.foregroundPresentationOptions = [.list]
                manager.onActionReceived = { _, _, _ in }
                continuation.resume()
            }
        }

        #expect(manager.foregroundPresentationOptions == [.list])
        #expect(manager.onActionReceived != nil)
        #expect(manager.onTextInputActionReceived == nil)
    }

    // MARK: - Delivery on the main thread, exactly once (README 0e, migration plan C)

    /// Records every call of a completion with the thread it ran on.
    private final class CallRecorder<Value: Sendable>: Sendable {
        private let calls = Mutex<[(value: Value, isMainThread: Bool)]>([])

        func record(_ value: Value) {
            let isMainThread = Thread.isMainThread
            calls.withLock { $0.append((value, isMainThread)) }
        }

        var all: [(value: Value, isMainThread: Bool)] {
            calls.withLock { $0 }
        }
    }

    /// Starts an operation on a background thread and returns every call of its completion.
    ///
    /// Waits up to 5 s for the first call, then 200 ms more, so that a second call is also seen.
    private func callsFromBackgroundThread<Value: Sendable>(
        _ start: @escaping @Sendable (_ completion: @escaping @Sendable (Value) -> Void) -> Void
    ) async throws -> [(value: Value, isMainThread: Bool)] {
        let recorder = CallRecorder<Value>()
        DispatchQueue.global().async {
            start { recorder.record($0) }
        }
        for _ in 0..<500 where recorder.all.isEmpty {
            try await Task.sleep(nanoseconds: 10_000_000)
        }
        try await Task.sleep(nanoseconds: 200_000_000)
        return recorder.all
    }

    private func expectSingleCallOnMain<Value: Sendable>(
        _ calls: [(value: Value, isMainThread: Bool)],
        sourceLocation: SourceLocation = #_sourceLocation
    ) {
        #expect(calls.count == 1, "completion must be invoked exactly once", sourceLocation: sourceLocation)
        #expect(calls.allSatisfy { $0.isMainThread }, "completion must be invoked on the main thread", sourceLocation: sourceLocation)
    }

    @Test(arguments: [false, true])
    func showDeliversOnTheMainThreadExactlyOnce(shouldFail: Bool) async throws {
        let repo = MockNotificationRepository()
        repo.shouldFail = shouldFail
        let manager = makeManager(repo: repo)

        let calls = try await callsFromBackgroundThread { (completion: @escaping @Sendable (Bool) -> Void) in
            manager.show(content: NotificationContent(id: "id", title: "title")) { isSuccess, _ in
                completion(isSuccess)
            }
        }

        expectSingleCallOnMain(calls)
        #expect(calls.first?.value == !shouldFail)
        #expect(repo.showCallCount == 1)
    }

    @Test(arguments: [false, true])
    func updateDeliversOnTheMainThreadExactlyOnce(shouldFail: Bool) async throws {
        let repo = MockNotificationRepository()
        repo.shouldFail = shouldFail
        let manager = makeManager(repo: repo)

        let calls = try await callsFromBackgroundThread { (completion: @escaping @Sendable (Bool) -> Void) in
            manager.update(identifier: "id", content: NotificationContent(id: "id", title: "title"), trigger: nil) { isSuccess, _ in
                completion(isSuccess)
            }
        }

        expectSingleCallOnMain(calls)
        #expect(calls.first?.value == !shouldFail)
        #expect(repo.updateCallCount == 1)
    }

    @Test(arguments: [false, true])
    func scheduleDeliversOnTheMainThreadExactlyOnce(shouldFail: Bool) async throws {
        let repo = MockNotificationRepository()
        repo.shouldFail = shouldFail
        let manager = makeManager(repo: repo)

        let calls = try await callsFromBackgroundThread { (completion: @escaping @Sendable (Bool) -> Void) in
            manager.schedule(
                content: NotificationContent(id: "id", title: "title"),
                trigger: .timeInterval(60, repeats: false),
                identifier: "id"
            ) { isSuccess, _ in
                completion(isSuccess)
            }
        }

        expectSingleCallOnMain(calls)
        #expect(calls.first?.value == !shouldFail)
        #expect(repo.scheduleCallCount == 1)
    }

    @Test(arguments: [false, true])
    func setBadgeCountDeliversOnTheMainThreadExactlyOnce(shouldFail: Bool) async throws {
        let repo = MockNotificationRepository()
        repo.shouldFail = shouldFail
        let manager = makeManager(repo: repo)

        let calls = try await callsFromBackgroundThread { (completion: @escaping @Sendable (Bool) -> Void) in
            manager.setBadgeCount(1) { isSuccess, _ in
                completion(isSuccess)
            }
        }

        expectSingleCallOnMain(calls)
        #expect(calls.first?.value == !shouldFail)
        #expect(repo.setBadgeCountCallCount == 1)
    }

    @Test(arguments: [false, true])
    func requestPermissionDeliversOnTheMainThreadExactlyOnce(shouldFail: Bool) async throws {
        let repo = MockNotificationRepository()
        repo.shouldFail = shouldFail
        let manager = makeManager(repo: repo)

        let calls = try await callsFromBackgroundThread { (completion: @escaping @Sendable (Bool) -> Void) in
            manager.requestPermission { granted, _ in
                completion(granted)
            }
        }

        expectSingleCallOnMain(calls)
        #expect(calls.first?.value == !shouldFail)
    }

    @Test func getScheduledDeliversOnTheMainThreadExactlyOnce() async throws {
        let repo = MockNotificationRepository()
        repo.makeScheduled = {
            [ScheduledNotification(identifier: "s1", title: "t", subtitle: nil, body: nil, categoryIdentifier: "", userInfo: [:])]
        }
        let manager = makeManager(repo: repo)

        let calls = try await callsFromBackgroundThread { (completion: @escaping @Sendable ([String]) -> Void) in
            manager.getScheduled { scheduled in
                completion(scheduled.map(\.identifier))
            }
        }

        expectSingleCallOnMain(calls)
        #expect(calls.first?.value == ["s1"])
    }

    @Test func getDeliveredDeliversOnTheMainThreadExactlyOnce() async throws {
        let repo = MockNotificationRepository()
        repo.makeDelivered = {
            [ActiveNotification(identifier: "d1", title: "t", subtitle: nil, body: nil, categoryIdentifier: "", date: Date(), userInfo: [:])]
        }
        let manager = makeManager(repo: repo)

        let calls = try await callsFromBackgroundThread { (completion: @escaping @Sendable ([String]) -> Void) in
            manager.getDelivered { delivered in
                completion(delivered.map(\.identifier))
            }
        }

        expectSingleCallOnMain(calls)
        #expect(calls.first?.value == ["d1"])
    }

    @Test func hasPermissionDeliversOnTheMainThreadExactlyOnce() async throws {
        let repo = MockNotificationRepository()
        repo.stubbedAuthorizationStatus = .denied
        let manager = makeManager(repo: repo)

        let calls = try await callsFromBackgroundThread { (completion: @escaping @Sendable (Bool) -> Void) in
            manager.hasPermission(completion: completion)
        }

        expectSingleCallOnMain(calls)
        #expect(calls.first?.value == false)
    }

    @Test func authorizationStatusDeliversOnTheMainThreadExactlyOnce() async throws {
        let repo = MockNotificationRepository()
        repo.stubbedAuthorizationStatus = .ephemeral
        let manager = makeManager(repo: repo)

        let calls = try await callsFromBackgroundThread { (completion: @escaping @Sendable (NotificationAuthorizationStatus) -> Void) in
            manager.authorizationStatus(completion: completion)
        }

        expectSingleCallOnMain(calls)
        #expect(calls.first?.value == .ephemeral)
    }

    @Test func showWithoutCompletionDoesNotTrap() async throws {
        let repo = MockNotificationRepository()
        let manager = makeManager(repo: repo)

        manager.show(content: NotificationContent(id: "id", title: "title"), completion: nil)
        // The show runs in a task; wait (up to 5 s) until it has reached the repository.
        for _ in 0..<500 where repo.showCallCount == 0 {
            try await Task.sleep(nanoseconds: 10_000_000)
        }

        #expect(repo.showCallCount == 1)
    }
}
