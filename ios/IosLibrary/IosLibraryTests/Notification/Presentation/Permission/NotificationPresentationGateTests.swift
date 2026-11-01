//
//  NotificationPresentationGateTests.swift
//  IosLibraryTests
//
//  UT-26 (the permission request) and UT-27 (the settings page) of design 13.1 (8.5.4, 8.5.5,
//  S-13, S-P19, S-P27): the table of `NotificationPresentationGate` for each presenter, and the
//  manager's forms around it. The UIKit work is `FakePresentationEnvironment`; the data is
//  `MockNotificationRepository`.
//

import Foundation
import Synchronization
import Testing
import UserNotifications
@testable import IosLibrary

@MainActor
struct NotificationPresentationGateTests {

    private let repository = MockNotificationRepository()
    private let environment = FakePresentationEnvironment()

    private func makeGate() -> NotificationPresentationGate {
        let environment = environment
        return NotificationPresentationGate(repository: repository, makeEnvironment: { environment })
    }

    private static let options: UNAuthorizationOptions = [.alert, .providesAppNotificationSettings]
    private static let detail = FailureDetail(domain: "UNErrorDomain", code: 1)

    // MARK: - UT-26: the permission request

    /// `.firstActiveScene`: requests at once, without the status or the foreground (as before).
    @Test func theFirstActiveSceneRequestsAtOnce() async {
        repository.stubbedAuthorizationStatus = .notDetermined
        let gate = makeGate()

        #expect(await gate.requestPermission(options: Self.options, presenter: .firstActiveScene) == .success(true))
        repository.stubbedGranted = false
        #expect(await gate.requestPermission(options: Self.options, presenter: .firstActiveScene) == .success(false))

        #expect(repository.requestPermissionCallCount == 2)
        #expect(repository.lastRequestedOptions == Self.options.rawValue)
        #expect(repository.authorizationStatusCallCount == 0)
        #expect(environment.foregroundSearches == 0)
    }

    /// The presenters that check the status first.
    enum CheckingPresenter: CaseIterable, Sendable {
        case foreground
        /// `.viewController(_:)` with a view controller outside a window.
        case viewControllerOutsideAWindow
        /// `.viewController(_:)` with a view controller inside a window.
        case viewControllerInsideAWindow

        @MainActor var selection: PresenterSelection {
            switch self {
            case .foreground:
                return .foreground
            case .viewControllerOutsideAWindow:
                let outside = FakeViewController("outside")
                outside.isInWindow = false
                return PresenterSelection(kind: .provided { outside })
            case .viewControllerInsideAWindow:
                let inside = FakeViewController("inside")
                return PresenterSelection(kind: .provided { inside })
            }
        }
    }

    /// `.foreground` and `.viewController(_:)` with a decided status: nothing is requested and
    /// the foreground is not looked at, also in the background or outside a window.
    @Test(arguments: [
        (NotificationAuthorizationStatus.authorized, true), (.provisional, true), (.ephemeral, true),
        (.denied, false), (.unknown, false),
    ], CheckingPresenter.allCases)
    func aDecidedStatusAnswersWithoutARequest(status: (NotificationAuthorizationStatus, Bool), presenter: CheckingPresenter) async {
        repository.stubbedAuthorizationStatus = status.0
        let gate = makeGate()

        #expect(await gate.requestPermission(options: Self.options, presenter: presenter.selection) == .success(status.1))
        #expect(repository.requestPermissionCallCount == 0)
        #expect(repository.authorizationStatusCallCount == 1)
        #expect(environment.foregroundSearches == 0)
    }

    /// `.foreground` while not determined: outside the foreground nothing is requested.
    @Test func notDeterminedOutsideTheForegroundIsNotForeground() async {
        repository.stubbedAuthorizationStatus = .notDetermined
        let gate = makeGate()

        #expect(await gate.requestPermission(options: Self.options, presenter: .foreground) == .failure(.notForeground))
        #expect(repository.requestPermissionCallCount == 0)
        #expect(environment.foregroundSearches == 1)
    }

    /// `.foreground` while not determined, in the foreground: requests; settling is not required.
    @Test func notDeterminedInTheForegroundRequests() async {
        repository.stubbedAuthorizationStatus = .notDetermined
        let busy = FakeViewController("busy")
        busy.isSettled = false
        environment.foreground = busy
        let gate = makeGate()

        #expect(await gate.requestPermission(options: Self.options, presenter: .foreground) == .success(true))
        #expect(repository.requestPermissionCallCount == 1)
        #expect(repository.lastRequestedOptions == Self.options.rawValue)
        #expect(environment.transitionWaits.isEmpty)
    }

