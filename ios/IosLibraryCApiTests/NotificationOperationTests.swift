//
//  NotificationOperationTests.swift
//  IosLibraryCApiTests
//

import Foundation
import UserNotifications
import XCTest
@testable import IosLibrary
@testable import IosLibraryCApi

/// The operations of Notification.h (OP-26 to OP-41) through C, without the notification center. These tests also
/// run on the private device under ASan (part 2, 12.2), so **nothing here reaches `UNUserNotificationCenter`**:
/// a call is either rejected at its entry, before anything is registered, or it is `show`, `update` or `schedule`
/// with the receiver's calls replaced (12.1, "権限の事前の確かめ"). The other completions are driven through the
/// receiver's `finish` functions with a registration made here. What needs the center is in the UI tests.
final class NotificationOperationTests: ClipboardTestCase {
    private let none: Int32 = 0
    private let invalid: Int32 = 1
    private let notSupported: Int32 = 3
    private let unknown: Int32 = 4
    private let permissionDenied: Int32 = 10
    private var builders: [OpaquePointer] = []
    /// Every recorder handed to C, for as long as this test object lives (XCTest keeps it to the end of the run):
    /// a completion that came late, after `finished` timed out or after a regression accepted a call, still
    /// writes to a live object.
    private var recorders: [ClipboardRecorder] = []

    private func kept() -> ClipboardRecorder {
        let recorder = ClipboardRecorder()
        recorders.append(recorder)
        return recorder
    }

    /// `completion(of:)` of ClipboardTestCase with a kept recorder.
    private func completed(file: StaticString = #filePath, line: UInt = #line, _ call: (ClipboardRecorder) -> Int32) -> ClipboardRecorder.Completion? {
        let recorder = kept()
        XCTAssertEqual(call(recorder), none, "rejected at the entry", file: file, line: line)
        recorder.markReturned()
        XCTAssertEqual(recorder.calls, [], "something ran inside the call", file: file, line: line)
        let result = finished(recorder, file: file, line: line)
        XCTAssertEqual(result?.afterReturn, true, file: file, line: line)
        return result
    }

    /// Closed by default: a call that reaches `show`, `update` or `schedule` without a test's `fake()` fails the
    /// test, and its pre-check reads `denied`, so that nothing reaches the notification center.
    private static let failing = NotificationReceiver.Adding(
        authorizationStatus: {
            XCTFail("a call reached the pre-check without a fake")
            return .denied
        },
        show: { _, _ in XCTFail("show reached the library") },
        update: { _, _, _ in XCTFail("update reached the library") },
        schedule: { _, _, _ in XCTFail("schedule reached the library") })

    override func setUpWithError() throws {
        try super.setUpWithError()
        NotificationReceiver.adding = Self.failing
        MainActor.assumeIsolated { NotificationReceiver.operations = FailClosed.operations }
    }

    override func tearDown() async throws {
        NotificationReceiver.adding = .manager
        builders.forEach { ntk_notification_content_free($0) }
        builders = []
        try await super.tearDown()
    }

    private func builder(id: String = "n1", title: String = "Title", file: StaticString = #filePath, line: UInt = #line) -> OpaquePointer? {
        var out: OpaquePointer?
        XCTAssertEqual(ntk_notification_content_create(c(id), c(title), &out), none, file: file, line: line)
        if let out { builders.append(out) }
        return out
    }

    private func sized<Value>(_ value: Value, _ set: (inout Value) -> Void = { _ in }) -> Value {
        var result = value
        withUnsafeMutableBytes(of: &result) { $0.storeBytes(of: UInt32(MemoryLayout<Value>.size), as: UInt32.self) }
        set(&result)
        return result
    }

    private func interval(_ seconds: Double, repeats: Bool = false) -> ntk_notification_trigger {
        sized(ntk_notification_trigger()) {
            $0.kind = Int32(NTK_NOTIFICATION_TRIGGER_TIME_INTERVAL)
            $0.interval_seconds = seconds
            $0.repeats = repeats ? 1 : 0
        }
    }

    // MARK: - The replaced calls of show, update and schedule

    /// What the receiver's calls saw. The status is what the pre-check reads.
    @MainActor
    private final class FakeCenter {
        var status: NotificationAuthorizationStatus = .authorized
        var failure: (any Error)?
        var statusReads = 0
        var calls: [String] = []
        var contents: [NotificationContentValue] = []

