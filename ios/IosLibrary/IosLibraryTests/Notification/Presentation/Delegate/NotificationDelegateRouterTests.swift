//
//  NotificationDelegateRouterTests.swift
//  IosLibraryTests
//

import Foundation
import Synchronization
import Testing
import UserNotifications
@testable import IosLibrary

/// UT-19: the combination table of stage 1a (delegate notes, chapter 3): the three methods ×
/// the previous delegate's behaviour × the kind of notification. In every combination the system
/// completion is called at most once, and exactly once unless the previous delegate drops or keeps
/// it; the library's notifications never reach the previous delegate (1a-7); the others reach it
/// when it implements the method, and are handled like the library's when it does not (1a-6).
///
/// "Not implemented" is the same as "none" for the router (the proxy passes no closure); the
/// proxy's `responds(to:)` check is in `NotificationDelegateProxyTests`.
struct NotificationDelegateRouterTableTests {

    private static let kinds = TestNotificationKind.allCases
    private static let behaviors = PreviousBehavior.allCases

    @Test(arguments: kinds, behaviors)
    func willPresent(kind: TestNotificationKind, behavior: PreviousBehavior) async {
        let sink = RecordingSink()
        let router = NotificationDelegateRouter.forTests(sink)
        let previous = FakePrevious(behavior)
        let system = CompletionRecorder<UNNotificationPresentationOptions>()

        router.willPresent(kind.notification(), previous: previous.willPresent, libraryOptions: { libraryTestOptions },
                           completion: system.handler)
        let atReturn = system.count
        await settle()

        let forwarded = !kind.isLibrary && behavior != .none
        if !forwarded { #expect(atReturn == 1, "the library completes inside the call") }
        #expect(previous.callCount == (forwarded ? 1 : 0), "the previous delegate is called only for others' notifications")
        #expect(system.count <= 1)
        #expect(system.count == (forwarded ? behavior.expectedSystemCompletions : 1))
        if let call = system.all.first {
            #expect(call.value == (forwarded ? FakePrevious.hostOptions : libraryTestOptions),
                    "a forwarded call keeps the previous delegate's options, the library's use the library's")
            if forwarded && behavior == .asyncBackground { #expect(!call.isMainThread) }
        }
        #expect(sink.all.isEmpty, "willPresent never makes an event")
    }

    @Test(arguments: kinds, behaviors)
    func didReceive(kind: TestNotificationKind, behavior: PreviousBehavior) async {
        let order = Mutex<[String]>([])
        let system = CompletionRecorder<Void>()
        let sink = RecordingSink(onResponse: { order.withLock { $0.append("event(completions=\(system.count))") } })
        let router = NotificationDelegateRouter.forTests(sink)
        let previous = FakePrevious(behavior)

        router.didReceive(kind.response(), previous: previous.didReceive, completion: { system.handler(()) })
        #expect(system.count == 0 || (!kind.isLibrary && behavior != .none),
                "a response the library handles is completed later, on the main queue")
        await settle()

        let forwarded = !kind.isLibrary && behavior != .none
        #expect(previous.callCount == (forwarded ? 1 : 0))
        #expect(system.count <= 1)
        #expect(system.count == (forwarded ? behavior.expectedSystemCompletions : 1))
        if forwarded {
            #expect(sink.all.isEmpty, "a forwarded response makes no library event")
        } else {
            #expect(sink.responses.map { $0.identifier } == ["n-1"])
            #expect(sink.responses.allSatisfy { $0.isMainThread })
            #expect(order.withLock { $0 } == ["event(completions=0)"], "the event is handed over before the system completion (1a-12)")
            #expect(system.all.allSatisfy { $0.isMainThread })
        }
    }

    @Test(arguments: kinds, [PreviousBehavior.none, .sync])
    func openSettings(kind: TestNotificationKind, behavior: PreviousBehavior) async {
        let sink = RecordingSink()
        let router = NotificationDelegateRouter.forTests(sink)
        let previous = FakePrevious(behavior)

        router.openSettings(for: kind.notification(), previous: previous.openSettings)
        await settle()

        let forwarded = !kind.isLibrary && behavior != .none
        #expect(previous.callCount == (forwarded ? 1 : 0))
        #expect(sink.settingsRequests.map { $0.identifier } == (forwarded ? [] : ["n-1"]))
        #expect(sink.settingsRequests.allSatisfy { $0.isMainThread })
    }

