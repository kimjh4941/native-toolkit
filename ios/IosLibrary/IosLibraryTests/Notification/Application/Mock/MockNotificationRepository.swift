//
//  MockNotificationRepository.swift
//  IosLibraryTests
//

import Foundation
import Synchronization
import UserNotifications
@testable import IosLibrary

// `NotificationRepository` is `Sendable` and is called from the manager's tasks, so the mutable
// test state is kept behind a `Mutex`. The stubs of the lists are factories that build a fresh
// value per call.
final class MockNotificationRepository: NotificationRepository {

    private struct State {
        var shouldFail = false
        var removalGate: (@Sendable () async -> Void)?
        var stubbedAuthorizationStatus: NotificationAuthorizationStatus = .authorized
        var makeScheduled: @Sendable () -> [ScheduledNotification] = { [] }
        var makeDelivered: @Sendable () -> [ActiveNotification] = { [] }

        var showCallCount = 0
        var updateCallCount = 0
        var scheduleCallCount = 0
        var cancelCallCount = 0
        var cancelAllCallCount = 0
        var removeDeliveredCallCount = 0
        var removeAllDeliveredCallCount = 0
        var cancelScheduledCallCount = 0
        var cancelAllScheduledCallCount = 0
        var setBadgeCountCallCount = 0
        var registerCategoryCallCount = 0
        var removeCategoryCallCount = 0
        var openSettingsCallCount = 0
        var requestPermissionCallCount = 0
        var authorizationStatusCallCount = 0
        /// What `requestPermission(options:)` returns when `shouldFail` is false (`false` is a denial).
        var stubbedGranted = true
        /// What `requestPermission(options:)` throws when `shouldFail` is true.
        var requestPermissionError: any Error & Sendable = NotificationError.permissionDenied
        var lastRequestedOptions: UInt?
        /// What `openNotificationSettings()` returns.
        var stubbedSettingsOpened = true
    }

    private let state = Mutex(State())

    private func value<Value: Sendable>(_ keyPath: KeyPath<State, Value>) -> Value {
        state.withLock { $0[keyPath: keyPath] }
    }

    private func setValue<Value: Sendable>(_ keyPath: WritableKeyPath<State, Value>, _ value: Value) {
        state.withLock { $0[keyPath: keyPath] = value }
    }

    /// When set, the four removals of delivered and scheduled notifications wait for it first.
    func setRemovalGate(_ gate: (@Sendable () async -> Void)?) { setValue(\.removalGate, gate) }

    /// Counts a call and returns whether the call should fail.
    private func record(_ keyPath: WritableKeyPath<State, Int>) -> Bool {
        state.withLock { state in
            state[keyPath: keyPath] += 1
            return state.shouldFail
        }
    }

    var shouldFail: Bool {
        get { value(\.shouldFail) }
        set { setValue(\.shouldFail, newValue) }
    }

    var stubbedAuthorizationStatus: NotificationAuthorizationStatus {
        get { value(\.stubbedAuthorizationStatus) }
        set { setValue(\.stubbedAuthorizationStatus, newValue) }
    }

    var makeScheduled: @Sendable () -> [ScheduledNotification] {
        get { value(\.makeScheduled) }
        set { setValue(\.makeScheduled, newValue) }
    }

    var makeDelivered: @Sendable () -> [ActiveNotification] {
        get { value(\.makeDelivered) }
        set { setValue(\.makeDelivered, newValue) }
    }