        private func record(_ call: String, _ value: NotificationContentValue) throws {
            calls.append(call)
            contents.append(value)
            if let failure { throw failure }
        }

        var adding: NotificationReceiver.Adding {
            NotificationReceiver.Adding(
                authorizationStatus: { [self] in
                    statusReads += 1
                    return status
                },
                show: { [self] value, trigger in try record("show \(Self.describe(trigger))", value) },
                update: { [self] identifier, value, trigger in try record("update \(identifier) \(Self.describe(trigger))", value) },
                schedule: { [self] identifier, value, trigger in try record("schedule \(identifier) \(Self.describe(trigger))", value) })
        }

        static func describe(_ trigger: NotificationTrigger?) -> String {
            switch trigger {
            case .none: return "now"
            case .timeInterval(let seconds, let repeats): return "interval(\(seconds), \(repeats))"
            case .some: return "other"
            }
        }
    }

    private func fake(_ status: NotificationAuthorizationStatus = .authorized, failure: (any Error)? = nil) -> FakeCenter {
        let center = FakeCenter()
        center.status = status
        center.failure = failure
        NotificationReceiver.adding = center.adding
        return center
    }

    private struct Add: @unchecked Sendable {
        let name: String
        let expected: String
        let call: (_ content: OpaquePointer?, _ userData: UnsafeMutableRawPointer?) -> Int32
    }

    /// The three operations with a valid input: a show now and in 30 seconds, an update of "u1" in 30 seconds, a
    /// schedule of "s1" in 60 seconds, repeating.
    private func adds() -> [Add] {
        let later = array([interval(30)])
        let repeating = array([interval(60, repeats: true)])
        return [
            Add(name: "show", expected: "show now") { ntk_notification_show_async($0, nil, recordDone, $1, recordRelease) },
            Add(name: "show later", expected: "show interval(30.0, false)") { ntk_notification_show_async($0, later, recordDone, $1, recordRelease) },
            Add(name: "update", expected: "update u1 interval(30.0, false)") {
                ntk_notification_update_async(self.c("u1"), $0, later, recordDone, $1, recordRelease)
            },
            Add(name: "schedule", expected: "schedule s1 interval(60.0, true)") {
                ntk_notification_schedule_async(self.c("s1"), $0, repeating, recordDone, $1, recordRelease)
            },
        ]
    }

    func testThePreCheckOfEveryStatus() {
        let statuses: [(NotificationAuthorizationStatus, Bool)] = [
            (.notDetermined, false), (.denied, false), (.authorized, true), (.provisional, true), (.ephemeral, true), (.unknown, false),
        ]
        for (status, allowed) in statuses {
            for add in adds() {
                let center = fake(status)
                let content = builder()
                let result = completed { add.call(content, $0.userData) }
                XCTAssertEqual(result?.error, allowed ? none : permissionDenied, "\(add.name) \(status)")
                XCTAssertEqual(center.statusReads, 1, "\(add.name) \(status)")
                XCTAssertEqual(center.calls, allowed ? [add.expected] : [], "\(add.name) \(status): what reached the library")
            }
        }
    }

    /// M2: without permission the previous request could not be made, so that `update` does not remove it is seen here.
    func testAnUpdateWithoutPermissionDoesNotCallTheLibrary() {
        let center = fake(.denied)
        let content = builder()
        XCTAssertEqual(completed { ntk_notification_update_async(c("u1"), content, nil, recordDone, $0.userData, recordRelease) }?.error,
                       permissionDenied)
        XCTAssertEqual(center.calls, [])
    }

    func testTheCopyOfTheContentIsTakenAtTheCall() {
        let center = fake()
        let content = builder(id: "before", title: "Before")
        let recorder = kept()
        XCTAssertEqual(ntk_notification_show_async(content, nil, recordDone, recorder.userData, recordRelease), none)
        XCTAssertEqual(ntk_notification_content_set_body(content, c("After")), none)
        ntk_notification_content_free(content)
        builders.removeAll { $0 == content }
        XCTAssertEqual(finished(recorder)?.error, none)
        XCTAssertEqual(center.contents.map(\.id), ["before"])
        XCTAssertEqual(center.contents.first?.title, "Before")
        XCTAssertNil(center.contents.first?.body)
    }

