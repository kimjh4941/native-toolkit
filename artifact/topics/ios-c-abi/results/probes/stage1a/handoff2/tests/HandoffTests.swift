// Hand-off 2 probe: XCTest for ntk_notification_install and the notification events (part 1 1.4,
// 5.12). The host app does nothing in unit tests, so the first test sees a process without the proxy.
// Settings requests (openSettingsFor) are driven by calling the installed delegate directly, which is
// the path the system takes; taps are covered by the UI tests.
import Foundation
import IosLibraryCApi
import UserNotifications
import XCTest

final class EventRecorder: @unchecked Sendable {
    private static let keepAlive = NSMutableArray()   // user_data is unretained; late releases must find it
    private let lock = NSLock()
    private(set) var events: [String] = []
    private(set) var releases = 0
    private(set) var releaseOnMain = true
    private(set) var releaseThread: Thread?
    private(set) var eventsOnMain = true

    init() { objc_sync_enter(Self.keepAlive); Self.keepAlive.add(self); objc_sync_exit(Self.keepAlive) }

    var pointer: UnsafeMutableRawPointer { Unmanaged.passUnretained(self).toOpaque() }
    static func from(_ p: UnsafeMutableRawPointer?) -> EventRecorder { Unmanaged.fromOpaque(p!).takeUnretainedValue() }

    func add(_ event: String) { lock.withLock { events.append(event); eventsOnMain = eventsOnMain && Thread.isMainThread } }
    func onRelease() {
        lock.withLock { releases += 1; releaseOnMain = releaseOnMain && Thread.isMainThread; releaseThread = .current }
    }
}

private func take(_ handle: OpaquePointer?) -> String {
    guard let handle else { return "nil" }
    defer { ntk_string_free(handle) }
    return ntk_string_data(handle).map { String(cString: $0) } ?? "nil"
}

let recordEvent: ntk_probe_notification_event_fn = { ud, kind, identifier, action, text, launch in
    EventRecorder.from(ud).add("kind=\(kind) id=\(take(identifier)) action=\(take(action)) text=\(take(text)) launch=\(launch)")
}
let recordRelease: ntk_release_fn = { ud in EventRecorder.from(ud).onRelease() }

/// A previous delegate that records openSettingsFor and, when cyclic, forwards it synchronously to
/// the delegate it replaced.
final class RecordingDelegate: NSObject, UNUserNotificationCenterDelegate {
    var openSettingsCalls = 0
    var cyclic = false
    weak var previous: (any UNUserNotificationCenterDelegate)?

    func userNotificationCenter(_ center: UNUserNotificationCenter, openSettingsFor notification: UNNotification?) {
        openSettingsCalls += 1
        if cyclic { previous?.userNotificationCenter?(center, openSettingsFor: notification) }
    }
}

private let NOT_INITIALIZED: Int32 = 2, WRONG_THREAD: Int32 = 16, INVALID: Int32 = 1

final class HandoffNotificationTests: XCTestCase {
    private var center: UNUserNotificationCenter { .current() }
    private var delegateName: String { center.delegate.map { String(describing: type(of: $0)) } ?? "nil" }

    private func settle(_ seconds: TimeInterval = 0.3) { RunLoop.main.run(until: Date().addingTimeInterval(seconds)) }

    private func openSettings(_ times: Int = 1) {
        for _ in 0..<times { center.delegate?.userNotificationCenter?(center, openSettingsFor: nil) }
    }

    private func addListener(_ recorder: EventRecorder) -> OpaquePointer? {
        var listener: OpaquePointer?
        XCTAssertEqual(ntk_probe_notification_add_listener(recordEvent, recorder.pointer, recordRelease, &listener), 0)
        XCTAssertNotNil(listener)
        return listener
    }

    /// Runs first (alphabetical): nothing has installed the proxy in this process yet.
    func test01NotInitializedBeforeTheFirstInstall() {
        let recorder = EventRecorder()
        var listener: OpaquePointer? = OpaquePointer(bitPattern: 0x1)
        XCTAssertEqual(ntk_probe_notification_add_listener(recordEvent, recorder.pointer, recordRelease, &listener), NOT_INITIALIZED)
        XCTAssertNil(listener, "the handle output is NULL on failure")
        XCTAssertEqual(recorder.releases, 1, "rejected: release before returning")
        var identifier: OpaquePointer?, action: OpaquePointer?
        XCTAssertEqual(ntk_probe_notification_get_launch_response(&identifier, &action), NOT_INITIALIZED)
        XCTAssertEqual(ntk_probe_notification_add_listener(nil, nil, nil, &listener), INVALID, "argument checks come first")
    }

    func test02InstallOffTheMainThreadReturnsWrongThread() {
        let before = delegateName
        let done = expectation(description: "background")
        var codes: [Int32] = []
        var times: [Double] = []
        DispatchQueue.global().async {
            for _ in 0..<5 {
                let start = DispatchTime.now().uptimeNanoseconds
                codes.append(ntk_notification_install())
                times.append(Double(DispatchTime.now().uptimeNanoseconds - start) / 1_000_000)
            }
            done.fulfill()
        }
        wait(for: [done], timeout: 5)
        print("HANDOFF2: install off main -> \(codes), ms = \(times.map { String(format: "%.3f", $0) })")
        XCTAssertEqual(codes, Array(repeating: WRONG_THREAD, count: 5))
        XCTAssertEqual(delegateName, before, "nothing changes off main")

        XCTAssertEqual(ntk_notification_install(), 0)
        XCTAssertEqual(delegateName, "NotificationDelegateProxy", "set before returning")
        XCTAssertEqual(ntk_notification_install(), 0, "idempotent")
        XCTAssertEqual(delegateName, "NotificationDelegateProxy")
    }