    var showCallCount: Int { value(\.showCallCount) }
    var updateCallCount: Int { value(\.updateCallCount) }
    var scheduleCallCount: Int { value(\.scheduleCallCount) }
    var cancelCallCount: Int { value(\.cancelCallCount) }
    var cancelAllCallCount: Int { value(\.cancelAllCallCount) }
    var removeDeliveredCallCount: Int { value(\.removeDeliveredCallCount) }
    var removeAllDeliveredCallCount: Int { value(\.removeAllDeliveredCallCount) }
    var cancelScheduledCallCount: Int { value(\.cancelScheduledCallCount) }
    var cancelAllScheduledCallCount: Int { value(\.cancelAllScheduledCallCount) }
    var setBadgeCountCallCount: Int { value(\.setBadgeCountCallCount) }
    var registerCategoryCallCount: Int { value(\.registerCategoryCallCount) }
    var removeCategoryCallCount: Int { value(\.removeCategoryCallCount) }
    var openSettingsCallCount: Int { value(\.openSettingsCallCount) }
    var requestPermissionCallCount: Int { value(\.requestPermissionCallCount) }
    var authorizationStatusCallCount: Int { value(\.authorizationStatusCallCount) }
    var lastRequestedOptions: UInt? { value(\.lastRequestedOptions) }

    var stubbedGranted: Bool {
        get { value(\.stubbedGranted) }
        set { setValue(\.stubbedGranted, newValue) }
    }

    var requestPermissionError: any Error & Sendable {
        get { state.withLock { $0.requestPermissionError } }
        set { state.withLock { $0.requestPermissionError = newValue } }
    }

    var stubbedSettingsOpened: Bool {
        get { value(\.stubbedSettingsOpened) }
        set { setValue(\.stubbedSettingsOpened, newValue) }
    }

    func show(content: NotificationContent, trigger: NotificationTrigger?) async throws {
        if record(\.showCallCount) { throw NotificationError.addRequestFailed(FailureDetail(systemError: TestError.stub)) }
    }

    func update(identifier: String, content: NotificationContent, trigger: NotificationTrigger?) async throws {
        if record(\.updateCallCount) { throw NotificationError.addRequestFailed(FailureDetail(systemError: TestError.stub)) }
    }

    func schedule(content: NotificationContent, trigger: NotificationTrigger, identifier: String) async throws {
        if record(\.scheduleCallCount) { throw NotificationError.addRequestFailed(FailureDetail(systemError: TestError.stub)) }
    }

    func requestPermission(options: UNAuthorizationOptions) async throws -> Bool {
        let (shouldFail, granted, error) = state.withLock { state in
            state.requestPermissionCallCount += 1
            state.lastRequestedOptions = options.rawValue
            return (state.shouldFail, state.stubbedGranted, state.requestPermissionError)
        }
        if shouldFail { throw error }
        return granted
    }

    func setBadgeCount(_ count: Int) async throws {
        if record(\.setBadgeCountCallCount) { throw NotificationError.setBadgeCountFailed(FailureDetail(systemError: TestError.stub)) }
    }

    func cancel(identifier: String) async {
        _ = record(\.cancelCallCount)
    }

    func cancelAll() async {
        _ = record(\.cancelAllCallCount)
    }

    func removeDelivered(identifier: String) async {
        await value(\.removalGate)?()
        _ = record(\.removeDeliveredCallCount)
    }

    func removeAllDelivered() async {
        await value(\.removalGate)?()
        _ = record(\.removeAllDeliveredCallCount)
    }

    func cancelScheduled(identifier: String) async {
        await value(\.removalGate)?()
        _ = record(\.cancelScheduledCallCount)
    }

    func cancelAllScheduled() async {
        await value(\.removalGate)?()
        _ = record(\.cancelAllScheduledCallCount)
    }

    func getScheduled() async -> [ScheduledNotification] {
        makeScheduled()
    }

    func getDelivered() async -> [ActiveNotification] {
        makeDelivered()
    }

    func authorizationStatus() async -> NotificationAuthorizationStatus {
        state.withLock { state in
            state.authorizationStatusCallCount += 1
            return state.stubbedAuthorizationStatus
        }
    }

    func openNotificationSettings() async -> Bool {
        _ = record(\.openSettingsCallCount)
        return stubbedSettingsOpened
    }

    func registerCategory(_ category: NotificationCategory) async {
        _ = record(\.registerCategoryCallCount)
    }

    func removeCategory(identifier: String) async {
        _ = record(\.removeCategoryCallCount)
    }
}

enum TestError: Error {
    case stub
}
