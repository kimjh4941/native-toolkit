//
//  NotificationDelegateProxyTests.swift
//  IosLibraryTests
//

import Foundation
import Testing
import UserNotifications
@testable import IosLibrary

/// The parts of the proxy that do not need a `UNNotification` (which tests cannot make): the
/// previous delegate's `responds(to:)` check on every call (part 1, 5.12.1), the values the
/// router gets, and what reaches the existing receivers.
@MainActor
struct NotificationDelegateProxyTests {

    private func install(_ host: (any UNUserNotificationCenterDelegate)?) -> (NotificationDelegateInstaller, FakeNotificationCenter) {
        let installer = NotificationDelegateInstaller(sink: IgnoringSink(), presentationOptions: { libraryTestOptions },
                                                      notificationCenter: NotificationCenter())
        let center = FakeNotificationCenter()
        center.delegate = host
        _ = installer.install(on: center, applicationIsActive: false)
        return (installer, center)
    }

    private static let selectors = [
        NotificationDelegateProxy.willPresentSelector,
        NotificationDelegateProxy.didReceiveSelector,
        NotificationDelegateProxy.openSettingsSelector,
    ]

    @Test func aPreviousDelegateThatImplementsTheMethodsIsUsed() {
        let host = FullHostDelegate()
        let (installer, center) = install(host)
        defer { center.removeObserver(installer.proxy, forKeyPath: NotificationDelegateProxy.delegateKeyPath) }

        for selector in Self.selectors {
            #expect(installer.proxy.previousDelegate(responding: selector) === host, "\(selector)")
        }
    }

    /// "noimpl" of the 1a table: the previous delegate exists but implements none of the methods,
    /// so the router gets no closure (and handles the call like "none").
    @Test func aPreviousDelegateThatImplementsNothingIsNotUsed() {
        let host = BareHostDelegate()
        let (installer, center) = install(host)
        defer { center.removeObserver(installer.proxy, forKeyPath: NotificationDelegateProxy.delegateKeyPath) }

        #expect(installer.proxy.previousDelegate === host)
        for selector in Self.selectors {
            #expect(installer.proxy.previousDelegate(responding: selector) == nil, "\(selector)")
        }
    }

    /// The check is made on every call: a delegate whose answer changes is followed.
    @Test func respondsToIsCheckedOnEveryCall() {
        let host = SwitchingHostDelegate()
        let (installer, center) = install(host)
        defer { center.removeObserver(installer.proxy, forKeyPath: NotificationDelegateProxy.delegateKeyPath) }

        #expect(installer.proxy.previousDelegate(responding: NotificationDelegateProxy.didReceiveSelector) === host)
        host.implements = false
        #expect(installer.proxy.previousDelegate(responding: NotificationDelegateProxy.didReceiveSelector) == nil)
    }

    @Test func theForegroundOfAnActionFollowsH21() {
        #expect(NotificationDelegateProxy.foreground(ofAction: UNNotificationDefaultActionIdentifier) == .always)
        #expect(NotificationDelegateProxy.foreground(ofAction: UNNotificationDismissActionIdentifier) == .never)
        #expect(NotificationDelegateProxy.foreground(ofAction: "open") == .whenTheApplicationIsInTheForeground)
        #expect(NotificationDelegateProxy.foreground(ofAction: "") == .whenTheApplicationIsInTheForeground)
        // For a custom action, the router reads the application state on the main queue.
        #expect(NotificationDelegateProxy.bringsAppToForeground(.active))
        #expect(NotificationDelegateProxy.bringsAppToForeground(.inactive))
        #expect(!NotificationDelegateProxy.bringsAppToForeground(.background))
    }

    @Test func theRouterSeesThePushAndTheMarker() {
        #expect(TestNotificationKind.library.notification().isLibraryNotification)
        #expect(!TestNotificationKind.pushWithMarker.notification().isLibraryNotification, "a push is never the library's (1a-12)")
        #expect(!TestNotificationKind.host.notification().isLibraryNotification)
        #expect(!TestNotificationKind.push.notification().isLibraryNotification)
        #expect(NotificationMarker.isPresent(in: [NotificationMarker.key: "anything"]))
        #expect(!NotificationMarker.isPresent(in: ["com.jonghyunkim.nativetoolkit.other": 1]))
    }
}

/// The userInfo of a delivered notification as the router gets it: the value tree without the
/// marker (design S-P11, 8.3.3).
struct NotificationDelegateUserInfoTests {

    @Test func theMarkerIsRemovedAndTheOtherValuesKept() {
        let values = NotificationDelegateProxy.userInfoValues(of: [
            NotificationMarker.key: NotificationMarker.value, "k": "v", "n": 3,
        ])
        #expect(values == ["k": .string("v"), "n": .integer(3)])
    }

