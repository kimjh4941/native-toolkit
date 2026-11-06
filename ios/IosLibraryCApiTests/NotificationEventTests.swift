//
//  NotificationEventTests.swift
//  IosLibraryCApiTests
//

import Foundation
import UserNotifications
import XCTest
@testable import IosLibrary
@testable import IosLibraryCApi

/// What one interaction handle held; the handle is read through C and freed inside the callback.
struct InteractionSeen: Equatable {
    let kind: Int32
    let notificationId: String?
    let actionId: String?
    let categoryId: String?
    let userText: String?
    let userInfoJson: String?
    let isLaunch: Int32
}

/// The events one registration received. Kept by the test object for as long as it lives.
final class EventRecorder: @unchecked Sendable {
    private let lock = NSLock()
    private var interactionList: [InteractionSeen] = []
    private var settingsList: [String?] = []
    private var releaseList: [Bool] = []
    /// Runs inside an interaction callback, after it was recorded.
    var onInteraction: (@Sendable () -> Void)?
    let outListener: UnsafeMutablePointer<OpaquePointer?>

    init() {
        outListener = .allocate(capacity: 1)
        outListener.initialize(to: OpaquePointer(bitPattern: 0x1))
    }

    deinit {
        outListener.deallocate()
    }

    var userData: UnsafeMutableRawPointer { Unmanaged.passUnretained(self).toOpaque() }

    static func from(_ userData: UnsafeMutableRawPointer?) -> EventRecorder? {
        userData.map { Unmanaged<EventRecorder>.fromOpaque($0).takeUnretainedValue() }
    }

    var interactions: [InteractionSeen] { lock.withLock { interactionList } }
    var settingsRequests: [String?] { lock.withLock { settingsList } }
    var releases: [Bool] { lock.withLock { releaseList } }

    func record(_ seen: InteractionSeen) {
        lock.withLock {
            interactionList.append(seen)
        }
        onInteraction?()
    }

    func record(settings identifier: String?) {
        lock.withLock { settingsList.append(identifier) }
    }

    func recordRelease() {
        let onMain = Thread.isMainThread
        lock.withLock { releaseList.append(onMain) }
    }
}

private func text(_ pointer: UnsafePointer<CChar>?) -> String? {
    pointer.map { String(cString: $0) }
}

/// Reads an interaction through C, checks that `out_size` matches, and frees it.
func seen(_ event: OpaquePointer?) -> InteractionSeen {
    var size = -1
    let json = text(ntk_notification_interaction_user_info_json(event, &size))
    precondition(size == (json?.utf8.count ?? 0))
    return InteractionSeen(kind: ntk_notification_interaction_kind(event),
                           notificationId: text(ntk_notification_interaction_notification_id(event, nil)),
                           actionId: text(ntk_notification_interaction_action_id(event, nil)),
                           categoryId: text(ntk_notification_interaction_category_id(event, nil)),
                           userText: text(ntk_notification_interaction_user_text(event, nil)),
                           userInfoJson: json, isLaunch: ntk_notification_interaction_is_launch(event))
}

func recordInteraction(_ userData: UnsafeMutableRawPointer?, _ event: OpaquePointer?) {
    let value = seen(event)
    ntk_notification_interaction_free(event)
    EventRecorder.from(userData)?.record(value)
}

func recordSettingsRequest(_ userData: UnsafeMutableRawPointer?, _ request: OpaquePointer?) {
    let identifier = text(ntk_notification_settings_request_notification_id(request, nil))
    ntk_notification_settings_request_free(request)
    EventRecorder.from(userData)?.record(settings: identifier)
}

func recordEventRelease(_ userData: UnsafeMutableRawPointer?) {
    EventRecorder.from(userData)?.recordRelease()
}

/// OP-42 to OP-45 through C, without the library's delegate (part 2, 12.1, "イベント" and "delegate"). These tests
/// also run on the private device under ASan, so **nothing here reaches the notification center or the library's
/// hubs**: the receiver's `Events` is replaced in `setUp` by one that fails the test when it is used, and a test
/// that needs it installs a fake. Events are handed to the receiver's `receive`, which the library's listener calls.
/// The ledgers are shared by the whole process: each test first takes away what an earlier one left held.
final class NotificationEventTests: ClipboardTestCase {
    private let none: Int32 = 0
    private let invalid: Int32 = 1
    private let notInitialized: Int32 = 2
    private var recorders: [EventRecorder] = []
    private var clipboardRecorders: [ClipboardRecorder] = []

