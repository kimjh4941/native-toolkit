//
//  ThreadContractTests.swift
//  IosLibraryCApiTests
//

import Foundation
import UserNotifications
import XCTest
@testable import IosLibrary
@testable import IosLibraryCApi

/// The receivers' replaceable calls, closed: what reaches one without a test's fake fails the test and still ends,
/// so that nothing reaches the notification center or the share sheet (these tests also run on the private device
/// under ASan; part 2, 12.2).
enum FailClosed {
    static let adding = NotificationReceiver.Adding(
        authorizationStatus: {
            XCTFail("a call reached the pre-check without a fake")
            return .denied
        },
        show: { _, _ in XCTFail("show reached the library") },
        update: { _, _, _ in XCTFail("update reached the library") },
        schedule: { _, _, _ in XCTFail("schedule reached the library") })

    static let operations = NotificationOperationsFake(failing: true).operations

    static let events = NotificationReceiver.Events(
        isDelegateInstalled: { false },
        subscribeInteractions: { _ in XCTFail("the library's interaction hub was reached without a fake") },
        subscribeSettingsRequests: { _ in XCTFail("the library's settings hub was reached without a fake") },
        launchResponse: {
            XCTFail("launchResponse was reached without a fake")
            return nil
        })

    static let sharing = ShareReceiver.Sharing { _, completion in
        XCTFail("a share reached the library without a fake")
        completion(.failure(.presentationFailed))
    }

    @MainActor
    static func install() {
        NotificationReceiver.adding = adding
        NotificationReceiver.operations = operations
        NotificationReceiver.events.withLock { $0 = events }
        ShareReceiver.sharing = sharing
    }
}

/// `NotificationReceiver.Operations` that end at once without the library: with nothing, false, `notDetermined` or
/// success. `failing` also fails the test, for a call that must not get there.
struct NotificationOperationsFake: Sendable {
    let failing: Bool

    private func reached(_ name: String) {
        if failing { XCTFail("\(name) reached the library without a fake") }
    }

    var operations: NotificationReceiver.Operations {
        NotificationReceiver.Operations(
            removeDelivered: { _, done in reached("removeDelivered"); done() },
            removeAllDelivered: { done in reached("removeAllDelivered"); done() },
            cancelScheduled: { _, done in reached("cancelScheduled"); done() },
            cancelAllScheduled: { done in reached("cancelAllScheduled"); done() },
            getScheduled: { done in reached("getScheduled"); done([]) },
            getDelivered: { done in reached("getDelivered"); done([]) },
            requestPermission: { _, done in reached("requestPermission"); done(.success(false)) },
            authorizationStatus: { done in reached("authorizationStatus"); done(.notDetermined) },
            hasPermission: { done in reached("hasPermission"); done(false) },
            openSettings: { done in reached("openSettings"); done(.success(())) },
            setBadgeCount: { _ in reached("setBadgeCount") },
            registerCategory: { _, done in reached("registerCategory"); done() },
            removeCategory: { _, done in reached("removeCategory"); done() })
    }
}

/// Part 1, chapter 6 for the functions of part 2 (TB-10): **no public function waits for the main thread** (5.6),
/// what is accepted completes and releases once each on the main thread after the call, many threads calling at
/// once, and orders of 5.7 held in place through the C functions. Nothing here shows a dialog or a sheet or reaches
/// the notification center: the receivers' calls are closed in `setUp` (`FailClosed`) and a test installs fakes; a
/// Dialog is cancelled before the first main turn (as `DialogEntryTests`); Clipboard uses named pasteboards.
///
/// The class runs after `NotificationEventTests` (by name), which counts the first insertion of each event kind
/// over the whole run.
final class ThreadContractTests: ClipboardTestCase {
    private let none: Int32 = 0
    private var recorders: [ClipboardRecorder] = []
    private var eventRecorders: [EventRecorder] = []
    private var builders: [OpaquePointer] = []

    override func setUpWithError() throws {
        try super.setUpWithError()
        MainActor.assumeIsolated { FailClosed.install() }
    }

    /// The closed calls stay after this class: a block queued here that runs later finds them, not the library.
    override func tearDown() async throws {
        FailClosed.install()
        builders.forEach { ntk_notification_content_free($0) }
        builders = []
        try await super.tearDown()
    }

    private func kept() -> ClipboardRecorder {
        let recorder = ClipboardRecorder()
        recorders.append(recorder)
        return recorder
    }

    private func keptEvents() -> EventRecorder {
        let recorder = EventRecorder()
        eventRecorders.append(recorder)
        return recorder
    }

    private func sized<Value>(_ value: Value, _ set: (inout Value) -> Void = { _ in }) -> Value {
        var result = value
        withUnsafeMutableBytes(of: &result) { $0.storeBytes(of: UInt32(MemoryLayout<Value>.size), as: UInt32.self) }
        set(&result)
        return result
    }

    private func builder(id: String = "n1") -> OpaquePointer? {
        var out: OpaquePointer?
        XCTAssertEqual(ntk_notification_content_create(c(id), c("Title"), &out), none)
        if let out { builders.append(out) }
        return out
    }

    /// Fakes that complete at once: authorized adds, the other operations, the events with the delegate installed,
    /// and a share that the user closed.
    private func installCompletingFakes() {
        NotificationReceiver.adding = NotificationReceiver.Adding(
            authorizationStatus: { .authorized }, show: { _, _ in }, update: { _, _, _ in }, schedule: { _, _, _ in })
        NotificationReceiver.operations = NotificationOperationsFake(failing: false).operations
        NotificationReceiver.events.withLock {
            $0 = NotificationReceiver.Events(isDelegateInstalled: { true }, subscribeInteractions: { _ in }, subscribeSettingsRequests: { _ in },
                                             launchResponse: { nil })
        }
        ShareReceiver.sharing = ShareReceiver.Sharing { _, completion in completion(.success(ShareResult(completed: false, activityType: nil))) }
    }