    func testWhatTheLibraryThrowsReachesTheCallback() {
        let detail = FailureDetail(domain: "d", code: 1)
        let failures: [(any Error, Int32)] = [
            (NotificationError.attachmentLoadFailed(identifier: "a", detail: detail), 17), (NotificationError.addRequestFailed(detail), 18),
            (NotificationError.invalidTrigger, invalid), (NotificationError.permissionDenied, unknown), (CocoaError(.fileNoSuchFile), unknown),
        ]
        for (failure, value) in failures {
            for add in adds() {
                let center = fake(failure: failure)
                let content = builder()
                XCTAssertEqual(completed { add.call(content, $0.userData) }?.error, value, "\(add.name) \(failure)")
                XCTAssertEqual(center.calls, [add.expected], "\(add.name) \(failure)")
            }
        }
    }

    func testAnAcceptedAddOffTheMainThreadDoesNotWaitForIt() {
        let center = fake()
        let content = builder()
        nonisolated(unsafe) let handle = content
        let recorder = kept()
        XCTAssertEqual(onAnotherThread { ntk_notification_show_async(handle, nil, recordDone, recorder.userData, recordRelease) }, none)
        XCTAssertEqual(recorder.calls, [])
        XCTAssertEqual(finished(recorder)?.error, none)
        XCTAssertEqual(center.calls, ["show now"])
    }

    // MARK: - Rejected at the entry

    /// The call returns `expected` with the release on this thread before it returns, and nothing else ever comes.
    private func assertRejected(_ name: String, expected: Int32 = 1, file: StaticString = #filePath, line: UInt = #line,
                                _ call: (UnsafeMutableRawPointer) -> Int32) {
        let recorder = kept()
        XCTAssertEqual(call(recorder.userData), expected, name, file: file, line: line)
        XCTAssertEqual(recorder.releases, [true], name, file: file, line: line)
        runMainQueue(file: file, line: line)
        XCTAssertEqual(recorder.calls, ["release"], name, file: file, line: line)
    }

    private struct Rejection: @unchecked Sendable {
        let name: String
        let call: (_ userData: UnsafeMutableRawPointer?, _ release: ntk_release_fn?) -> Int32
    }

    /// Every operation with a NULL callback and an input that would be valid (P2-28).
    private func nullCallbacks() -> [Rejection] {
        let content = builder()
        let identifier = c("x")
        let trigger = array([interval(60)])
        let category = array([sized(ntk_notification_category()) { $0.identifier = self.c("cat") }])
        return [
            Rejection(name: "show") { ntk_notification_show_async(content, nil, nil, $0, $1) },
            Rejection(name: "update") { ntk_notification_update_async(identifier, content, nil, nil, $0, $1) },
            Rejection(name: "schedule") { ntk_notification_schedule_async(identifier, content, trigger, nil, $0, $1) },
            Rejection(name: "remove") { ntk_notification_remove_async(identifier, nil, $0, $1) },
            Rejection(name: "removeAll") { ntk_notification_remove_all_async(nil, $0, $1) },
            Rejection(name: "cancelScheduled") { ntk_notification_cancel_scheduled_async(identifier, nil, $0, $1) },
            Rejection(name: "cancelAllScheduled") { ntk_notification_cancel_all_scheduled_async(nil, $0, $1) },
            Rejection(name: "getScheduled") { ntk_notification_get_scheduled_async(nil, $0, $1) },
            Rejection(name: "getDelivered") { ntk_notification_get_delivered_async(nil, $0, $1) },
            Rejection(name: "requestPermission") { ntk_notification_request_permission_async(0, nil, $0, $1) },
            Rejection(name: "authorizationStatus") { ntk_notification_get_authorization_status_async(nil, $0, $1) },
            Rejection(name: "hasPermission") { ntk_notification_has_permission_async(nil, $0, $1) },
            Rejection(name: "openSettings") { ntk_notification_open_settings_async(nil, $0, $1) },
            Rejection(name: "setBadgeCount") { ntk_notification_set_badge_count_async(0, nil, $0, $1) },
            Rejection(name: "registerCategory") { ntk_notification_register_category_async(category, nil, $0, $1) },
            Rejection(name: "removeCategory") { ntk_notification_remove_category_async(identifier, nil, $0, $1) },
        ]
    }