    /// `openSettingsFor` without a notification (from Settings) is not the library's (part 1 R-13).
    @Test(arguments: [PreviousBehavior.none, .sync])
    func openSettingsWithoutANotification(behavior: PreviousBehavior) async {
        let sink = RecordingSink()
        let router = NotificationDelegateRouter.forTests(sink)
        let previous = FakePrevious(behavior)

        router.openSettings(for: nil, previous: previous.openSettings)
        await settle()

        #expect(previous.callCount == (behavior == .none ? 0 : 1))
        #expect(sink.settingsRequests.count == (behavior == .none ? 1 : 0))
        #expect(sink.settingsRequests.first?.identifier == nil)
    }

    /// The system completion of a forwarded call reaches the system on the thread the previous
    /// delegate used, without the library holding anything (a race of 8 threads on one handler).
    @Test func aPreviousDelegateCallingTheHandlerFromManyThreadsCompletesOnce() async {
        let system = CompletionRecorder<Void>()
        let router = NotificationDelegateRouter.forTests(RecordingSink())
        let handler = Mutex<(@Sendable () -> Void)?>(nil)

        router.didReceive(TestNotificationKind.host.response(), previous: { h in handler.withLock { $0 = h } },
                          completion: { system.handler(()) })
        let taken = handler.withLock { $0 }
        await withTaskGroup(of: Void.self) { group in
            for _ in 0..<8 {
                group.addTask { await withCheckedContinuation { c in Thread { for _ in 0..<25 { taken?() }; c.resume() }.start() } }
            }
        }

        #expect(system.count == 1)
    }
}

/// UT-20: cycle prevention (P1-21, part 1 5.12.5). A call that comes back synchronously while it
/// is being forwarded is handled as unclaimed; nothing else is stopped.
struct NotificationDelegateRouterCycleTests {

    @Test func willPresentComingBackIsHandledByTheLibrary() async {
        let router = NotificationDelegateRouter.forTests(RecordingSink())
        let system = CompletionRecorder<UNNotificationPresentationOptions>()
        let forwards = Mutex(0)
        let note = TestNotificationKind.host.notification()
        // A host that forwards to its previous delegate, which is the proxy again.
        func host(_ handler: @escaping @Sendable (UNNotificationPresentationOptions) -> Void) {
            forwards.withLock { $0 += 1 }
            router.willPresent(note, previous: host, libraryOptions: { libraryTestOptions }, completion: handler)
        }

        router.willPresent(note, previous: host, libraryOptions: { libraryTestOptions }, completion: system.handler)
        await settle()

        #expect(forwards.withLock { $0 } == 1, "the inner call is not forwarded again")
        #expect(system.all.map { $0.value } == [libraryTestOptions])
    }

    @Test func didReceiveComingBackMakesOneEventAndOneCompletion() async {
        let sink = RecordingSink()
        let router = NotificationDelegateRouter.forTests(sink)
        let system = CompletionRecorder<Void>()
        let forwards = Mutex(0)
        let response = TestNotificationKind.host.response()
        func host(_ handler: @escaping @Sendable () -> Void) {
            forwards.withLock { $0 += 1 }
            router.didReceive(response, previous: host, completion: handler)
        }

        router.didReceive(response, previous: host, completion: { system.handler(()) })
        await settle()

        #expect(forwards.withLock { $0 } == 1)
        #expect(sink.responses.count == 1)
        #expect(sink.responses.first?.isLaunchResponse == false, "a cycle is never the launch response (R4-3)")
        #expect(system.count == 1)
        #expect(router.launchResponse == nil)
    }

    @Test func openSettingsWithoutANotificationComingBackMakesOneEvent() async {
        let sink = RecordingSink()
        let router = NotificationDelegateRouter.forTests(sink)
        let forwards = Mutex(0)
        func host() {
            forwards.withLock { $0 += 1 }
            router.openSettings(for: nil, previous: host)
        }

        router.openSettings(for: nil, previous: host)
        await settle()

        #expect(forwards.withLock { $0 } == 1)
        #expect(sink.settingsRequests.count == 1)
    }