    /// How many times a fake was asked to add the library's listener, over the whole run: only the first insertion
    /// of each kind does (AP-21).
    nonisolated(unsafe) private static var interactionSubscriptions = 0
    nonisolated(unsafe) private static var settingsSubscriptions = 0

    private static let failing = NotificationReceiver.Events(
        isDelegateInstalled: { false },
        subscribeInteractions: { _ in XCTFail("the library's interaction hub was reached without a fake") },
        subscribeSettingsRequests: { _ in XCTFail("the library's settings hub was reached without a fake") },
        launchResponse: {
            XCTFail("launchResponse was reached without a fake")
            return nil
        })

    override func setUpWithError() throws {
        try super.setUpWithError()
        NotificationReceiver.events.withLock { $0 = Self.failing }
    }

    /// The failing `Events` is put back after each test and stays after this class: a block a test queued and that
    /// runs later finds it, not the library. A test that uses the event entries installs its own fake; nothing else
    /// in this process uses them.
    override func tearDown() async throws {
        NotificationReceiver.events.withLock { $0 = Self.failing }
        try await super.tearDown()
    }

    private func kept() -> EventRecorder {
        let recorder = EventRecorder()
        recorders.append(recorder)
        return recorder
    }

    private func keptClipboardRecorder() -> ClipboardRecorder {
        let recorder = ClipboardRecorder()
        clipboardRecorders.append(recorder)
        return recorder
    }

    /// The launch responses a fake gives, one per call; the last one stays.
    @MainActor
    private final class LaunchResponses {
        var values: [NotificationResponseEvent?]
        var calls = 0

        init(_ values: [NotificationResponseEvent?]) {
            self.values = values
        }

        func next() -> NotificationResponseEvent? {
            calls += 1
            return values.count > 1 ? values.removeFirst() : values.first ?? nil
        }
    }

    /// Installs a fake whose delegate is installed and whose launch response is `launch` (or each of `launches` in
    /// turn), and takes away the events an earlier test left held.
    private func installFake(launch: NotificationResponseEvent? = nil, launches: LaunchResponses? = nil, launchFailure: (any Error)? = nil) {
        NotificationReceiver.events.withLock {
            $0 = NotificationReceiver.Events(
                isDelegateInstalled: { true },
                subscribeInteractions: { _ in Self.interactionSubscriptions += 1 },
                subscribeSettingsRequests: { _ in Self.settingsSubscriptions += 1 },
                launchResponse: {
                    if let launchFailure { throw launchFailure }
                    return launches?.next() ?? launch
                })
        }
        let interactions = add()
        let settings = addSettings()
        runMainQueue()
        ntk_notification_listener_remove(interactions.outListener.pointee)
        ntk_notification_listener_remove(settings.outListener.pointee)
        runMainQueue()
    }

    private func add(file: StaticString = #filePath, line: UInt = #line) -> EventRecorder {
        let recorder = kept()
        XCTAssertEqual(ntk_notification_add_interaction_listener(recordInteraction, recorder.userData, recordEventRelease, recorder.outListener),
                       none, file: file, line: line)
        XCTAssertNotNil(recorder.outListener.pointee, file: file, line: line)
        return recorder
    }

    private func addSettings(file: StaticString = #filePath, line: UInt = #line) -> EventRecorder {
        let recorder = kept()
        XCTAssertEqual(ntk_notification_add_settings_request_listener(recordSettingsRequest, recorder.userData, recordEventRelease,
                                                                      recorder.outListener), none, file: file, line: line)
        return recorder
    }

    private func event(_ identifier: String = "n1", action: String = UNNotificationDefaultActionIdentifier, category: String = "",
                       text: String? = nil, userInfo: [String: NotificationUserInfoValue] = [:], launch: Bool = false) -> NotificationResponseEvent {
        NotificationResponseEvent(notificationIdentifier: identifier, actionIdentifier: action, categoryIdentifier: category,
                                  userText: text, userInfo: userInfo, isLaunchResponse: launch)
    }