    /// Takes away the interactions and settings requests an earlier test left held in the process's ledgers.
    private func drainHeldEvents() {
        let interactions = keptEvents()
        let settings = keptEvents()
        XCTAssertEqual(ntk_notification_add_interaction_listener(recordInteraction, interactions.userData, recordEventRelease, interactions.outListener), none)
        XCTAssertEqual(ntk_notification_add_settings_request_listener(recordSettingsRequest, settings.userData, recordEventRelease, settings.outListener),
                       none)
        runMainQueue()
        ntk_notification_listener_remove(interactions.outListener.pointee)
        ntk_notification_listener_remove(settings.outListener.pointee)
        runMainQueue()
    }

    private func interaction(_ identifier: String) -> NotificationResponseEvent {
        NotificationResponseEvent(notificationIdentifier: identifier, actionIdentifier: UNNotificationDefaultActionIdentifier, categoryIdentifier: "",
                                  userText: nil, userInfo: [:], isLaunchResponse: false)
    }

    // MARK: - No function waits for the main thread

    /// What a call is expected to do after it returned.
    private enum After {
        /// Returns at once; nothing comes later.
        case nothing
        /// Accepted: one completion and then one release, on the main thread, once it runs again.
        case completesOnMain(free: (OpaquePointer?) -> Void)
        /// A registration added and removed inside the call: one release on the main thread, no callback.
        case releasesOnMain
    }

    private struct Call: @unchecked Sendable {
        let name: String
        var expected: Int32 = 0
        let after: After
        let run: (ClipboardRecorder) -> Int32
    }

    private static let completes = After.completesOnMain(free: { _ in })