    /// The inner call of a cycle is never the launch response, also when the outer (forwarded)
    /// one did not use up the first place: here the application state reads background for the
    /// outer note and foreground for the inner one (a custom action).
    @MainActor
    @Test func theInnerCallOfACycleIsNeverTheLaunchResponse() async {
        let sink = RecordingSink()
        let reads = Mutex(0)
        let router = NotificationDelegateRouter.forTests(sink, isApplicationInForeground: {
            reads.withLock { count in
                count += 1
                return count > 1
            }
        })
        let response = TestNotificationKind.host.response(action: "open", foreground: .whenTheApplicationIsInTheForeground)
        func host(_ handler: @escaping @Sendable () -> Void) {
            router.didReceive(response, previous: host, completion: handler)
        }

        router.didReceive(response, previous: host, completion: {})
        await settle()

        #expect(reads.withLock { $0 } == 2)
        #expect(sink.responses.map { $0.isLaunchResponse } == [false])
        #expect(router.launchResponse == nil)
    }

    /// Another delivery of the same identifier (another date) is not a cycle.
    @Test func theSameIdentifierWithAnotherDateIsForwarded() async {
        let router = NotificationDelegateRouter.forTests(RecordingSink())
        let system = CompletionRecorder<UNNotificationPresentationOptions>()
        let inner = CompletionRecorder<UNNotificationPresentationOptions>()
        let forwards = Mutex(0)
        let first = TestNotificationKind.host.notification(date: Date(timeIntervalSince1970: 1_000))
        let second = TestNotificationKind.host.notification(date: Date(timeIntervalSince1970: 1_001))
        let answer: NotificationDelegateRouter.ForwardWillPresent<UNNotificationPresentationOptions> = { handler in
            forwards.withLock { $0 += 1 }
            handler(FakePrevious.hostOptions)
        }

        router.willPresent(first, previous: { handler in
            forwards.withLock { $0 += 1 }
            router.willPresent(second, previous: answer, libraryOptions: { libraryTestOptions }, completion: inner.handler)
            handler(FakePrevious.hostOptions)
        }, libraryOptions: { libraryTestOptions }, completion: system.handler)
        await settle()

        #expect(forwards.withLock { $0 } == 2)
        #expect(inner.all.map { $0.value } == [FakePrevious.hostOptions])
        #expect(system.all.map { $0.value } == [FakePrevious.hostOptions])
    }

    /// A different action of the same delivery is not a cycle either (the key has the action).
    @Test func anotherActionOfTheSameDeliveryIsForwarded() async {
        let router = NotificationDelegateRouter.forTests(RecordingSink())
        let forwards = Mutex(0)
        let open = TestNotificationKind.host.response(action: "open")
        let delete = TestNotificationKind.host.response(action: "delete")
        let answer: NotificationDelegateRouter.ForwardDidReceive = { handler in
            forwards.withLock { $0 += 1 }
            handler()
        }

        router.didReceive(open, previous: { handler in
            forwards.withLock { $0 += 1 }
            router.didReceive(delete, previous: answer, completion: {})
            handler()
        }, completion: {})
        await settle()

        #expect(forwards.withLock { $0 } == 2)
    }

    /// The key is taken out when the forwarding call returns: the next call is forwarded again.
    @Test func theSameNotificationLaterIsForwardedAgain() async {
        let router = NotificationDelegateRouter.forTests(RecordingSink())
        let previous = FakePrevious(.sync)
        let system = CompletionRecorder<UNNotificationPresentationOptions>()
        let note = TestNotificationKind.host.notification()

        router.willPresent(note, previous: previous.willPresent, libraryOptions: { libraryTestOptions }, completion: system.handler)
        router.willPresent(note, previous: previous.willPresent, libraryOptions: { libraryTestOptions }, completion: system.handler)

        #expect(previous.callCount == 2)
        #expect(system.all.map { $0.value } == [FakePrevious.hostOptions, FakePrevious.hostOptions])
    }