    func testANullCallbackIsRejectedByEveryOperation() {
        let table = nullCallbacks()
        XCTAssertEqual(table.count, 16)
        for rejection in table {
            assertRejected(rejection.name) { rejection.call($0, recordRelease) }
        }
    }

    func testARejectionWithoutAReleaseIsFine() {
        for rejection in nullCallbacks() {
            XCTAssertEqual(rejection.call(nil, nil), invalid, rejection.name)
        }
    }

    func testARejectionOffTheMainThreadReleasesOnThatThreadAndDoesNotWait() {
        let table = nullCallbacks()
        for index in table.indices {
            let rejection = table[index]
            let recorder = kept()
            XCTAssertEqual(onAnotherThread { rejection.call(recorder.userData, recordRelease) }, invalid, rejection.name)
            XCTAssertEqual(recorder.releases, [false], rejection.name)
        }
    }

    func testTheSystemCodeAfterARejectionIsZero() {
        XCTAssertEqual(ntk_notification_show_async(nil, nil, recordDone, nil, nil), invalid)
        XCTAssertEqual(ntk_last_system_code(), 0)
    }

    func testTheContentIsRequired() {
        let otherHandle: OpaquePointer? = Handle.makeString("a handle of another type")
        defer { ntk_string_free(otherHandle) }
        for content in [nil, otherHandle] {
            let name = content == nil ? "NULL" : "another type"
            assertRejected("show \(name)") { ntk_notification_show_async(content, nil, recordDone, $0, recordRelease) }
            assertRejected("update \(name)") { ntk_notification_update_async(c("u"), content, nil, recordDone, $0, recordRelease) }
            assertRejected("schedule \(name)") {
                ntk_notification_schedule_async(c("s"), content, array([interval(60)]), recordDone, $0, recordRelease)
            }
        }
    }

    func testTheIdentifiersOfUpdateAndSchedule() {
        let content = builder()
        let trigger = array([interval(60)])
        var identifiers: [(String, UnsafePointer<CChar>?)] = [("NULL", nil), ("empty", c(""))]
        identifiers += invalidUTF8.map { ("\($0)", raw($0)) }
        for (name, identifier) in identifiers {
            assertRejected("update \(name)") { ntk_notification_update_async(identifier, content, nil, recordDone, $0, recordRelease) }
            assertRejected("schedule \(name)") { ntk_notification_schedule_async(identifier, content, trigger, recordDone, $0, recordRelease) }
        }
    }

    /// "" is accepted by the removals (it removes nothing): only NULL and bytes that are not UTF-8 are rejected here.
    func testTheIdentifiersOfTheRemovals() {
        var identifiers: [(String, UnsafePointer<CChar>?)] = [("NULL", nil)]
        identifiers += invalidUTF8.map { ("\($0)", raw($0)) }
        for (name, identifier) in identifiers {
            assertRejected("remove \(name)") { ntk_notification_remove_async(identifier, recordDone, $0, recordRelease) }
            assertRejected("cancelScheduled \(name)") { ntk_notification_cancel_scheduled_async(identifier, recordDone, $0, recordRelease) }
            assertRejected("removeCategory \(name)") { ntk_notification_remove_category_async(identifier, recordDone, $0, recordRelease) }
        }
    }