    @Test func anEmptyUserInfoStaysEmpty() {
        #expect(NotificationDelegateProxy.userInfoValues(of: [:]).isEmpty)
        #expect(NotificationDelegateProxy.userInfoValues(of: [NotificationMarker.key: 1]).isEmpty)
    }

    /// The system never delivers it, but a value outside the property-list types must not crash.
    @Test func aValueThatIsNotAPropertyListIsLeftOut() {
        let values = NotificationDelegateProxy.userInfoValues(of: ["object": NSObject(), "k": "v"])
        #expect(values == ["k": .string("v")])
    }
}

/// What `IosNotificationManager` (the library's sink) does with a response and a settings
/// request: the existing receivers, on the main thread (design 3.3), and the settings request as
/// an event (P1-10).
@MainActor
struct IosNotificationManagerDelegateSinkTests {

    private func makeManager() -> (IosNotificationManager, MockNotificationRepository) {
        let repository = MockNotificationRepository()
        let manager = IosNotificationManager(
            repository: repository,
            delegateStatus: NotificationDelegateStatus(isInstalled: { true }, launchResponse: { nil })
        )
        return (manager, repository)
    }

    @Test func aTapReachesOnActionReceived() {
        let (manager, _) = makeManager()
        let actions = CompletionRecorder<[String]>()
        let texts = CompletionRecorder<[String]>()
        deprecatedNotification.setReceivers(
            of: manager,
            action: { id, action, userInfo in actions.handler([id, action, "\(userInfo["k"] as? String ?? "-")"]) },
            textInput: { id, action, text, _ in texts.handler([id, action, text]) }
        )

        manager.deliver(response: TestNotificationKind.legacy.response(identifier: "n", action: "open"), isLaunchResponse: false)

        let received = actions.all.map { $0.value }
        #expect(received == [["n", "open", "v"]])
        let onMain = actions.all.allSatisfy { $0.isMainThread }
        #expect(onMain)
        #expect(texts.count == 0)
    }

    /// A text input response (even an empty reply) reaches onTextInputActionReceived only.
    @Test(arguments: ["hello reply", ""])
    func aReplyReachesOnTextInputActionReceived(reply: String) {
        let (manager, _) = makeManager()
        let actions = CompletionRecorder<[String]>()
        let texts = CompletionRecorder<[String]>()
        deprecatedNotification.setReceivers(
            of: manager,
            action: { id, action, _ in actions.handler([id, action]) },
            textInput: { id, action, text, _ in texts.handler([id, action, text]) }
        )

        manager.deliver(response: TestNotificationKind.host.response(identifier: "n", action: "reply", userText: reply), isLaunchResponse: true)

        let replies = texts.all.map { $0.value }
        #expect(replies == [["n", "reply", reply]])
        #expect(actions.count == 0)
    }

    /// The existing receivers get the userInfo without the marker, with Foundation types.
    @Test func theExistingReceiversGetTheUserInfoWithoutTheMarker() throws {
        let (manager, _) = makeManager()
        let received = CompletionRecorder<[String]>()
        deprecatedNotification.setReceivers(
            of: manager,
            action: { _, _, userInfo in
                received.handler(userInfo.keys.compactMap { $0.base as? String }.sorted() + ["\(userInfo["k"] as? String ?? "-")"])
            },
            textInput: nil
        )

        manager.deliver(response: TestNotificationKind.library.response(), isLaunchResponse: false)

        #expect(received.all.map(\.value) == [["k", "v"]])
    }

    @Test func noReceiverIsFine() {
        let (manager, _) = makeManager()
        manager.deliver(response: TestNotificationKind.host.response(), isLaunchResponse: false)
    }

    /// A settings request the library handles is an event of `settingsRequests`; the library no
    /// longer opens the Settings app (design P1-10, 3.3).
    @Test func aSettingsRequestIsAnEventAndOpensNothing() throws {
        let (manager, repository) = makeManager()
        var requests: [NotificationSettingsRequest] = []
        try manager.settingsRequests.addListener { request, _ in requests.append(request) }

        manager.deliver(settingsRequestFor: nil)
        manager.deliver(settingsRequestFor: "n-1")

        #expect(requests == [NotificationSettingsRequest(notificationIdentifier: nil), NotificationSettingsRequest(notificationIdentifier: "n-1")])
        #expect(repository.openSettingsCallCount == 0)
    }
}

/// A host delegate that implements `didReceive` until told otherwise.
private final class SwitchingHostDelegate: NSObject, UNUserNotificationCenterDelegate {
    var implements = true

    override func responds(to aSelector: Selector!) -> Bool {
        if aSelector == NotificationDelegateProxy.didReceiveSelector { return implements }
        return super.responds(to: aSelector)
    }

    func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse,
                                withCompletionHandler completionHandler: @escaping @Sendable () -> Void) {
        completionHandler()
    }
}