    private let bodyTap = InteractionSeen(kind: 0, notificationId: "n1", actionId: UNNotificationDefaultActionIdentifier, categoryId: "",
                                          userText: nil, userInfoJson: "{}", isLaunch: 0)

    // MARK: - Rejected at the entry

    private struct Add: @unchecked Sendable {
        let name: String
        let call: (_ withCallback: Bool, _ userData: UnsafeMutableRawPointer?, _ release: ntk_release_fn?,
                   _ out: UnsafeMutablePointer<OpaquePointer?>?) -> Int32
    }

    private let adds = [
        Add(name: "interaction") { ntk_notification_add_interaction_listener($0 ? recordInteraction : nil, $1, $2, $3) },
        Add(name: "settings") { ntk_notification_add_settings_request_listener($0 ? recordSettingsRequest : nil, $1, $2, $3) },
    ]

    /// The entry's checks come before NOT_INITIALIZED (part 2, 11); the output is NULL on every rejection (R-8), and
    /// the release comes on the calling thread before the call returns.
    func testTheAddsRejectAtTheEntry() {
        for add in adds {
            for (name, withCallback, withOut, expected) in [("NULL callback", false, true, invalid), ("NULL output", true, false, invalid),
                                                            ("not installed", true, true, notInitialized)] {
                let recorder = kept()
                XCTAssertEqual(add.call(withCallback, recorder.userData, recordEventRelease, withOut ? recorder.outListener : nil), expected,
                               "\(add.name) \(name)")
                if withOut {
                    XCTAssertNil(recorder.outListener.pointee, "\(add.name) \(name)")
                }
                XCTAssertEqual(recorder.releases, [true], "\(add.name) \(name)")
                runMainQueue()
                XCTAssertEqual(recorder.releases, [true], "\(add.name) \(name)")
            }
        }
    }

    func testARejectionOffTheMainThreadReleasesOnThatThread() {
        for add in adds {
            let recorder = kept()
            XCTAssertEqual(onAnotherThread { add.call(true, recorder.userData, recordEventRelease, recorder.outListener) }, notInitialized, add.name)
            XCTAssertEqual(recorder.releases, [false], add.name)
            XCTAssertNil(recorder.outListener.pointee, add.name)
        }
        runMainQueue()
    }

    func testTheLaunchResponseRejectsAtTheEntry() {
        let first = keptClipboardRecorder()
        XCTAssertEqual(ntk_notification_get_launch_response_async(nil, first.userData, recordRelease), invalid)
        let second = keptClipboardRecorder()
        XCTAssertEqual(ntk_notification_get_launch_response_async(recordHandle, second.userData, recordRelease), notInitialized)
        for recorder in [first, second] {
            XCTAssertEqual(recorder.releases, [true])
            runMainQueue()
            XCTAssertEqual(recorder.calls, ["release"])
        }
        XCTAssertEqual(ntk_last_system_code(), 0)
    }

    func testRemovingNullDoesNothing() {
        ntk_notification_listener_remove(nil)
        runMainQueue()
    }

    // MARK: - Delivered

    func testAnInteractionReachesEveryRegistrationWithAHandleOfItsOwn() {
        installFake()
        let first = add()
        let second = add()
        runMainQueue()
        NotificationReceiver.receive(event())
        XCTAssertEqual(first.interactions, [bodyTap])
        XCTAssertEqual(second.interactions, [bodyTap])
        // Each callback frees its handle before the next reads its own: one shared handle would be read after free
        // (ASan) or freed twice.
        ntk_notification_listener_remove(first.outListener.pointee)
        runMainQueue()
        XCTAssertEqual(first.releases, [true])
        NotificationReceiver.receive(event("n2"))
        XCTAssertEqual(first.interactions.count, 1, "nothing after the removal")
        XCTAssertEqual(second.interactions.map(\.notificationId), ["n1", "n2"])
        ntk_notification_listener_remove(second.outListener.pointee)
        runMainQueue()
        XCTAssertEqual(second.releases, [true])
    }

    /// AP-21: with no registration, up to 32 wait (the oldest go), and the next registration gets them inside
    /// its insertion, in order.
    func testWhatComesWithNoRegistrationWaitsForTheNext() {
        installFake()
        for index in 0..<33 {
            NotificationReceiver.receive(event("n\(index)"))
        }
        let late = add()
        XCTAssertEqual(late.interactions, [], "nothing inside the call")
        runMainQueue()
        XCTAssertEqual(late.interactions.map(\.notificationId), (1..<33).map { "n\($0)" })
        ntk_notification_listener_remove(late.outListener.pointee)
        runMainQueue()
    }