    /// AP-19 and 12.1, "trigger": a trigger out of range is the return value, with no completion, and the process
    /// does not stop (M5, M8). The pre-check is never reached.
    func testATriggerOutOfRangeIsTheReturnValue() {
        let center = fake()
        let content = builder()
        var triggers: [(String, ntk_notification_trigger)] = [
            ("0", interval(0)), ("-1", interval(-1)), ("59.9 repeating", interval(59.9, repeats: true)), ("30 repeating", interval(30, repeats: true)),
            ("NaN", interval(.nan)), ("-inf", interval(-.infinity)), ("+inf", interval(.infinity)),
            ("kind 3", sized(ntk_notification_trigger()) { $0.kind = 3 }),
            ("calendar 0", sized(ntk_notification_trigger()) { $0.kind = Int32(NTK_NOTIFICATION_TRIGGER_CALENDAR) }),
            ("calendar unknown bit", sized(ntk_notification_trigger()) {
                $0.kind = Int32(NTK_NOTIFICATION_TRIGGER_CALENDAR)
                $0.calendar_fields = UInt32(NTK_NOTIFICATION_CALENDAR_HOUR) | (1 << 6)
            }),
        ]
        for (name, latitude, longitude, radius) in [("latitude", 90.5, 0.0, 10.0), ("longitude", 0.0, -180.5, 10.0), ("radius", 0.0, 0.0, 0.0)] {
            triggers.append(("location \(name)", sized(ntk_notification_trigger()) {
                $0.kind = Int32(NTK_NOTIFICATION_TRIGGER_LOCATION)
                $0.location_identifier = self.c("place")
                $0.latitude = latitude
                $0.longitude = longitude
                $0.radius = radius
            }))
        }
        for (name, trigger) in triggers {
            let pointer = array([trigger])
            assertRejected("show \(name)") { ntk_notification_show_async(content, pointer, recordDone, $0, recordRelease) }
            assertRejected("update \(name)") { ntk_notification_update_async(c("u"), content, pointer, recordDone, $0, recordRelease) }
            assertRejected("schedule \(name)") { ntk_notification_schedule_async(c("s"), content, pointer, recordDone, $0, recordRelease) }
        }
        XCTAssertEqual(center.statusReads, 0)
        XCTAssertEqual(center.calls, [])
    }

    func testScheduleNeedsATrigger() {
        let content = builder()
        assertRejected("schedule NULL") { ntk_notification_schedule_async(c("s"), content, nil, recordDone, $0, recordRelease) }
    }

    func testTheStructRulesOfTheTriggerThroughC() {
        let content = builder()
        var small = interval(60)
        small.struct_size = 8
        var reserved = interval(60)
        reserved.reserved1 = 1
        assertRejected("small") { ntk_notification_show_async(content, array([small]), recordDone, $0, recordRelease) }
        assertRejected("reserved1") { ntk_notification_show_async(content, array([reserved]), recordDone, $0, recordRelease) }
        // A longer struct whose unknown tail is not zero.
        let size = MemoryLayout<ntk_notification_trigger>.size
        let longer = UnsafeMutableRawPointer.allocate(byteCount: size + 8, alignment: 8)
        defer { longer.deallocate() }
        longer.initializeMemory(as: UInt8.self, repeating: 0, count: size + 8)
        var base = interval(60)
        base.struct_size = UInt32(size + 8)
        longer.storeBytes(of: base, as: ntk_notification_trigger.self)
        longer.storeBytes(of: UInt8(1), toByteOffset: size + 7, as: UInt8.self)
        let pointer = UnsafePointer(longer.assumingMemoryBound(to: ntk_notification_trigger.self))
        assertRejected("unknown tail", expected: notSupported) { ntk_notification_show_async(content, pointer, recordDone, $0, recordRelease) }
    }

    /// 12.1, "category" through C: what the mapping rejects is the return value (the mapping itself is in
    /// NotificationMappingTests).
    func testACategoryIsCheckedAtTheEntry() {
        let action = sized(ntk_notification_action()) {
            $0.identifier = self.c("a")
            $0.title = self.c("A")
            $0.options = 1 << 3
        }
        let categories: [(String, ntk_notification_category)] = [
            ("no identifier", sized(ntk_notification_category())),
            ("empty identifier", sized(ntk_notification_category()) { $0.identifier = self.c("") }),
            ("unknown category bit", sized(ntk_notification_category()) {
                $0.identifier = self.c("c")
                $0.options = 1 << 4
            }),
            ("unknown action bit", sized(ntk_notification_category()) {
                $0.identifier = self.c("c")
                $0.actions = self.array([action])
                $0.action_count = 1
            }),
            ("reserved1", sized(ntk_notification_category()) {
                $0.identifier = self.c("c")
                $0.reserved1 = 1
            }),
        ]
        for (name, category) in categories {
            let pointer = array([category])
            assertRejected(name) { ntk_notification_register_category_async(pointer, recordDone, $0, recordRelease) }
        }
        assertRejected("NULL") { ntk_notification_register_category_async(nil, recordDone, $0, recordRelease) }
    }

    /// P2-27: an unknown bit, `provisional` (1 << 6) among them, is rejected.
    func testUnknownPermissionBitsAreRejected() {
        for bit in [UInt32(1) << 6, 1 << 7, 1 << 8, 1 << 31] {
            assertRejected("bit \(bit)") { ntk_notification_request_permission_async(bit | 4, recordChanged, $0, recordRelease) }
        }
    }