    /// Every function of the headers, each with an input it accepts where it takes one. The 134 names are part 2,
    /// 8.2; `testTheTableIsEveryFunction` checks that they are 134 different exported functions.
    private func everyFunction() -> [Call] {
        let scope = makeNamedPasteboard()
        let scopePointer = array([scope])
        let contentPointer = array([plainText("x")])
        let plainType = c("public.plain-text")
        let number = UInt32(NTK_CLIPBOARD_PATTERN_NUMBER)

        let string = Handle.makeString("s")
        let bytes = Handle.makeBytes([1, 2])
        let list = Handle.makeStringList(["a"])
        let readResult = ClipboardHandles.makeReadResult(ClipboardReadResult(items: [
            ClipboardItemData(typeIdentifiers: ["public.a"], text: "t", urlString: "https://a.example", imageDataUTType: "public.png"),
        ], numberOfItems: 1))
        let snapshot = ClipboardHandles.makeSnapshot(ClipboardSnapshot(hasStrings: true, hasURLs: false, hasImages: false, hasColors: false,
                                                                       numberOfItems: 1, typeIdentifiers: ["public.a"],
                                                                       allTypeIdentifiers: [["public.a"]], matchingItemIndexes: [0]))
        let loaded = ClipboardHandles.makeLoadedItem(.text("t"))
        let change = ClipboardMapping.change(of: ClipboardChangeEvent(kind: .changed(typesAdded: ["public.a"], typesRemoved: ["public.b"]),
                                                                      scope: .named("n"))).map(ClipboardHandles.makeChange)
        let dialogResult = DialogHandles.makeResult(DialogResultValue(button: ntk_dialog_button(NTK_DIALOG_BUTTON_POSITIVE), optionIndex: -1,
                                                                      buttonText: "OK", text: "t", username: "u", password: "p"))
        let content = builder()
        let contentToFree = builder(id: "free")
        builders.removeAll { $0 == contentToFree }
        let identifier = c("n1")
        let trigger = array([sized(ntk_notification_trigger()) {
            $0.kind = Int32(NTK_NOTIFICATION_TRIGGER_TIME_INTERVAL)
            $0.interval_seconds = 60
        }])
        let category = array([sized(ntk_notification_category()) { $0.identifier = self.c("cat") }])
        let interactionHandle = NotificationHandles.makeInteraction(NotificationMapping.interaction(of: interaction("n1")))
        let settingsRequest = NotificationHandles.makeSettingsRequest("n1")
        let notificationList = NotificationHandles.makeList([NotificationListEntry(identifier: "n1", title: "t", subtitle: "s", body: "b",
                                                                                   categoryIdentifier: "c", dateMillis: 1)])
        let shareRequest = array([sized(ntk_share_request()) {
            $0.items = self.array([self.sized(ntk_share_item()) {
                $0.kind = Int32(NTK_SHARE_ITEM_TEXT)
                $0.value = self.c("t")
            }])
            $0.item_count = 1
        }])
        let shareResult = ShareHandles.makeResult(ShareResultValue(completed: true, activityType: "a"))
        let wrongThread = Int32(NTK_NOTIFICATION_ERROR_WRONG_THREAD)
        let alert = array([sized(ntk_dialog_alert_request())])
        let confirm = array([sized(ntk_dialog_confirm_request())])
        let destructive = array([sized(ntk_dialog_destructive_request())])
        let sheet = array([sized(ntk_dialog_action_sheet_request())])
        let textInput = array([sized(ntk_dialog_text_input_request())])
        let login = array([sized(ntk_dialog_login_request())])

        func dialog(_ name: String, _ show: @escaping (UnsafeMutableRawPointer, UnsafeMutablePointer<UInt64>) -> Int32) -> Call {
            // Cancelled in the same call, before the first main turn: nothing is shown (DialogEntryTests).
            Call(name: name, after: Self.completes) { recorder in
                var id: UInt64 = 0
                let error = show(recorder.userData, &id)
                if error == 0 { _ = ntk_dialog_cancel(id) }
                return error
            }
        }

        func sync(_ name: String, _ body: @escaping () -> Void) -> Call {
            Call(name: name, after: .nothing) { _ in
                body()
                return 0
            }
        }

        return [
            // Common.h
            sync("ntk_version") { _ = ntk_version() },
            sync("ntk_last_system_code") { _ = ntk_last_system_code() },
            sync("ntk_string_data") { _ = ntk_string_data(string) },
            sync("ntk_string_size") { _ = ntk_string_size(string) },
            sync("ntk_string_free") { ntk_string_free(string) },
            sync("ntk_bytes_data") { _ = ntk_bytes_data(bytes) },
            sync("ntk_bytes_size") { _ = ntk_bytes_size(bytes) },
            sync("ntk_bytes_free") { ntk_bytes_free(bytes) },
            sync("ntk_string_list_count") { _ = ntk_string_list_count(list) },
            sync("ntk_string_list_at") { _ = ntk_string_list_at(list, 0, nil) },
            sync("ntk_string_list_free") { ntk_string_list_free(list) },

            // Clipboard.h
            Call(name: "ntk_clipboard_copy_async", after: Self.completes) {
                ntk_clipboard_copy_async(contentPointer, nil, scopePointer, recordDone, $0.userData, recordRelease)
            },
            Call(name: "ntk_clipboard_append_async", after: Self.completes) {
                ntk_clipboard_append_async(contentPointer, scopePointer, recordDone, $0.userData, recordRelease)
            },
            Call(name: "ntk_clipboard_read_async", after: .completesOnMain(free: ntk_clipboard_read_result_free)) {
                ntk_clipboard_read_async(scopePointer, recordHandle, $0.userData, recordRelease)
            },
            Call(name: "ntk_clipboard_read_data_async", after: .completesOnMain(free: ntk_bytes_free)) {
                ntk_clipboard_read_data_async(plainType, scopePointer, recordHandle, $0.userData, recordRelease)
            },
            Call(name: "ntk_clipboard_get_snapshot_async", after: .completesOnMain(free: ntk_clipboard_snapshot_free)) {
                ntk_clipboard_get_snapshot_async(nil, 0, scopePointer, recordHandle, $0.userData, recordRelease)
            },
            Call(name: "ntk_clipboard_clear_async", after: Self.completes) {
                ntk_clipboard_clear_async(scopePointer, recordDone, $0.userData, recordRelease)
            },
            Call(name: "ntk_clipboard_create_pasteboard_async", after: .completesOnMain(free: ntk_string_free)) {
                ntk_clipboard_create_pasteboard_async(Int32(NTK_CLIPBOARD_SCOPE_NAMED), scope.name, recordHandle, $0.userData, recordRelease)
            },
            Call(name: "ntk_clipboard_detect_patterns_async", after: Self.completes) {
                ntk_clipboard_detect_patterns_async(number, scopePointer, recordPatterns, $0.userData, recordRelease)
            },
            Call(name: "ntk_clipboard_detect_values_async", after: .completesOnMain(free: ntk_string_free)) {
                ntk_clipboard_detect_values_async(number, scopePointer, recordHandle, $0.userData, recordRelease)
            },
            Call(name: "ntk_clipboard_load_item_async", after: .completesOnMain(free: ntk_clipboard_loaded_item_free)) {
                ntk_clipboard_load_item_async(Int32(NTK_CLIPBOARD_ITEM_TEXT), nil, scopePointer, recordLoad, $0.userData, recordRelease, nil)
            },
            Call(name: "ntk_clipboard_cancel_load", after: Self.completes) { recorder in
                var id: UInt64 = 0
                let error = ntk_clipboard_load_item_async(Int32(NTK_CLIPBOARD_ITEM_TEXT), nil, scopePointer, recordLoad, recorder.userData,
                                                          recordRelease, &id)
                return error == 0 ? ntk_clipboard_cancel_load(id) : error
            },
            Call(name: "ntk_clipboard_start_observing_async", after: Self.completes) {
                ntk_clipboard_start_observing_async(scopePointer, recordDone, $0.userData, recordRelease)
            },
            Call(name: "ntk_clipboard_stop_observing_async", after: Self.completes) {
                ntk_clipboard_stop_observing_async(recordDone, $0.userData, recordRelease)
            },
            Call(name: "ntk_clipboard_check_foreground_change_async", after: Self.completes) {
                ntk_clipboard_check_foreground_change_async(scopePointer, recordChanged, $0.userData, recordRelease)
            },
            Call(name: "ntk_clipboard_add_change_listener", after: .releasesOnMain) { recorder in
                let error = ntk_clipboard_add_change_listener(recordChange, recorder.userData, recordRelease, recorder.outListener)
                ntk_clipboard_listener_remove(recorder.outListener.pointee)
                return error
            },
            Call(name: "ntk_clipboard_listener_remove", after: .releasesOnMain) { recorder in
                let error = ntk_clipboard_add_change_listener(recordChange, recorder.userData, recordRelease, recorder.outListener)
                ntk_clipboard_listener_remove(recorder.outListener.pointee)
                return error
            },
            sync("ntk_clipboard_read_result_item_count") { _ = ntk_clipboard_read_result_item_count(readResult) },
            sync("ntk_clipboard_read_result_item_type_count") { _ = ntk_clipboard_read_result_item_type_count(readResult, 0) },
            sync("ntk_clipboard_read_result_item_type_at") { _ = ntk_clipboard_read_result_item_type_at(readResult, 0, 0, nil) },
            sync("ntk_clipboard_read_result_item_text_at") { _ = ntk_clipboard_read_result_item_text_at(readResult, 0, nil) },
            sync("ntk_clipboard_read_result_item_url_at") { _ = ntk_clipboard_read_result_item_url_at(readResult, 0, nil) },
            sync("ntk_clipboard_read_result_item_image_type_at") { _ = ntk_clipboard_read_result_item_image_type_at(readResult, 0, nil) },
            sync("ntk_clipboard_read_result_free") { ntk_clipboard_read_result_free(readResult) },
            sync("ntk_clipboard_snapshot_has_strings") { _ = ntk_clipboard_snapshot_has_strings(snapshot) },
            sync("ntk_clipboard_snapshot_has_urls") { _ = ntk_clipboard_snapshot_has_urls(snapshot) },
            sync("ntk_clipboard_snapshot_has_images") { _ = ntk_clipboard_snapshot_has_images(snapshot) },
            sync("ntk_clipboard_snapshot_has_colors") { _ = ntk_clipboard_snapshot_has_colors(snapshot) },
            sync("ntk_clipboard_snapshot_number_of_items") { _ = ntk_clipboard_snapshot_number_of_items(snapshot) },
            sync("ntk_clipboard_snapshot_type_count") { _ = ntk_clipboard_snapshot_type_count(snapshot) },
            sync("ntk_clipboard_snapshot_type_at") { _ = ntk_clipboard_snapshot_type_at(snapshot, 0, nil) },
            sync("ntk_clipboard_snapshot_item_type_count") { _ = ntk_clipboard_snapshot_item_type_count(snapshot, 0) },
            sync("ntk_clipboard_snapshot_item_type_at") { _ = ntk_clipboard_snapshot_item_type_at(snapshot, 0, 0, nil) },
            sync("ntk_clipboard_snapshot_has_matching") { _ = ntk_clipboard_snapshot_has_matching(snapshot) },
            sync("ntk_clipboard_snapshot_matching_count") { _ = ntk_clipboard_snapshot_matching_count(snapshot) },
            sync("ntk_clipboard_snapshot_matching_at") { _ = ntk_clipboard_snapshot_matching_at(snapshot, 0) },
            sync("ntk_clipboard_snapshot_free") { ntk_clipboard_snapshot_free(snapshot) },
            sync("ntk_clipboard_loaded_item_kind") { _ = ntk_clipboard_loaded_item_kind(loaded) },
            sync("ntk_clipboard_loaded_item_text") { _ = ntk_clipboard_loaded_item_text(loaded, nil) },
            sync("ntk_clipboard_loaded_item_url") { _ = ntk_clipboard_loaded_item_url(loaded, nil) },
            sync("ntk_clipboard_loaded_item_image_data") { _ = ntk_clipboard_loaded_item_image_data(loaded, nil) },
            sync("ntk_clipboard_loaded_item_image_type") { _ = ntk_clipboard_loaded_item_image_type(loaded, nil) },
            sync("ntk_clipboard_loaded_item_file_path") { _ = ntk_clipboard_loaded_item_file_path(loaded, nil) },
            sync("ntk_clipboard_loaded_item_free") { ntk_clipboard_loaded_item_free(loaded) },
            sync("ntk_clipboard_change_kind") { _ = ntk_clipboard_change_kind(change) },
            sync("ntk_clipboard_change_scope_kind") { _ = ntk_clipboard_change_scope_kind(change) },
            sync("ntk_clipboard_change_scope_name") { _ = ntk_clipboard_change_scope_name(change, nil) },
            sync("ntk_clipboard_change_types_added_count") { _ = ntk_clipboard_change_types_added_count(change) },
            sync("ntk_clipboard_change_types_added_at") { _ = ntk_clipboard_change_types_added_at(change, 0, nil) },
            sync("ntk_clipboard_change_types_removed_count") { _ = ntk_clipboard_change_types_removed_count(change) },
            sync("ntk_clipboard_change_types_removed_at") { _ = ntk_clipboard_change_types_removed_at(change, 0, nil) },
            sync("ntk_clipboard_change_free") { ntk_clipboard_change_free(change) },
            // Last of Clipboard: the pasteboard of the calls above goes.
            Call(name: "ntk_clipboard_remove_pasteboard_async", after: Self.completes) {
                ntk_clipboard_remove_pasteboard_async(scopePointer, recordDone, $0.userData, recordRelease)
            },

            // Dialog.h
            dialog("ntk_dialog_show_alert_async") { ntk_dialog_show_alert_async(alert, recordLoad, $0, recordRelease, $1) },
            dialog("ntk_dialog_show_confirm_async") { ntk_dialog_show_confirm_async(confirm, recordLoad, $0, recordRelease, $1) },
            dialog("ntk_dialog_show_destructive_async") { ntk_dialog_show_destructive_async(destructive, recordLoad, $0, recordRelease, $1) },
            dialog("ntk_dialog_show_action_sheet_async") { ntk_dialog_show_action_sheet_async(sheet, recordLoad, $0, recordRelease, $1) },
            dialog("ntk_dialog_show_text_input_async") { ntk_dialog_show_text_input_async(textInput, recordLoad, $0, recordRelease, $1) },
            dialog("ntk_dialog_show_login_async") { ntk_dialog_show_login_async(login, recordLoad, $0, recordRelease, $1) },
            // The cancel of a request accepted in the same call, before the first main turn: CANCELED later on main.
            dialog("ntk_dialog_cancel") { ntk_dialog_show_alert_async(alert, recordLoad, $0, recordRelease, $1) },
            sync("ntk_dialog_result_button") { _ = ntk_dialog_result_button(dialogResult) },
            sync("ntk_dialog_result_option_index") { _ = ntk_dialog_result_option_index(dialogResult) },
            sync("ntk_dialog_result_button_text") { _ = ntk_dialog_result_button_text(dialogResult, nil) },
            sync("ntk_dialog_result_text") { _ = ntk_dialog_result_text(dialogResult, nil) },
            sync("ntk_dialog_result_username") { _ = ntk_dialog_result_username(dialogResult, nil) },
            sync("ntk_dialog_result_password") { _ = ntk_dialog_result_password(dialogResult, nil) },
            sync("ntk_dialog_result_free") { ntk_dialog_result_free(dialogResult) },

            // Notification.h. Off the main thread, the install returns WRONG_THREAD at once (part 1, chapter 6).
            Call(name: "ntk_notification_install", expected: wrongThread, after: .nothing) { _ in ntk_notification_install() },
            Call(name: "ntk_notification_show_async", after: Self.completes) {
                ntk_notification_show_async(content, nil, recordDone, $0.userData, recordRelease)
            },
            Call(name: "ntk_notification_update_async", after: Self.completes) {
                ntk_notification_update_async(identifier, content, nil, recordDone, $0.userData, recordRelease)
            },
            Call(name: "ntk_notification_schedule_async", after: Self.completes) {
                ntk_notification_schedule_async(identifier, content, trigger, recordDone, $0.userData, recordRelease)
            },
            Call(name: "ntk_notification_remove_async", after: Self.completes) {
                ntk_notification_remove_async(identifier, recordDone, $0.userData, recordRelease)
            },
            Call(name: "ntk_notification_remove_all_async", after: Self.completes) {
                ntk_notification_remove_all_async(recordDone, $0.userData, recordRelease)
            },
            Call(name: "ntk_notification_cancel_scheduled_async", after: Self.completes) {
                ntk_notification_cancel_scheduled_async(identifier, recordDone, $0.userData, recordRelease)
            },
            Call(name: "ntk_notification_cancel_all_scheduled_async", after: Self.completes) {
                ntk_notification_cancel_all_scheduled_async(recordDone, $0.userData, recordRelease)
            },
            Call(name: "ntk_notification_get_scheduled_async", after: .completesOnMain(free: ntk_notification_list_free)) {
                ntk_notification_get_scheduled_async(recordHandle, $0.userData, recordRelease)
            },
            Call(name: "ntk_notification_get_delivered_async", after: .completesOnMain(free: ntk_notification_list_free)) {
                ntk_notification_get_delivered_async(recordHandle, $0.userData, recordRelease)
            },
            Call(name: "ntk_notification_request_permission_async", after: Self.completes) {
                ntk_notification_request_permission_async(0, recordChanged, $0.userData, recordRelease)
            },
            Call(name: "ntk_notification_get_authorization_status_async", after: Self.completes) {
                ntk_notification_get_authorization_status_async(recordChanged, $0.userData, recordRelease)
            },
            Call(name: "ntk_notification_has_permission_async", after: Self.completes) {
                ntk_notification_has_permission_async(recordChanged, $0.userData, recordRelease)
            },
            Call(name: "ntk_notification_open_settings_async", after: Self.completes) {
                ntk_notification_open_settings_async(recordDone, $0.userData, recordRelease)
            },
            Call(name: "ntk_notification_set_badge_count_async", after: Self.completes) {
                ntk_notification_set_badge_count_async(1, recordDone, $0.userData, recordRelease)
            },
            Call(name: "ntk_notification_register_category_async", after: Self.completes) {
                ntk_notification_register_category_async(category, recordDone, $0.userData, recordRelease)
            },
            Call(name: "ntk_notification_remove_category_async", after: Self.completes) {
                ntk_notification_remove_category_async(identifier, recordDone, $0.userData, recordRelease)
            },
            Call(name: "ntk_notification_add_interaction_listener", after: .releasesOnMain) { recorder in
                let error = ntk_notification_add_interaction_listener(recordInteractionAsCompletion, recorder.userData, recordRelease, recorder.outListener)
                ntk_notification_listener_remove(recorder.outListener.pointee)
                return error
            },
            Call(name: "ntk_notification_add_settings_request_listener", after: .releasesOnMain) { recorder in
                let error = ntk_notification_add_settings_request_listener(recordSettingsRequestAsCompletion, recorder.userData, recordRelease, recorder.outListener)
                ntk_notification_listener_remove(recorder.outListener.pointee)
                return error
            },
            Call(name: "ntk_notification_get_launch_response_async", after: Self.completes) {
                ntk_notification_get_launch_response_async(recordHandle, $0.userData, recordRelease)
            },
            Call(name: "ntk_notification_listener_remove", after: .releasesOnMain) { recorder in
                let error = ntk_notification_add_interaction_listener(recordInteractionAsCompletion, recorder.userData, recordRelease, recorder.outListener)
                ntk_notification_listener_remove(recorder.outListener.pointee)
                return error
            },
            sync("ntk_notification_content_create") {
                var out: OpaquePointer?
                _ = ntk_notification_content_create("off.main", "Title", &out)
                ntk_notification_content_free(out)
            },
            sync("ntk_notification_content_free") { ntk_notification_content_free(contentToFree) },
            sync("ntk_notification_content_set_subtitle") { _ = ntk_notification_content_set_subtitle(content, "s") },
            sync("ntk_notification_content_set_body") { _ = ntk_notification_content_set_body(content, "b") },
            sync("ntk_notification_content_set_badge") { _ = ntk_notification_content_set_badge(content, 1) },
            sync("ntk_notification_content_set_sound") {
                _ = ntk_notification_content_set_sound(content, ntk_notification_sound_kind(NTK_NOTIFICATION_SOUND_DEFAULT), nil)
            },
            sync("ntk_notification_content_set_category") { _ = ntk_notification_content_set_category(content, "cat") },
            sync("ntk_notification_content_set_interruption_level") {
                _ = ntk_notification_content_set_interruption_level(content, ntk_notification_interruption_level(NTK_NOTIFICATION_INTERRUPTION_PASSIVE))
            },
            sync("ntk_notification_content_set_thread") { _ = ntk_notification_content_set_thread(content, "th") },
            sync("ntk_notification_content_set_target_content") { _ = ntk_notification_content_set_target_content(content, "tc") },
            sync("ntk_notification_content_set_relevance_score") { _ = ntk_notification_content_set_relevance_score(content, 0.5) },
            sync("ntk_notification_content_set_filter_criteria") { _ = ntk_notification_content_set_filter_criteria(content, "f") },
            sync("ntk_notification_content_set_user_info_json") { _ = ntk_notification_content_set_user_info_json(content, "{\"k\":1}") },
            sync("ntk_notification_content_add_attachment") { _ = ntk_notification_content_add_attachment(content, "a", "file:///no/such/file.png") },
            sync("ntk_notification_interaction_kind") { _ = ntk_notification_interaction_kind(interactionHandle) },
            sync("ntk_notification_interaction_notification_id") { _ = ntk_notification_interaction_notification_id(interactionHandle, nil) },
            sync("ntk_notification_interaction_action_id") { _ = ntk_notification_interaction_action_id(interactionHandle, nil) },
            sync("ntk_notification_interaction_category_id") { _ = ntk_notification_interaction_category_id(interactionHandle, nil) },
            sync("ntk_notification_interaction_user_text") { _ = ntk_notification_interaction_user_text(interactionHandle, nil) },
            sync("ntk_notification_interaction_user_info_json") { _ = ntk_notification_interaction_user_info_json(interactionHandle, nil) },
            sync("ntk_notification_interaction_is_launch") { _ = ntk_notification_interaction_is_launch(interactionHandle) },
            sync("ntk_notification_interaction_free") { ntk_notification_interaction_free(interactionHandle) },
            sync("ntk_notification_settings_request_notification_id") { _ = ntk_notification_settings_request_notification_id(settingsRequest, nil) },
            sync("ntk_notification_settings_request_free") { ntk_notification_settings_request_free(settingsRequest) },
            sync("ntk_notification_list_count") { _ = ntk_notification_list_count(notificationList) },
            sync("ntk_notification_list_identifier_at") { _ = ntk_notification_list_identifier_at(notificationList, 0, nil) },
            sync("ntk_notification_list_title_at") { _ = ntk_notification_list_title_at(notificationList, 0, nil) },
            sync("ntk_notification_list_subtitle_at") { _ = ntk_notification_list_subtitle_at(notificationList, 0, nil) },
            sync("ntk_notification_list_body_at") { _ = ntk_notification_list_body_at(notificationList, 0, nil) },
            sync("ntk_notification_list_category_at") { _ = ntk_notification_list_category_at(notificationList, 0, nil) },
            sync("ntk_notification_list_date_millis_at") { _ = ntk_notification_list_date_millis_at(notificationList, 0) },
            sync("ntk_notification_list_free") { ntk_notification_list_free(notificationList) },

            // Share.h
            Call(name: "ntk_share_content_async", after: .completesOnMain(free: ntk_share_result_free)) {
                ntk_share_content_async(shareRequest, recordHandle, $0.userData, recordRelease)
            },
            sync("ntk_share_result_completed") { _ = ntk_share_result_completed(shareResult) },
            sync("ntk_share_result_activity_type") { _ = ntk_share_result_activity_type(shareResult, nil) },
            sync("ntk_share_result_free") { ntk_share_result_free(shareResult) },
        ]
    }