    func test03ReplacedThenReinstalledForwardsToTheNewPrevious() {
        XCTAssertEqual(ntk_notification_install(), 0)
        let host = RecordingDelegate()
        center.delegate = host
        XCTAssertEqual(ntk_notification_install(), 0)
        XCTAssertEqual(delegateName, "NotificationDelegateProxy")
        let recorder = EventRecorder()
        let listener = addListener(recorder)
        settle()
        openSettings()
        settle()
        XCTAssertEqual(host.openSettingsCalls, 1, "openSettingsFor(nil) goes to the previous delegate that implements it")
        XCTAssertEqual(recorder.events, [], "and is not a library event")
        ntk_probe_notification_listener_remove(listener)
        settle()
        XCTAssertEqual(recorder.releases, 1)
        XCTAssertTrue(recorder.releaseOnMain)
        withExtendedLifetime(host) {}
    }

    /// P1-21: the previous delegate forwards back to the proxy synchronously; the proxy stops it and
    /// handles the request as unclaimed (one settings event, no recursion).
    func test04SynchronousCycleIsStopped() {
        XCTAssertEqual(ntk_notification_install(), 0)
        let host = RecordingDelegate()
        host.cyclic = true
        host.previous = center.delegate   // the proxy
        center.delegate = host
        XCTAssertEqual(ntk_notification_install(), 0)   // proxy -> host -> proxy
        let recorder = EventRecorder()
        let listener = addListener(recorder)
        settle()
        openSettings()
        settle()
        print("HANDOFF2: cycle -> host calls \(host.openSettingsCalls), events \(recorder.events)")
        XCTAssertEqual(host.openSettingsCalls, 1)
        XCTAssertEqual(recorder.events, ["kind=1 id=nil action=nil text=nil launch=0"])
        ntk_probe_notification_listener_remove(listener)
        center.delegate = nil
        XCTAssertEqual(ntk_notification_install(), 0)   // back to a proxy without a previous delegate
        settle()
        withExtendedLifetime(host) {}
    }

    /// 5.12.7: events before the first C listener stay in the hub; after a listener is removed they stay
    /// in the C receiver's book; both reach the next listener inside its registration, oldest first.
    func test05EventsAreKeptWhileNoListenerIsRegistered() {
        center.delegate = nil
        XCTAssertEqual(ntk_notification_install(), 0)
        let first = EventRecorder()
        let l1 = addListener(first)
        settle()
        openSettings()
        settle()
        XCTAssertEqual(first.events.count, 1)
        ntk_probe_notification_listener_remove(l1)   // from main: no event after this call
        openSettings(2)
        settle()
        XCTAssertEqual(first.events.count, 1, "removed on main: nothing more")
        XCTAssertEqual(first.releases, 1)

        let second = EventRecorder()
        let l2 = addListener(second)
        XCTAssertEqual(second.events.count, 0, "not inside the add function")
        settle()
        XCTAssertEqual(second.events.count, 2, "the two kept events arrive with the registration")
        XCTAssertTrue(second.eventsOnMain)
        ntk_probe_notification_listener_remove(l2)
        settle()
    }

    func test06AtMost32EventsAreKept() {
        center.delegate = nil
        XCTAssertEqual(ntk_notification_install(), 0)
        openSettings(40)
        settle()
        let recorder = EventRecorder()
        let listener = addListener(recorder)
        settle()
        print("HANDOFF2: 40 events without a listener -> next listener got \(recorder.events.count)")
        XCTAssertEqual(recorder.events.count, 32)
        ntk_probe_notification_listener_remove(listener)
        settle()
    }

    func test07RemoveFromAnotherThreadReleasesOnMainOnce() {
        center.delegate = nil
        XCTAssertEqual(ntk_notification_install(), 0)
        let recorder = EventRecorder()
        let listener = addListener(recorder)
        settle()
        let done = expectation(description: "background")
        let box = UncheckedHandle(listener)
        DispatchQueue.global().async {
            ntk_probe_notification_listener_remove(box.handle)
            done.fulfill()
        }
        wait(for: [done], timeout: 5)
        settle()
        XCTAssertEqual(recorder.releases, 1)
        XCTAssertTrue(recorder.releaseOnMain)
        // Leave the book empty for the next test.
        let drain = EventRecorder()
        let l = addListener(drain)
        settle()
        ntk_probe_notification_listener_remove(l)
        settle()
    }

    func test08ScheduleRejectsBadArguments() {
        let recorder = EventRecorder()
        let done: ntk_probe_notification_done_fn = { _, _, _, _ in }
        XCTAssertEqual(ntk_probe_notification_schedule_marked(1, "", "t", done, recorder.pointer, recordRelease), INVALID)
        XCTAssertEqual(ntk_probe_notification_schedule_marked(1, "id", nil, done, recorder.pointer, recordRelease), INVALID)
        XCTAssertEqual(ntk_probe_notification_schedule_marked(1, "id", "t", nil, recorder.pointer, recordRelease), INVALID)
        XCTAssertEqual(recorder.releases, 3)
    }
}

struct UncheckedHandle: @unchecked Sendable { let handle: OpaquePointer? ; init(_ handle: OpaquePointer?) { self.handle = handle } }