    /// A previous delegate that comes back later (asynchronously) is outside the contract: the
    /// router forwards it again (it does not stop it). Checked only so that the contract is
    /// visible in the tests.
    @Test func comingBackAfterTheForwardingCallReturnedIsNotStopped() async {
        let router = NotificationDelegateRouter.forTests(RecordingSink())
        let forwards = CompletionRecorder<Void>()
        let note = TestNotificationKind.host.notification()
        let done = CompletionRecorder<UNNotificationPresentationOptions>()

        router.willPresent(note, previous: { handler in
            forwards.handler(())
            DispatchQueue.main.async {
                router.willPresent(note, previous: { h in forwards.handler(()); h([]) },
                                   libraryOptions: { libraryTestOptions }, completion: handler)
            }
        }, libraryOptions: { libraryTestOptions }, completion: done.handler)
        await settle()

        #expect(forwards.count == 2)
        #expect(done.count == 1)
    }
}

/// UT-22: the launch response (P1-22 as narrowed by H2-1). The first response of the process
/// that brings the app to the foreground, arriving before the app was active, is the launch
/// response when the library handles it; forwarded ones and cycles never are; background actions
/// do not count.
@MainActor
struct NotificationDelegateRouterLaunchTests {

    @Test func aTapOnTheLibrarysNotificationBeforeTheAppIsActiveIsTheLaunchResponse() async {
        let sink = RecordingSink()
        let router = NotificationDelegateRouter.forTests(sink)
        let response = TestNotificationKind.library.response()

        router.didReceive(response, previous: nil, completion: {})
        await settle()

        #expect(sink.responses.map { $0.isLaunchResponse } == [true])
        #expect(router.launchResponse == response)
        #expect(router.isLaunchResponseSettled)
    }

    /// An unclaimed notification (no previous delegate) is handled by the library, so it can be
    /// the launch response.
    @Test func anUnclaimedNotificationCanBeTheLaunchResponse() async {
        let sink = RecordingSink()
        let router = NotificationDelegateRouter.forTests(sink)

        router.didReceive(TestNotificationKind.host.response(), previous: nil, completion: {})
        await settle()

        #expect(sink.responses.map { $0.isLaunchResponse } == [true])
    }

    @Test func aResponseAfterTheAppBecameActiveIsNot() async {
        let sink = RecordingSink()
        let router = NotificationDelegateRouter.forTests(sink)
        router.noteDidBecomeActive()

        router.didReceive(TestNotificationKind.library.response(), previous: nil, completion: {})
        await settle()

        #expect(sink.responses.map { $0.isLaunchResponse } == [false])
        #expect(router.launchResponse == nil)
        #expect(router.isLaunchResponseSettled)
    }

    @Test func noneWhenTheAppWasActiveAtTheFirstInstall() async {
        let sink = RecordingSink()
        let router = NotificationDelegateRouter.forTests(sink)
        router.noteFirstInstall(applicationIsActive: true)

        router.didReceive(TestNotificationKind.library.response(), previous: nil, completion: {})
        await settle()

        #expect(sink.responses.map { $0.isLaunchResponse } == [false])
    }

    @Test func aFirstInstallWhileInactiveLeavesItOpen() async {
        let sink = RecordingSink()
        let router = NotificationDelegateRouter.forTests(sink)
        router.noteFirstInstall(applicationIsActive: false)
        #expect(!router.isLaunchResponseSettled)

        router.didReceive(TestNotificationKind.library.response(), previous: nil, completion: {})
        await settle()

        #expect(sink.responses.map { $0.isLaunchResponse } == [true])
    }

    /// iOS 18.3 ran the main-queue block after `didBecomeActive` at a cold start (MS-05): what
    /// counts is when the response arrived.
    @Test func becomingActiveBeforeTheMainQueueBlockRunsKeepsIt() async {
        let sink = RecordingSink()
        let router = NotificationDelegateRouter.forTests(sink)

        router.didReceive(TestNotificationKind.library.response(), previous: nil, completion: {})
        router.noteDidBecomeActive()
        await settle()

        #expect(sink.responses.map { $0.isLaunchResponse } == [true])
    }