    /// The table names 134 different functions, each one exported (part 2, 8.2: 134; the 2a check holds the
    /// headers, the entries and the symbols equal), so no function of the headers is missing from it.
    func testTheTableIsEveryFunction() {
        installCompletingFakes()
        let names = everyFunction().map(\.name)
        XCTAssertEqual(names.count, 134)
        XCTAssertEqual(Set(names).count, names.count, "a name twice")
        for name in names {
            XCTAssertNotNil(dlsym(UnsafeMutableRawPointer(bitPattern: -2), name), "not an exported function: \(name)")
        }
    }

    /// Part 1, chapter 6 "main を待たない" for every function (part 2, 12.1): with the main thread stopped (the test
    /// waits for the other thread on it), each call returns in time with what it is expected to return, nothing runs
    /// inside it, and what it accepted completes and releases once each on the main thread when it runs again.
    func testNoFunctionWaitsForTheMainThread() {
        installCompletingFakes()
        drainHeldEvents()
        for call in everyFunction() {
            let recorder = kept()
            let returned = onAnotherThread(timeout: 5) { call.run(recorder) }
            XCTAssertEqual(returned, call.expected, "\(call.name) did not return in time, or returned another value")
            XCTAssertEqual(recorder.calls, [], "something ran inside \(call.name)")
            switch call.after {
            case .nothing:
                runMainQueue()
                XCTAssertEqual(recorder.calls, [], call.name)
            case .completesOnMain(let free):
                let completion = finished(recorder)
                XCTAssertNotNil(completion, call.name)
                free(completion?.handle)
            case .releasesOnMain:
                runMainQueue()
                XCTAssertEqual(recorder.calls, ["release"], call.name)
                XCTAssertEqual(recorder.releases, [true], call.name)
            }
        }
    }