    func testANegativeBadgeCountIsRejected() {
        for count in [Int32(-1), .min] {
            assertRejected("\(count)") { ntk_notification_set_badge_count_async(count, recordDone, $0, recordRelease) }
        }
    }

    // MARK: - The mappings

    func testThePermissionOptions() throws {
        XCTAssertEqual(try NotificationMapping.permissionOptions(0), [.alert, .sound, .badge], "0 is the default")
        let bits: [(Int, UNAuthorizationOptions)] = [
            (Int(NTK_NOTIFICATION_AUTH_BADGE), .badge), (Int(NTK_NOTIFICATION_AUTH_SOUND), .sound), (Int(NTK_NOTIFICATION_AUTH_ALERT), .alert),
            (Int(NTK_NOTIFICATION_AUTH_CAR_PLAY), .carPlay), (Int(NTK_NOTIFICATION_AUTH_CRITICAL_ALERT), .criticalAlert),
            (Int(NTK_NOTIFICATION_AUTH_PROVIDES_APP_SETTINGS), .providesAppNotificationSettings),
        ]
        for (bit, option) in bits {
            XCTAssertEqual(try NotificationMapping.permissionOptions(UInt32(bit)), option, "\(bit)")
        }
        XCTAssertEqual(try NotificationMapping.permissionOptions(0x3F),
                       [.badge, .sound, .alert, .carPlay, .criticalAlert, .providesAppNotificationSettings])
        XCTAssertEqual(try NotificationMapping.permissionOptions(UInt32(NTK_NOTIFICATION_AUTH_ALERT) | UInt32(NTK_NOTIFICATION_AUTH_PROVIDES_APP_SETTINGS)),
                       [.alert, .providesAppNotificationSettings], "no default is added to a set that is given")
        for bit in [UInt32(1) << 6, 1 << 7, 1 << 8] {
            do throws(EntryError) {
                XCTFail("accepted \(try NotificationMapping.permissionOptions(bit))")
            } catch {
                XCTAssertEqual(error, .invalidParameter)
            }
        }
    }

    func testTheStatuses() {
        let rows: [(NotificationAuthorizationStatus, Int32, Bool)] = [
            (.notDetermined, 0, false), (.denied, 1, false), (.authorized, 2, true), (.provisional, 3, true), (.ephemeral, 4, true), (.unknown, 5, false),
        ]
        for (status, value, allowed) in rows {
            XCTAssertEqual(NotificationMapping.status(of: status), value, "\(status)")
            XCTAssertEqual(NotificationMapping.allowsAdding(status), allowed, "\(status)")
        }
    }

    /// 11.2, every case written out (2a stops a case that is added or removed).
    func testEveryNotificationError() {
        let detail = FailureDetail(domain: "d", code: 2)
        let rows: [(NotificationError, Int32)] = [
            (.permissionDenied, 4), (.attachmentLoadFailed(identifier: "a", detail: detail), 17), (.addRequestFailed(detail), 18),
            (.setBadgeCountFailed(detail), 19), (.authorizationFailed(detail), 20), (.reservedUserInfoKey, 1), (.invalidUserInfo, 1),
            (.invalidTrigger, 1), (.notForeground, 8), (.openSettingsFailed, 15), (.delegateNotInstalled, 2),
        ]
        for (failure, value) in rows {
            XCTAssertEqual(NotificationMapping.error(for: failure), value, "\(failure)")
            XCTAssertEqual(NotificationMapping.error(for: failure as any Error), value, "\(failure) as any Error")
        }
        XCTAssertEqual(NotificationMapping.error(for: CocoaError(.fileNoSuchFile) as any Error), unknown)
    }

    func testMillis() {
        XCTAssertEqual(NotificationMapping.millis(of: Date(timeIntervalSince1970: 1.2345)), 1234)
        XCTAssertEqual(NotificationMapping.millis(of: Date(timeIntervalSince1970: -0.0005)), -1)
        XCTAssertEqual(NotificationMapping.millis(of: Date(timeIntervalSince1970: 1e300)), 0)
    }

    // MARK: - The completions, from the receiver (no center)