    /// AP-21: the only registration removed and a new one added inside the callback of a held event; the rest
    /// reaches the new one.
    func testReplacingTheRegistrationInsideAHeldEventsCallback() {
        installFake()
        for index in 0..<3 {
            NotificationReceiver.receive(event("n\(index)"))
        }
        let first = add()
        let next = kept()
        next.outListener.pointee = nil
        first.onInteraction = { [unowned first, unowned next] in
            guard first.interactions.count == 1 else { return }
            ntk_notification_listener_remove(first.outListener.pointee)
            _ = ntk_notification_add_interaction_listener(recordInteraction, next.userData, recordEventRelease, next.outListener)
        }
        runMainQueue()
        runMainQueue()
        XCTAssertEqual(first.interactions.map(\.notificationId), ["n0"])
        XCTAssertEqual(next.interactions.map(\.notificationId), ["n1", "n2"])
        ntk_notification_listener_remove(next.outListener.pointee)
        runMainQueue()
    }

    /// The library's listener is added once per kind, inside the first insertion, and never removed (AP-21).
    func testTheLibrarysListenerIsAddedOnce() {
        installFake()
        let one = add()
        let two = addSettings()
        runMainQueue()
        XCTAssertEqual(Self.interactionSubscriptions, 1)
        XCTAssertEqual(Self.settingsSubscriptions, 1)
        ntk_notification_listener_remove(one.outListener.pointee)
        ntk_notification_listener_remove(two.outListener.pointee)
        runMainQueue()
    }

    /// Settings requests wait for the next registration too (part 2, 5.4).
    func testASettingsRequestWithNoRegistrationWaitsForTheNext() {
        installFake()
        NotificationReceiver.receive(NotificationSettingsRequest(notificationIdentifier: "early"))
        NotificationReceiver.receive(NotificationSettingsRequest(notificationIdentifier: nil))
        let late = addSettings()
        XCTAssertEqual(late.settingsRequests, [], "nothing inside the call")
        runMainQueue()
        XCTAssertEqual(late.settingsRequests, ["early", nil])
        ntk_notification_listener_remove(late.outListener.pointee)
        runMainQueue()
    }

    func testASettingsRequestWithAndWithoutANotification() {
        installFake()
        let recorder = addSettings()
        runMainQueue()
        NotificationReceiver.receive(NotificationSettingsRequest(notificationIdentifier: "n1"))
        NotificationReceiver.receive(NotificationSettingsRequest(notificationIdentifier: nil))
        XCTAssertEqual(recorder.settingsRequests, ["n1", nil])
        ntk_notification_listener_remove(recorder.outListener.pointee)
        runMainQueue()
    }

    // MARK: - The values (part 2, 6.3, "イベントの値")

    func testTheFourKinds() {
        let rows: [(String, String?, Int32)] = [
            (UNNotificationDefaultActionIdentifier, nil, 0), ("open", nil, 1), (UNNotificationDismissActionIdentifier, nil, 2),
            ("reply", "hi", 3), (UNNotificationDefaultActionIdentifier, "", 3),
        ]
        for (action, text, kind) in rows {
            XCTAssertEqual(NotificationMapping.kind(actionIdentifier: action, userText: text), kind, "\(action) \(String(describing: text))")
        }
    }

    func testAnInteractionThroughC() {
        installFake()
        let recorder = add()
        runMainQueue()
        NotificationReceiver.receive(event("n9", action: "reply", category: "cat", text: "",
                                           userInfo: ["k": .integer(1), "nested": .array([.bool(true), .string("s")])], launch: true))
        XCTAssertEqual(recorder.interactions.first?.kind, 3)
        XCTAssertEqual(recorder.interactions.first?.notificationId, "n9")
        XCTAssertEqual(recorder.interactions.first?.actionId, "reply")
        XCTAssertEqual(recorder.interactions.first?.categoryId, "cat")
        XCTAssertEqual(recorder.interactions.first?.userText, "", "an empty reply is not NULL")
        XCTAssertEqual(recorder.interactions.first?.isLaunch, 1)
        let json = recorder.interactions.first?.userInfoJson ?? ""
        let object = try? JSONSerialization.jsonObject(with: Data(json.utf8)) as? [String: Any]
        XCTAssertEqual(object?["k"] as? Int, 1)
        XCTAssertEqual((object?["nested"] as? [Any])?.count, 2)
        ntk_notification_listener_remove(recorder.outListener.pointee)
        runMainQueue()
    }