    // MARK: - Many threads at once

    /// Part 1, chapter 6 "スレッド": 8 threads × 25 calls at once, of the accepting functions of every feature, with
    /// the main thread stopped. Every call returns NONE; each accepted one completes once and releases once on the
    /// main thread, after the call; the request ids are all different.
    func testEightThreadsTimesTwentyFiveCalls() {
        installCompletingFakes()
        drainHeldEvents()
        let scope = makeNamedPasteboard()
        nonisolated(unsafe) let scopePointer = array([scope])
        nonisolated(unsafe) let content = builder()
        nonisolated(unsafe) let alert = array([sized(ntk_dialog_alert_request())])
        nonisolated(unsafe) let shareRequest = array([sized(ntk_share_request()) {
            $0.items = self.array([self.sized(ntk_share_item()) {
                $0.kind = Int32(NTK_SHARE_ITEM_TEXT)
                $0.value = self.c("t")
            }])
            $0.item_count = 1
        }])
        // Each kind: the call, and whether it gives a request id. A listener is added and removed in the call.
        let kinds: [(name: String, completes: Bool, call: @Sendable (ClipboardRecorder) -> (Int32, UInt64))] = [
            ("dialog", true, { recorder in
                var id: UInt64 = 0
                let error = ntk_dialog_show_alert_async(alert, recordLoad, recorder.userData, recordRelease, &id)
                _ = ntk_dialog_cancel(id)
                return (error, id)
            }),
            ("load", true, { recorder in
                var id: UInt64 = 0
                let error = ntk_clipboard_load_item_async(Int32(NTK_CLIPBOARD_ITEM_TEXT), nil, scopePointer, recordLoad, recorder.userData,
                                                          recordRelease, &id)
                return (error, id)
            }),
            ("check", true, { (ntk_clipboard_check_foreground_change_async(scopePointer, recordChanged, $0.userData, recordRelease), 0) }),
            ("show", true, { (ntk_notification_show_async(content, nil, recordDone, $0.userData, recordRelease), 0) }),
            ("scheduled", true, { (ntk_notification_get_scheduled_async(recordHandle, $0.userData, recordRelease), 0) }),
            ("share", true, { (ntk_share_content_async(shareRequest, recordHandle, $0.userData, recordRelease), 0) }),
            ("interactionListener", false, { recorder in
                let error = ntk_notification_add_interaction_listener(recordInteractionAsCompletion, recorder.userData, recordRelease, recorder.outListener)
                ntk_notification_listener_remove(recorder.outListener.pointee)
                return (error, 0)
            }),
            ("changeListener", false, { recorder in
                let error = ntk_clipboard_add_change_listener(recordChange, recorder.userData, recordRelease, recorder.outListener)
                ntk_clipboard_listener_remove(recorder.outListener.pointee)
                return (error, 0)
            }),
        ]
        let threads = 8
        let rounds = 25
        let table = (0..<threads * rounds).map { _ in kept() }
        let ids = ResultsByIndex(count: threads * rounds)
        let returned = onAnotherThread(timeout: 30) { () -> Bool in
            let group = DispatchGroup()
            // The 8 threads wait here until all are made, then call at once.
            let gate = DispatchSemaphore(value: 0)
            for thread in 0..<threads {
                group.enter()
                Thread.detachNewThread {
                    gate.wait()
                    for round in 0..<rounds {
                        let index = thread * rounds + round
                        let (error, id) = kinds[index % kinds.count].call(table[index])
                        ids.set(index, error: error, id: id)
                    }
                    group.leave()
                }
            }
            for _ in 0..<threads { gate.signal() }
            return group.wait(timeout: .now() + 25) == .success
        }
        XCTAssertEqual(returned, true, "the calls did not all return while the main thread was stopped")
        for index in table.indices {
            XCTAssertEqual(ids.error(index), none, "call \(index)")
            XCTAssertEqual(table[index].calls, [], "something ran inside call \(index)")
        }
        for index in table.indices {
            let kind = kinds[index % kinds.count]
            if kind.completes {
                let completion = finished(table[index])
                XCTAssertNotNil(completion, "call \(index) \(kind.name)")
                if kind.name == "load" { ntk_clipboard_loaded_item_free(completion?.handle) }
                if kind.name == "scheduled" { ntk_notification_list_free(completion?.handle) }
                if kind.name == "share" { ntk_share_result_free(completion?.handle) }
            } else {
                runMainQueue()
                XCTAssertEqual(table[index].calls, ["release"], "call \(index) \(kind.name)")
                XCTAssertEqual(table[index].releases, [true], "call \(index) \(kind.name)")
            }
        }
        let requestIDs = table.indices.map { ids.id($0) }.filter { $0 != 0 }
        XCTAssertEqual(requestIDs.count, threads * rounds / kinds.count * 2, "the dialogs and the loads each have an id")
        XCTAssertEqual(Set(requestIDs).count, requestIDs.count, "a request id twice")
    }