    private func registration<Callback>(_ callback: Callback, _ recorder: ClipboardRecorder) -> Registration<Callback> {
        Registration<Callback>(callback: callback, userData: recorder.userData, release: recordRelease, cancellable: nil, canceled: nil, onRemoval: nil)
    }

    private func once(_ recorder: ClipboardRecorder, file: StaticString = #filePath, line: UInt = #line) -> ClipboardRecorder.Completion? {
        XCTAssertEqual(recorder.calls, ["completion", "release"], file: file, line: line)
        XCTAssertEqual(recorder.completions.first?.systemCode, 0, file: file, line: line)
        return recorder.completions.first
    }

    func testThePermissionCompletions() {
        let rows: [(Result<Bool, NotificationError>, Int32, Int32)] = [
            (.success(true), none, 1), (.success(false), none, 0), (.failure(.notForeground), 8, 0),
            (.failure(.authorizationFailed(FailureDetail(domain: "d", code: 1))), 20, 0),
        ]
        for (result, error, granted) in rows {
            let recorder = kept()
            NotificationReceiver.finishPermission(registration(recordChanged as ntk_notification_permission_fn, recorder), result)
            let completion = once(recorder)
            XCTAssertEqual(completion?.error, error, "\(result)")
            XCTAssertEqual(completion?.value, granted, "\(result)")
        }
    }

    func testTheSettingsCompletions() {
        let rows: [(Result<Void, NotificationError>, Int32)] = [(.success(()), none), (.failure(.notForeground), 8), (.failure(.openSettingsFailed), 15)]
        for (result, error) in rows {
            let recorder = kept()
            NotificationReceiver.finishSettings(registration(recordDone as ntk_notification_done_fn, recorder), result)
            XCTAssertEqual(once(recorder)?.error, error, "\(result)")
        }
    }

    private func list(_ entries: [NotificationListEntry]) -> OpaquePointer? {
        let recorder = kept()
        NotificationReceiver.finishList(registration(recordHandle as ntk_notification_list_fn, recorder), entries)
        let completion = once(recorder)
        XCTAssertEqual(completion?.error, none)
        return completion?.handle
    }

    func testAListThroughC() {
        let scheduled = NotificationMapping.entries(of: [
            ScheduledNotification(identifier: "s1", title: "T", subtitle: nil, body: "B", categoryIdentifier: "", userInfo: ["k": 1]),
        ])
        let delivered = NotificationMapping.entries(of: [
            ActiveNotification(identifier: "d1", title: "", subtitle: "S", body: nil, categoryIdentifier: "cat",
                               date: Date(timeIntervalSince1970: 1_700_000_000.25), userInfo: [:]),
            ActiveNotification(identifier: "d2", title: "\u{1F600}", subtitle: nil, body: nil, categoryIdentifier: "",
                               date: Date(timeIntervalSince1970: 0), userInfo: [:]),
        ])
        let handle = list(scheduled + delivered)
        defer { ntk_notification_list_free(handle) }
        XCTAssertEqual(ntk_notification_list_count(handle), 3)
        var size = 99
        XCTAssertEqual(text(ntk_notification_list_identifier_at(handle, 0, &size)), "s1")
        XCTAssertEqual(size, 2)
        XCTAssertEqual(text(ntk_notification_list_title_at(handle, 0, nil)), "T")
        XCTAssertNil(ntk_notification_list_subtitle_at(handle, 0, &size), "no subtitle is NULL")
        XCTAssertEqual(size, 0)
        XCTAssertEqual(text(ntk_notification_list_body_at(handle, 0, nil)), "B")
        XCTAssertEqual(text(ntk_notification_list_category_at(handle, 0, &size)), "")
        XCTAssertEqual(size, 0)
        XCTAssertEqual(ntk_notification_list_date_millis_at(handle, 0), 0, "a scheduled one has no date")
        XCTAssertEqual(text(ntk_notification_list_identifier_at(handle, 1, nil)), "d1")
        XCTAssertEqual(text(ntk_notification_list_title_at(handle, 1, &size)), "", "an empty title is not NULL")
        XCTAssertEqual(size, 0)
        XCTAssertEqual(text(ntk_notification_list_subtitle_at(handle, 1, nil)), "S")
        XCTAssertNil(ntk_notification_list_body_at(handle, 1, nil))
        XCTAssertEqual(text(ntk_notification_list_category_at(handle, 1, nil)), "cat")
        XCTAssertEqual(ntk_notification_list_date_millis_at(handle, 1), 1_700_000_000_250)
        XCTAssertEqual(text(ntk_notification_list_title_at(handle, 2, &size)), "\u{1F600}")
        XCTAssertEqual(size, 4)
        XCTAssertEqual(ntk_notification_list_date_millis_at(handle, 2), 0)
    }