    func testTheReadersOfNothing() {
        let other = Handle.makeString("another type")
        defer { ntk_string_free(other) }
        for handle in [nil, other] {
            XCTAssertEqual(ntk_notification_interaction_kind(handle), -1)
            var size = 9
            XCTAssertNil(ntk_notification_interaction_notification_id(handle, &size))
            XCTAssertEqual(size, 0)
            XCTAssertNil(ntk_notification_interaction_action_id(handle, nil))
            XCTAssertNil(ntk_notification_interaction_category_id(handle, nil))
            XCTAssertNil(ntk_notification_interaction_user_text(handle, nil))
            XCTAssertNil(ntk_notification_interaction_user_info_json(handle, nil))
            XCTAssertEqual(ntk_notification_interaction_is_launch(handle), 0)
            size = 9
            XCTAssertNil(ntk_notification_settings_request_notification_id(handle, &size))
            XCTAssertEqual(size, 0)
        }
        ntk_notification_interaction_free(nil)
        ntk_notification_settings_request_free(nil)
    }

    // MARK: - The launch response (P2-19)

    private func launchCompletion(file: StaticString = #filePath, line: UInt = #line) -> (Int32, InteractionSeen?) {
        let recorder = keptClipboardRecorder()
        XCTAssertEqual(ntk_notification_get_launch_response_async(recordHandle, recorder.userData, recordRelease), none, file: file, line: line)
        recorder.markReturned()
        let completion = finished(recorder, file: file, line: line)
        XCTAssertEqual(completion?.afterReturn, true, file: file, line: line)
        let value = completion?.handle.map { seen($0) }
        ntk_notification_interaction_free(completion?.handle)
        return (completion?.error ?? -99, value)
    }

    func testNoLaunchResponseIsNull() {
        installFake()
        let (error, value) = launchCompletion()
        XCTAssertEqual(error, none)
        XCTAssertNil(value)
    }

    func testALaunchResponse() {
        installFake(launch: event("cold", launch: true))
        let (error, value) = launchCompletion()
        XCTAssertEqual(error, none)
        XCTAssertEqual(value?.notificationId, "cold")
        XCTAssertEqual(value?.kind, 0)
        XCTAssertEqual(value?.isLaunch, 1)
    }

    func testALaunchResponseFailure() {
        installFake(launchFailure: NotificationError.delegateNotInstalled)
        let (error, value) = launchCompletion()
        XCTAssertEqual(error, notInitialized)
        XCTAssertNil(value)
    }

    /// P2-19: "none for now" can become a response before the app is first active; once there, it stays.
    func testTheLaunchResponseCanAppearLaterAndThenStays() {
        let responses = LaunchResponses([nil, event("late", launch: true)])
        installFake(launches: responses)
        XCTAssertNil(launchCompletion().1)
        XCTAssertEqual(launchCompletion().1?.notificationId, "late")
        XCTAssertEqual(launchCompletion().1?.notificationId, "late")
        XCTAssertEqual(responses.calls, 3)
    }

    /// A handle of one event type read as the other reads as nothing.
    func testTheEventHandlesAreNotTakenForEachOther() {
        let interaction = NotificationHandles.makeInteraction(NotificationMapping.interaction(of: event()))
        let request = NotificationHandles.makeSettingsRequest("n1")
        defer {
            ntk_notification_interaction_free(interaction)
            ntk_notification_settings_request_free(request)
        }
        XCTAssertEqual(text(ntk_notification_settings_request_notification_id(request, nil)), "n1")
        XCTAssertNil(ntk_notification_settings_request_notification_id(interaction, nil))
        XCTAssertEqual(ntk_notification_interaction_kind(interaction), 0)
        XCTAssertEqual(ntk_notification_interaction_kind(request), -1)
        XCTAssertNil(ntk_notification_interaction_notification_id(request, nil))
    }
}