    /// `.viewController(_:)` while not determined: the view controller must be in a window.
    @Test func theProvidedViewControllerMustBeInAWindow() async {
        repository.stubbedAuthorizationStatus = .notDetermined
        let outside = FakeViewController("outside")
        outside.isInWindow = false
        let inside = FakeViewController("inside")
        let gate = makeGate()

        #expect(await gate.requestPermission(options: Self.options, presenter: PresenterSelection(kind: .provided { outside })) == .failure(.notForeground))
        #expect(repository.requestPermissionCallCount == 0)
        #expect(await gate.requestPermission(options: Self.options, presenter: PresenterSelection(kind: .provided { inside })) == .success(true))
        #expect(repository.requestPermissionCallCount == 1)
    }

    /// A failed request is `authorizationFailed`: the library's case as it is, another error with
    /// its domain and code.
    @Test func aFailedRequestIsAuthorizationFailed() async {
        repository.stubbedAuthorizationStatus = .notDetermined
        environment.foreground = FakeViewController("top")
        repository.shouldFail = true
        let gate = makeGate()

        repository.requestPermissionError = NotificationError.authorizationFailed(Self.detail)
        #expect(await gate.requestPermission(options: Self.options, presenter: .foreground) == .failure(.authorizationFailed(Self.detail)))
        repository.requestPermissionError = NSError(domain: "Custom", code: 5)
        #expect(await gate.requestPermission(options: Self.options, presenter: .firstActiveScene)
                == .failure(.authorizationFailed(FailureDetail(domain: "Custom", code: 5))))
    }

    @Test func theStatusesThatGrant() {
        #expect([NotificationAuthorizationStatus.notDetermined, .denied, .authorized, .provisional, .ephemeral, .unknown]
            .filter(NotificationPresentationGate.grants) == [.authorized, .provisional, .ephemeral])
    }

    // MARK: - UT-27: the settings page

    @Test func theFirstActiveSceneOpensAtOnce() async {
        let gate = makeGate()
        #expect(await gate.openNotificationSettings(presenter: .firstActiveScene) == .success(()))
        #expect(repository.openSettingsCallCount == 1)
        #expect(environment.foregroundSearches == 0)
    }

    @Test func outsideTheForegroundTheSettingsPageIsNotOpened() async {
        let gate = makeGate()
        let outside = FakeViewController("outside")
        outside.isInWindow = false

        #expect(await gate.openNotificationSettings(presenter: .foreground) == .failure(.notForeground))
        #expect(await gate.openNotificationSettings(presenter: PresenterSelection(kind: .provided { outside })) == .failure(.notForeground))
        #expect(repository.openSettingsCallCount == 0)
    }

    /// `.viewController(_:)` with a view controller inside a window opens the page.
    @Test func theSettingsPageOpensForAProvidedViewControllerInAWindow() async {
        let gate = makeGate()
        let inside = FakeViewController("inside")

        #expect(await gate.openNotificationSettings(presenter: PresenterSelection(kind: .provided { inside })) == .success(()))
        #expect(repository.openSettingsCallCount == 1)
    }

    @Test func inTheForegroundTheSettingsPageOpensOrFails() async {
        environment.foreground = FakeViewController("top")
        let gate = makeGate()

        #expect(await gate.openNotificationSettings(presenter: .foreground) == .success(()))
        repository.stubbedSettingsOpened = false
        #expect(await gate.openNotificationSettings(presenter: .foreground) == .failure(.openSettingsFailed))
        #expect(await gate.openNotificationSettings(presenter: .firstActiveScene) == .failure(.openSettingsFailed))
        #expect(repository.openSettingsCallCount == 3)
    }
}

extension Result where Success == Void {
    /// For `#expect(... == .success(()))`.
    fileprivate static func == (lhs: Self, rhs: Self) -> Bool where Failure: Equatable {
        switch (lhs, rhs) {
        case (.success, .success): return true
        case let (.failure(left), .failure(right)): return left == right
        default: return false
        }
    }
}

/// The manager's forms around the gate: the completion on the main thread, once, never inside the
/// call; the existing forms keep their values and do not use the deprecated helper (S-P27).
struct IosNotificationManagerPermissionTests {

    /// Records the calls of a completion with the thread; any thread.
    private final class Calls<Value: Sendable>: Sendable {
        private let values = Mutex<[(Value, Bool)]>([])
        func record(_ value: Value) {
            let isMain = Thread.isMainThread
            values.withLock { $0.append((value, isMain)) }
        }
        var all: [(Value, Bool)] { values.withLock { $0 } }
    }

    private func makeManager(_ repository: MockNotificationRepository, foreground: Bool) async -> IosNotificationManager {
        let gate = await MainActor.run { () -> NotificationPresentationGate in
            let environment = FakePresentationEnvironment()
            environment.foreground = foreground ? FakeViewController("top") : nil
            return NotificationPresentationGate(repository: repository, makeEnvironment: { environment })
        }
        return IosNotificationManager(repository: repository, presentationGate: gate)
    }