    /// The first response went to the host: there is no launch response for the library, also
    /// when the library handles a later one before the app is active.
    @Test func aForwardedFirstResponseLeavesNone() async {
        let sink = RecordingSink()
        let router = NotificationDelegateRouter.forTests(sink)

        router.didReceive(TestNotificationKind.host.response(identifier: "host"), previous: FakePrevious(.sync).didReceive, completion: {})
        router.didReceive(TestNotificationKind.library.response(identifier: "lib"), previous: nil, completion: {})
        await settle()

        #expect(sink.responses.map { $0.identifier } == ["lib"])
        #expect(sink.responses.map { $0.isLaunchResponse } == [false])
        #expect(router.launchResponse == nil)
    }

    @Test func onlyTheFirstOfTwoResponsesIsTheLaunchResponse() async {
        let sink = RecordingSink()
        let router = NotificationDelegateRouter.forTests(sink)

        router.didReceive(TestNotificationKind.library.response(identifier: "a"), previous: nil, completion: {})
        router.didReceive(TestNotificationKind.library.response(identifier: "b"), previous: nil, completion: {})
        await settle()

        #expect(sink.responses.map { $0.isLaunchResponse } == [true, false])
        #expect(router.launchResponse?.notification.identifier == "a")
    }

    /// H2-1: a background action (the app stays in the background) is an ordinary event and does
    /// not use up the first place; the first response that brings the app to the foreground does.
    @Test func aBackgroundActionIsNotTheLaunchResponse() async {
        let sink = RecordingSink()
        let inForeground = Mutex(false)
        let router = NotificationDelegateRouter.forTests(sink, isApplicationInForeground: { inForeground.withLock { $0 } })

        router.didReceive(TestNotificationKind.library.response(identifier: "bg", action: "delete",
                                                               foreground: .whenTheApplicationIsInTheForeground),
                          previous: nil, completion: {})
        await settle()
        #expect(sink.responses.map { $0.isLaunchResponse } == [false])
        #expect(router.launchResponse == nil)
        #expect(!router.isLaunchResponseSettled)

        inForeground.withLock { $0 = true }
        router.didReceive(TestNotificationKind.library.response(identifier: "tap"), previous: nil, completion: {})
        await settle()

        #expect(sink.responses.map { $0.isLaunchResponse } == [false, true])
        #expect(router.launchResponse?.notification.identifier == "tap")
    }

    @Test func aForegroundActionIsTheLaunchResponse() async {
        let sink = RecordingSink()
        let router = NotificationDelegateRouter.forTests(sink, isApplicationInForeground: { true })

        router.didReceive(TestNotificationKind.library.response(action: "open", foreground: .whenTheApplicationIsInTheForeground),
                          previous: nil, completion: {})
        await settle()

        #expect(sink.responses.map { $0.isLaunchResponse } == [true])
    }

    @Test func theDismissActionIsNeverTheLaunchResponse() async {
        let sink = RecordingSink()
        let router = NotificationDelegateRouter.forTests(sink, isApplicationInForeground: { true })

        router.didReceive(TestNotificationKind.library.response(action: UNNotificationDismissActionIdentifier, foreground: .never),
                          previous: nil, completion: {})
        await settle()

        #expect(sink.responses.map { $0.isLaunchResponse } == [false])
        #expect(router.launchResponse == nil)
    }

    /// A forwarded background action does not use up the first place either.
    @Test func aForwardedBackgroundActionLeavesTheFirstPlace() async {
        let sink = RecordingSink()
        let inForeground = Mutex(false)
        let router = NotificationDelegateRouter.forTests(sink, isApplicationInForeground: { inForeground.withLock { $0 } })

        router.didReceive(TestNotificationKind.host.response(identifier: "host", action: "delete",
                                                            foreground: .whenTheApplicationIsInTheForeground),
                          previous: FakePrevious(.sync).didReceive, completion: {})
        await settle()
        inForeground.withLock { $0 = true }
        router.didReceive(TestNotificationKind.library.response(identifier: "lib"), previous: nil, completion: {})
        await settle()

        #expect(sink.responses.map { $0.isLaunchResponse } == [true])
    }
}
