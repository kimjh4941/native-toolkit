//
//  IosNotificationManagerEventTests.swift
//  IosLibraryTests
//
//  The manager's event entries (design 8.4, S-P8, S-P12): `responses`, `settingsRequests`,
//  `launchResponse()`, and the deprecated receivers beside the hub (UT-25). Every manager has its
//  own "installed" source: the process flag stays set once `NotificationDelegateRealCenterTests`
//  has installed the real proxy (that suite also checks the shared manager, which reads it).
//

import Foundation
import Synchronization
import Testing
import UserNotifications
@testable import IosLibrary

@MainActor
struct IosNotificationManagerEventTests {

    private func makeManager(
        installed: Bool = true,
        launchResponse: NotificationDelegateResponse? = nil
    ) -> IosNotificationManager {
        let repository = MockNotificationRepository()
        return IosNotificationManager(
            repository: repository,
            permissionHelper: NotificationPermissionHelper(repository: repository),
            delegateStatus: NotificationDelegateStatus(isInstalled: { installed }, launchResponse: { launchResponse })
        )
    }

    // MARK: responses

    /// The event carries the response's values, without the marker, and the launch flag.
    @Test func aResponseBecomesAnEventWithoutTheMarker() throws {
        let manager = makeManager()
        var events: [NotificationResponseEvent] = []
        try manager.responses.addListener { event, _ in events.append(event) }

        manager.deliver(response: TestNotificationKind.library.response(identifier: "n", action: "reply", userText: "hi"), isLaunchResponse: true)

        #expect(events == [NotificationResponseEvent(
            notificationIdentifier: "n",
            actionIdentifier: "reply",
            categoryIdentifier: "category",
            userText: "hi",
            userInfo: ["k": .string("v")],
            isLaunchResponse: true
        )])
    }

    /// The description shows the reply's length and the key count, never the values.
    @Test func theEventDescriptionHidesTheReplyAndTheValues() {
        let event = NotificationResponseEvent(
            notificationIdentifier: "n", actionIdentifier: "reply", categoryIdentifier: "c",
            userText: "secret reply", userInfo: ["k": .string("secret value")], isLaunchResponse: false
        )
        let shown = [event.description, String(describing: event), String(reflecting: event), "\(event)"]
        for text in shown {
            #expect(!text.contains("secret"), "\(text)")
            #expect(text.contains("length 12"), "\(text)")
            #expect(text.contains("1 keys"), "\(text)")
        }
    }

    @Test func withoutTheDelegateTheHubsAndTheLaunchResponseThrow() {
        let manager = makeManager(installed: false)
        let errors = [
            #expect(throws: NotificationError.self) { try manager.responses.addListener { _, _ in } },
            #expect(throws: NotificationError.self) { try manager.settingsRequests.addListener { _, _ in } },
            #expect(throws: NotificationError.self) { _ = try manager.launchResponse() },
        ]
        for (index, error) in errors.enumerated() {
            guard case .delegateNotInstalled? = error else {
                Issue.record("entry \(index): expected delegateNotInstalled, got \(String(describing: error))")
                continue
            }
        }
    }

    // MARK: Deprecated receivers (UT-25)

    /// The deprecated receivers are called for every response but are not listeners: with only
    /// them set, the hub keeps the response for the next listener (design 13.1 UT-25 "今の受け手を
    /// 並びに入れる").
    @Test func theDeprecatedReceiversAreNotListeners() throws {
        let manager = makeManager()
        let legacy = CompletionRecorder<String>()
        deprecatedNotification.setReceivers(of: manager, action: { id, _, _ in legacy.handler(id) }, textInput: nil)

        manager.deliver(response: TestNotificationKind.library.response(identifier: "first"), isLaunchResponse: false)

        #expect(legacy.all.map(\.value) == ["first"])
        #expect(manager.responses.keptCount == 1)
        var events: [String] = []
        try manager.responses.addListener { event, _ in events.append(event.notificationIdentifier) }
        #expect(events == ["first"])
    }

    /// With a listener, the listener is called first, then the deprecated receiver, once each per
    /// response (design 8.3.2).
    @Test func theListenerComesBeforeTheDeprecatedReceiver() throws {
        let manager = makeManager()
        let order = Mutex<[String]>([])
        deprecatedNotification.setReceivers(
            of: manager,
            action: { id, _, _ in order.withLock { $0.append("legacy \(id)") } },
            textInput: { id, _, _, _ in order.withLock { $0.append("legacy text \(id)") } }
        )
        try manager.responses.addListener { event, _ in order.withLock { $0.append("listener \(event.notificationIdentifier)") } }

        manager.deliver(response: TestNotificationKind.library.response(identifier: "a"), isLaunchResponse: false)
        manager.deliver(response: TestNotificationKind.library.response(identifier: "b", action: "reply", userText: ""), isLaunchResponse: false)

        #expect(order.withLock { $0 } == ["listener a", "legacy a", "listener b", "legacy text b"])
        #expect(manager.responses.keptCount == 0)
    }

    // MARK: Through the router

    /// From the router's main-queue block: the listener receives the event before the system
    /// completion is called (1a-12), on the main thread.
    @Test func theListenerReceivesTheEventBeforeTheSystemCompletion() async throws {
        let manager = makeManager()
        let order = Mutex<[String]>([])
        try manager.responses.addListener { event, _ in
            order.withLock { $0.append("listener \(event.notificationIdentifier) main=\(Thread.isMainThread)") }
        }
        let router = NotificationDelegateRouter(sink: manager, isApplicationInForeground: { true })

        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            DispatchQueue.global().async {
                router.didReceive(TestNotificationKind.library.response(identifier: "n"), previous: nil) {
                    order.withLock { $0.append("completion") }
                    continuation.resume()
                }
            }
        }

        #expect(order.withLock { $0 } == ["listener n main=true", "completion"])
    }

    /// Kept while there is no listener, and handed over with its launch flag (N36's library part).
    @Test func aLaunchResponseKeptUntilTheListenerIsAddedKeepsItsFlag() async throws {
        let manager = makeManager()
        let router = NotificationDelegateRouter(sink: manager, isApplicationInForeground: { true })
        router.noteFirstInstall(applicationIsActive: false)

        router.didReceive(TestNotificationKind.library.response(identifier: "launch"), previous: nil, completion: {})
        await drainMainQueue(times: 2)
        router.noteDidBecomeActive()

        #expect(manager.responses.keptCount == 1)
        var events: [NotificationResponseEvent] = []
        try manager.responses.addListener { event, _ in events.append(event) }
        #expect(events.map(\.notificationIdentifier) == ["launch"])
        #expect(events.map(\.isLaunchResponse) == [true])
    }

    // MARK: launchResponse()

    @Test func theLaunchResponseIsTheRoutersResponseAsAnEvent() throws {
        let response = TestNotificationKind.library.response(identifier: "launch", action: "open")
        let manager = makeManager(launchResponse: response)
        let event = try #require(try manager.launchResponse())
        #expect(event == NotificationResponseEvent(
            notificationIdentifier: "launch",
            actionIdentifier: "open",
            categoryIdentifier: "category",
            userText: nil,
            userInfo: ["k": .string("v")],
            isLaunchResponse: true
        ))
    }

    @Test func withoutALaunchResponseItIsNil() throws {
        #expect(try makeManager().launchResponse() == nil)
    }
}