    private func wait<Value>(for calls: Calls<Value>) async throws {
        for _ in 0..<500 where calls.all.isEmpty {
            try await Task.sleep(nanoseconds: 10_000_000)
        }
        try await Task.sleep(nanoseconds: 100_000_000)
    }

    @Test func theResultFormsCompleteOnMainOnceAndNeverInsideTheCall() async throws {
        let repository = MockNotificationRepository()
        repository.stubbedAuthorizationStatus = .notDetermined
        let manager = await makeManager(repository, foreground: false)
        let permission = Calls<Result<Bool, NotificationError>>()
        let settings = Calls<String>()

        let calledInside = await MainActor.run { () -> Bool in
            manager.requestPermission(presenter: .foreground) { permission.record($0) }
            manager.openNotificationSettings(presenter: .foreground) { result in
                if case .failure(let error) = result { settings.record(LogRedaction.caseName(error)) } else { settings.record("success") }
            }
            return !permission.all.isEmpty || !settings.all.isEmpty
        }
        try await wait(for: permission)
        try await wait(for: settings)

        #expect(!calledInside)
        #expect(permission.all.count == 1)
        #expect(permission.all.first?.0 == .failure(.notForeground))
        #expect(permission.all.first?.1 == true)
        #expect(settings.all.map(\.0) == ["notForeground"])
        #expect(settings.all.first?.1 == true)
        #expect(repository.requestPermissionCallCount == 0)
        #expect(repository.openSettingsCallCount == 0)
    }

    /// Calls made at the same time each get their own completion.
    @Test func overlappingRequestsEachComplete() async throws {
        let repository = MockNotificationRepository()
        let manager = await makeManager(repository, foreground: true)
        let calls = Calls<Result<Bool, NotificationError>>()

        DispatchQueue.concurrentPerform(iterations: 4) { _ in
            manager.requestPermission(presenter: .firstActiveScene) { calls.record($0) }
        }
        for _ in 0..<500 where calls.all.count < 4 {
            try await Task.sleep(nanoseconds: 10_000_000)
        }

        #expect(calls.all.count == 4)
        #expect(calls.all.allSatisfy { $0.0 == .success(true) && $0.1 })
        #expect(repository.requestPermissionCallCount == 4)
    }

    /// The existing form: a denial is `(false, <permissionDenied's text>)`, as before.
    @Test func theExistingRequestReportsADenialAsAFailure() async throws {
        let repository = MockNotificationRepository()
        repository.stubbedGranted = false
        let manager = await makeManager(repository, foreground: false)
        let calls = Calls<String?>()

        manager.requestPermission { granted, message in
            calls.record(granted ? "granted" : message)
        }
        try await wait(for: calls)

        #expect(calls.all.map(\.0) == [NotificationError.permissionDenied.errorDescription])
        #expect(calls.all.first?.1 == true)
    }

    /// The existing form goes through the use case, not the deprecated helper: an error that is not
    /// a `NotificationError` is reported as `authorizationFailed` (the helper would pass the error
    /// through), and the options are passed as given.
    @Test func theExistingRequestGoesThroughTheUseCase() async throws {
        let repository = MockNotificationRepository()
        repository.shouldFail = true
        repository.requestPermissionError = NSError(domain: "Custom", code: 5, userInfo: [NSLocalizedDescriptionKey: "custom text"])
        let manager = await makeManager(repository, foreground: false)
        let calls = Calls<String?>()

        manager.requestPermission(options: [.badge]) { _, message in calls.record(message) }
        try await wait(for: calls)

        #expect(calls.all.map(\.0) == [NotificationError.authorizationFailed(FailureDetail(domain: "Custom", code: 5)).errorDescription])
        #expect(repository.lastRequestedOptions == UNAuthorizationOptions.badge.rawValue)
    }

    /// The `async` forms: a denial is `false` (not an error); the errors are the gate's.
    @Test func theAsyncFormsReturnTheGatesResult() async throws {
        let repository = MockNotificationRepository()
        repository.stubbedAuthorizationStatus = .notDetermined
        let manager = await makeManager(repository, foreground: false)

        repository.stubbedGranted = false
        #expect(try await manager.requestPermission() == false)
        await #expect(throws: NotificationError.notForeground) {
            try await manager.requestPermission(presenter: .foreground)
        }
        await #expect(throws: NotificationError.notForeground) {
            try await manager.openNotificationSettings(presenter: .foreground)
        }
        repository.stubbedSettingsOpened = false
        await #expect(throws: NotificationError.openSettingsFailed) {
            try await manager.openNotificationSettings()
        }
    }
}