    func testAnEmptyListIsNotNull() {
        let handle = list([])
        defer { ntk_notification_list_free(handle) }
        XCTAssertNotNil(handle)
        XCTAssertEqual(ntk_notification_list_count(handle), 0)
    }

    func testTheReadersOfNothing() {
        let handle = list(NotificationMapping.entries(of: [
            ScheduledNotification(identifier: "s1", title: "T", subtitle: "S", body: "B", categoryIdentifier: "c", userInfo: [:]),
        ]))
        defer { ntk_notification_list_free(handle) }
        let otherHandle: OpaquePointer? = Handle.makeString("a handle of another type")
        defer { ntk_string_free(otherHandle) }
        let tooFar = Int(bitPattern: UInt.max)
        for (name, list, index) in [("NULL", nil, 0), ("another type", otherHandle, 0), ("index 1", handle, 1), ("index SIZE_MAX", handle, tooFar)] {
            var size = 99
            XCTAssertNil(ntk_notification_list_identifier_at(list, index, &size), name)
            XCTAssertEqual(size, 0, name)
            size = 99
            XCTAssertNil(ntk_notification_list_title_at(list, index, &size), name)
            XCTAssertEqual(size, 0, name)
            XCTAssertNil(ntk_notification_list_subtitle_at(list, index, nil), name)
            XCTAssertNil(ntk_notification_list_body_at(list, index, nil), name)
            XCTAssertNil(ntk_notification_list_category_at(list, index, nil), name)
            XCTAssertEqual(ntk_notification_list_date_millis_at(list, index), 0, name)
        }
        XCTAssertEqual(ntk_notification_list_count(nil), 0)
        XCTAssertEqual(ntk_notification_list_count(otherHandle), 0)
        ntk_notification_list_free(nil)
    }

    // MARK: - Review fixes

    /// "" is accepted by the three removals and removes nothing (part 2, 6.3); NULL is not.
    func testAnEmptyRemovalIdentifierIsAccepted() throws {
        XCTAssertEqual(try NotificationReceiver.removalIdentifier(c("")), "")
        XCTAssertEqual(try NotificationReceiver.removalIdentifier(c("x")), "x")
        do throws(EntryError) {
            XCTFail("accepted NULL: \(try NotificationReceiver.removalIdentifier(nil))")
        } catch {
            XCTAssertEqual(error, .invalidParameter)
        }
    }

    func testTheStatusCompletions() {
        let rows: [(NotificationAuthorizationStatus, Int32)] = [
            (.notDetermined, 0), (.denied, 1), (.authorized, 2), (.provisional, 3), (.ephemeral, 4), (.unknown, 5),
        ]
        for (status, value) in rows {
            let recorder = kept()
            NotificationReceiver.finishStatus(registration(recordChanged as ntk_notification_status_fn, recorder), status)
            let completion = once(recorder)
            XCTAssertEqual(completion?.error, none, "\(status)")
            XCTAssertEqual(completion?.value, value, "\(status)")
        }
    }

    func testTheHasPermissionCompletions() {
        for granted in [true, false] {
            let recorder = kept()
            NotificationReceiver.finishHasPermission(registration(recordChanged as ntk_notification_permission_fn, recorder), granted)
            let completion = once(recorder)
            XCTAssertEqual(completion?.error, none)
            XCTAssertEqual(completion?.value, granted ? 1 : 0)
        }
    }

    /// 12.1: the pre-check's set is the library's internal one (`requestPermission` reports these as granted).
    func testThePreCheckIsTheLibrarysSet() {
        for status in [NotificationAuthorizationStatus.notDetermined, .denied, .authorized, .provisional, .ephemeral, .unknown] {
            XCTAssertEqual(NotificationMapping.allowsAdding(status), NotificationPresentationGate.grants(status), "\(status)")
        }
    }
}