    /// 8 threads × 25 cancels of loads the main thread is running at the same time (5.7: "main 以外の取り消しと、main
    /// の完了が重なる"): whichever comes first, one completion (NONE with the item, or CANCELED) and one release.
    func testCancelsFromEightThreadsAgainstTheMainThreadsCompletions() {
        let scope = makeNamedPasteboard()
        XCTAssertEqual(copy(plainText("loaded"), to: scope), none)
        var scopeValue = scope
        let threads = 8
        let rounds = 25
        let table = (0..<threads * rounds).map { _ in kept() }
        // Queued before the loads: the cancel threads start when the main thread starts running the loads, not
        // before it, so cancels and completions overlap instead of every cancel coming first.
        let start = DispatchSemaphore(value: 0)
        MainQueue.async { for _ in 0..<threads { start.signal() } }
        var ids: [UInt64] = []
        for recorder in table {
            var id: UInt64 = 0
            XCTAssertEqual(ntk_clipboard_load_item_async(Int32(NTK_CLIPBOARD_ITEM_TEXT), nil, &scopeValue, recordLoad, recorder.userData, recordRelease,
                                                         &id), none)
            ids.append(id)
        }
        let cancelIDs = ids
        let done = DispatchGroup()
        for thread in 0..<threads {
            done.enter()
            Thread.detachNewThread {
                start.wait()
                for round in 0..<rounds {
                    _ = ntk_clipboard_cancel_load(cancelIDs[thread * rounds + round])
                    usleep(10_000)
                }
                done.leave()
            }
        }
        // The main thread runs the loads while the other threads cancel them.
        let deadline = Date(timeIntervalSinceNow: 20)
        while done.wait(timeout: .now()) != .success, Date() < deadline {
            RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.001))
        }
        XCTAssertEqual(done.wait(timeout: .now()), .success, "a cancel thread did not finish in 20 s")
        var canceled = 0
        var loaded = 0
        defer { print("[ThreadContractTests] cancels against completions: canceled=\(canceled) loaded=\(loaded)") }
        for (index, recorder) in table.enumerated() {
            let completion = finished(recorder)
            XCTAssertEqual(completion?.requestID, ids[index], "load \(index)")
            switch completion?.error {
            case ClipboardErrorValue.canceled?:
                canceled += 1
                XCTAssertNil(completion?.handle, "load \(index)")
            case none?:
                loaded += 1
                XCTAssertEqual(text(ntk_clipboard_loaded_item_text(completion?.handle, nil)), "loaded", "load \(index)")
                ntk_clipboard_loaded_item_free(completion?.handle)
            default:
                XCTFail("load \(index): \(String(describing: completion?.error))")
            }
        }
        XCTAssertGreaterThan(canceled, 0, "no cancel came before its completion")
    }

    // MARK: - Orders held in place through C (part 1, chapter 6 "競合を決まった順で再現する")

    /// Main stopped: a delivery is queued, the only registration is removed from another thread, and another
    /// delivery is queued; then main runs. The removed registration gets neither (its state is CANCEL_REQUESTED when
    /// they run), releases once on main, and both wait, in order, for the next registration (5.7, R-7).
    func testADeliveryQueuedBeforeARemovalOffTheMainThreadIsNotDelivered() {
        installCompletingFakes()
        drainHeldEvents()
        let first = keptEvents()
        XCTAssertEqual(ntk_notification_add_interaction_listener(recordInteraction, first.userData, recordEventRelease, first.outListener), none)
        runMainQueue()
        let removed = UInt(bitPattern: first.outListener.pointee)

        let one = interaction("one")
        let two = interaction("two")
        MainQueue.async { NotificationReceiver.receive(one) }
        XCTAssertEqual(onAnotherThread { () -> Bool in
            ntk_notification_listener_remove(OpaquePointer(bitPattern: removed))
            return true
        }, true)
        MainQueue.async { NotificationReceiver.receive(two) }
        XCTAssertEqual(first.interactions, [])
        XCTAssertEqual(first.releases, [])
        runMainQueue()

        XCTAssertEqual(first.interactions, [], "delivered after the removal")
        XCTAssertEqual(first.releases, [true])
        let next = keptEvents()
        XCTAssertEqual(ntk_notification_add_interaction_listener(recordInteraction, next.userData, recordEventRelease, next.outListener), none)
        XCTAssertEqual(next.interactions, [], "delivered inside the call")
        runMainQueue()
        XCTAssertEqual(next.interactions.map(\.notificationId), ["one", "two"])
        ntk_notification_listener_remove(next.outListener.pointee)
        runMainQueue()
        XCTAssertEqual(next.releases, [true])
    }

    /// Removal from another thread against deliveries on the main thread, 200 rounds through C: one release on main,
    /// nothing delivered after it, and every event either delivered or held, in order (5.7).
    func testRemovalOffTheMainThreadAgainstDeliveriesThroughC() {
        installCompletingFakes()
        drainHeldEvents()
        for round in 0..<200 {
            let recorder = keptEvents()
            XCTAssertEqual(ntk_notification_add_interaction_listener(recordInteraction, recorder.userData, recordEventRelease, recorder.outListener),
                           none)
            runMainQueue()
            let handle = UInt(bitPattern: recorder.outListener.pointee)
            let race = RaceStart()
            let finished = DispatchSemaphore(value: 0)
            Thread.detachNewThread {
                race.waitForGo()
                ntk_notification_listener_remove(OpaquePointer(bitPattern: handle))
                finished.signal()
            }
            race.go(afterSpinning: (round % 20) * 100)
            for index in 0..<5 { NotificationReceiver.receive(interaction("\(index)")) }
            XCTAssertEqual(finished.wait(timeout: .now() + 10), .success, "round \(round)")
            runMainQueue()

            XCTAssertEqual(recorder.releases, [true], "round \(round)")
            let delivered = recorder.interactions.compactMap(\.notificationId)
            XCTAssertEqual(delivered, (0..<delivered.count).map { "\($0)" }, "round \(round)")
            NotificationReceiver.receive(interaction("after"))
            XCTAssertEqual(recorder.interactions.count, delivered.count, "delivered after the release, round \(round)")

            // What was not delivered waits for the next registration, in order.
            let next = keptEvents()
            XCTAssertEqual(ntk_notification_add_interaction_listener(recordInteraction, next.userData, recordEventRelease, next.outListener), none)
            runMainQueue()
            XCTAssertEqual(next.interactions.compactMap(\.notificationId), (delivered.count..<5).map { "\($0)" } + ["after"], "round \(round)")
            ntk_notification_listener_remove(next.outListener.pointee)
            runMainQueue()
        }
    }
}

/// An event for a `ClipboardRecorder`: it shows as a completion, which no listener here expects.
private func recordInteractionAsCompletion(_ userData: UnsafeMutableRawPointer?, _ event: OpaquePointer?) {
    ntk_notification_interaction_free(event)
    ClipboardRecorder.from(userData)?.record(-100, 0)
}

private func recordSettingsRequestAsCompletion(_ userData: UnsafeMutableRawPointer?, _ request: OpaquePointer?) {
    ntk_notification_settings_request_free(request)
    ClipboardRecorder.from(userData)?.record(-101, 0)
}

/// What each concurrent call returned, written by its thread.
private final class ResultsByIndex: @unchecked Sendable {
    private let lock = NSLock()
    private var errors: [Int32]
    private var ids: [UInt64]

    init(count: Int) {
        errors = Array(repeating: -1, count: count)
        ids = Array(repeating: 0, count: count)
    }

    func set(_ index: Int, error: Int32, id: UInt64) {
        lock.withLock {
            errors[index] = error
            ids[index] = id
        }
    }

    func error(_ index: Int) -> Int32 { lock.withLock { errors[index] } }
    func id(_ index: Int) -> UInt64 { lock.withLock { ids[index] } }
}
