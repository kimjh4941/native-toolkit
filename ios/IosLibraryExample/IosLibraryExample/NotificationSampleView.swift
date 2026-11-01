import IosLibrary
import os
import SwiftUI
import UIKit

private let logger = Logger(subsystem: "com.jonghyunkim.ios.nativetoolkit.example", category: "NotificationSampleView")

/// Single source of truth for the accessibility identifiers exposed by `NotificationSampleView`.
///
/// A button's `<name>` is the lowerCamelCase of its title without the parenthesised part. Only
/// `SetBadgeCount(1)` / `SetBadgeCount(0)` keep their digit, because they would otherwise collide.
enum NotificationSampleIdentifiers {

    static let result = "notification.result"

    static func section(_ name: String) -> String { "notification.section.\(name)" }
    static func button(_ name: String) -> String { "notification.button.\(name)" }
    static func lastEvent(_ field: String) -> String { "notification.lastEvent.\(field)" }

    enum Section {
        static let permission = "permission"
        static let show = "show"
        static let updateCancelRemove = "updateCancelRemove"
        static let schedule = "schedule"
        static let query = "query"
        static let badge = "badge"
        static let category = "category"
        /// Swift API (2.0.0): the event hub, the launch response and the host delegate (1b C5),
        /// the operations' typed results, the categories' completion and the presenter (1b C6).
        static let swiftAPI = "swiftAPI"
    }

    enum ButtonName {
        static let requestPermission = "requestPermission"
        static let hasPermission = "hasPermission"
        static let authorizationStatus = "authorizationStatus"
        static let openNotificationSettings = "openNotificationSettings"
        static let showImmediate = "showImmediate"
        static let showImmediateWithAttachment = "showImmediateWithAttachment"
        static let showTimeInterval = "showTimeInterval"
        static let showCalendar = "showCalendar"
        static let showLocation = "showLocation"
        static let updateById = "updateById"
        static let cancelById = "cancelById"
        static let cancelAll = "cancelAll"
        static let removeDeliveredById = "removeDeliveredById"
        static let removeAllDelivered = "removeAllDelivered"
        static let scheduleTimeInterval = "scheduleTimeInterval"
        static let scheduleCalendar = "scheduleCalendar"
        static let scheduleLocation = "scheduleLocation"
        static let cancelScheduledById = "cancelScheduledById"
        static let cancelAllScheduled = "cancelAllScheduled"
        static let getScheduled = "getScheduled"
        static let getDelivered = "getDelivered"
        static let setBadgeCount1 = "setBadgeCount1"
        static let setBadgeCount0 = "setBadgeCount0"
        static let registerCategory = "registerCategory"
        static let removeCategory = "removeCategory"
        // Swift API (2.0.0) section (1b SA-06, SA-08, SA-12).
        static let addSecondListener = "addSecondListener"
        static let removeSecondListener = "removeSecondListener"
        static let readLaunchResponse = "readLaunchResponse"
        static let showHostNotification = "showHostNotification"
        // Swift API (2.0.0) section (1b C6: SA-09, SA-10, SA-13, SA-05).
        static let showReservedKey = "showReservedKey"
        static let showInvalidUserInfo = "showInvalidUserInfo"
        static let registerCategoryWithCompletion = "registerCategoryWithCompletion"
        static let requestPermissionWithAppSettings = "requestPermissionWithAppSettings"
        static let openNotificationSettingsForeground = "openNotificationSettingsForeground"
        static let requestPermissionAfter3Seconds = "requestPermissionAfter3Seconds"
    }

    enum LastEventField {
        static let sequence = "sequence"
        static let kind = "kind"
        static let notificationId = "notificationId"
        static let actionId = "actionId"
        static let userText = "userText"
    }

    /// The status lines of the Swift API section (`notification.<name>`; 1b SA-06, SA-11, SA-12, SA-18).
    static func status(_ name: String) -> String { "notification.\(name)" }

    enum StatusName {
        static let launchStatus = "launchStatus"
        static let listenerCounts = "listenerCounts"
        static let lastSettingsRequest = "lastSettingsRequest"
        static let hostEvent = "hostEvent"
    }
}

struct NotificationSampleView: View {

    private typealias ID = NotificationSampleIdentifiers

    private let notificationId = "sample-notification"
    private let scheduledId = "scheduled-notification"
    private let categoryId = "sample-category"

    @State private var resultText = "Result will be displayed here"
    /// Number of result updates, exposed as the result line's `accessibilityValue` so a UI test
    /// can tell a new result from an identical old one.
    @State private var resultUpdateCount = 0
    @StateObject private var eventViewModel = NotificationEventViewModel()

    var body: some View {
        VStack(spacing: 12) {
            Text("IosNotificationManager Example")
                .font(.title)
                .fontWeight(.bold)
                .padding(.top, 8)

            Text(resultText)
                .padding()
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.gray.opacity(0.2))
                .cornerRadius(8)
                .padding(.horizontal)
                .accessibilityIdentifier(ID.result)
                .accessibilityValue("updates=\(resultUpdateCount)")

            lastEventView

            ScrollView {
                VStack(spacing: 16) {
                    sectionView(title: "Permission", identifier: ID.Section.permission) {
                        Button("RequestPermission") {
                            IosNotificationManager.shared.requestPermission { isSuccess, errorMessage in
                                if isSuccess {
                                    self.updateResult(
                                        isSuccess: true,
                                        result: "[requestPermission] granted"
                                    )
                                } else {
                                    self.updateResult(
                                        isSuccess: false,
                                        result: "[requestPermission] denied. Permission dialog will not appear again. Please enable notifications in Settings."
                                    )
                                }
                            }
                        }
                        .accessibilityIdentifier(ID.button(ID.ButtonName.requestPermission))

                        Button("HasPermission") {
                            IosNotificationManager.shared.hasPermission { hasPermission in
                                self.updateResult(
                                    isSuccess: true,
                                    result: "[hasPermission] \(hasPermission)"
                                )
                            }
                        }
                        .accessibilityIdentifier(ID.button(ID.ButtonName.hasPermission))

                        Button("AuthorizationStatus") {
                            IosNotificationManager.shared.authorizationStatus { status in
                                self.updateResult(
                                    isSuccess: true,
                                    result: "[authorizationStatus] \(status.label)"
                                )
                            }
                        }
                        .accessibilityIdentifier(ID.button(ID.ButtonName.authorizationStatus))

                        Button("OpenNotificationSettings") {
                            IosNotificationManager.shared.openNotificationSettings()
                            self.updateResult(
                                isSuccess: true,
                                result: "[openNotificationSettings] called"
                            )
                        }
                        .accessibilityIdentifier(ID.button(ID.ButtonName.openNotificationSettings))
                    }

                    sectionView(title: "Show", identifier: ID.Section.show) {
                        Button("ShowImmediate") {
                            requirePermission {
                                let content = makeContent(id: notificationId, title: "Immediate Notification", body: "Displayed now")
                                IosNotificationManager.shared.show(content: content) { isSuccess, errorMessage in
                                    self.updateResult(
                                        isSuccess: isSuccess,
                                        result: "[showImmediate] error: \(errorMessage ?? "nil")"
                                    )
                                }
                            }
                        }
                        .accessibilityIdentifier(ID.button(ID.ButtonName.showImmediate))

                        Button("ShowImmediateWithAttachment(AppIcon)") {
                            requirePermission {
                                let content = makeContentWithAppIconAttachment(
                                    id: notificationId,
                                    title: "Immediate Notification with Attachment",
                                    body: "Displayed with app icon attachment"
                                )
                                IosNotificationManager.shared.show(content: content) { isSuccess, errorMessage in
                                    self.updateResult(
                                        isSuccess: isSuccess,
                                        result: "[showImmediateWithAttachment] error: \(errorMessage ?? "nil")"
                                    )
                                }
                            }
                        }
                        .accessibilityIdentifier(ID.button(ID.ButtonName.showImmediateWithAttachment))

                        Button("ShowTimeInterval(5s)") {
                            requirePermission {
                                let content = makeContent(id: notificationId, title: "5s Notification", body: "Will be shown after 5 seconds")
                                IosNotificationManager.shared.show(
                                    content: content,
                                    trigger: .timeInterval(5.0, repeats: false)
                                ) { isSuccess, errorMessage in
                                    self.updateResult(
                                        isSuccess: isSuccess,
                                        result: "[showTimeInterval] error: \(errorMessage ?? "nil")"
                                    )
                                }
                            }
                        }
                        .accessibilityIdentifier(ID.button(ID.ButtonName.showTimeInterval))

                        Button("ShowCalendar(+1m)") {
                            requirePermission {
                                let content = makeContent(id: notificationId, title: "Calendar Notification", body: "Will be shown in one minute")
                                let components = calendarComponents(afterMinutes: 1)
                                IosNotificationManager.shared.show(
                                    content: content,
                                    trigger: .calendar(components, repeats: false)
                                ) { isSuccess, errorMessage in
                                    self.updateResult(
                                        isSuccess: isSuccess,
                                        result: "[showCalendar] error: \(errorMessage ?? "nil")"
                                    )
                                }
                            }
                        }
                        .accessibilityIdentifier(ID.button(ID.ButtonName.showCalendar))

                        Button("ShowLocation(Tokyo Station, onEntry)") {
                            requirePermission {
                                let content = makeContent(id: notificationId, title: "Location Notification", body: "You arrived at Tokyo Station")
                                IosNotificationManager.shared.show(
                                    content: content,
                                    trigger: .location(
                                        identifier: "tokyo-station",
                                        latitude: 35.6812,
                                        longitude: 139.7671,
                                        radius: 100,
                                        notifyOnEntry: true,
                                        notifyOnExit: false
                                    )
                                ) { isSuccess, errorMessage in
                                    self.updateResult(
                                        isSuccess: isSuccess,
                                        result: isSuccess
                                            ? "[showLocation] Registered. Notification will fire when entering Tokyo Station (radius: 100m)."
                                            : "[showLocation] error: \(errorMessage ?? "nil")"
                                    )
                                }
                            }
                        }
                        .accessibilityIdentifier(ID.button(ID.ButtonName.showLocation))
                    }

                    sectionView(title: "Update / Cancel / Remove", identifier: ID.Section.updateCancelRemove) {
                        Button("UpdateById") {
                            requirePermission {
                                let content = makeContent(
                                    id: notificationId,
                                    title: "Updated Notification",
                                    body: "This content was updated"
                                )
                                IosNotificationManager.shared.update(
                                    identifier: notificationId,
                                    content: content,
                                    trigger: nil
                                ) { isSuccess, errorMessage in
                                    self.updateResult(
                                        isSuccess: isSuccess,
                                        result: "[update] id: \(self.notificationId), error: \(errorMessage ?? "nil")"
                                    )
                                }
                            }
                        }
                        .accessibilityIdentifier(ID.button(ID.ButtonName.updateById))

                        Button("CancelById") {
                            IosNotificationManager.shared.cancel(identifier: notificationId)
                            self.updateResult(
                                isSuccess: true,
                                result: "[cancel] id: \(notificationId)"
                            )
                        }
                        .accessibilityIdentifier(ID.button(ID.ButtonName.cancelById))

                        Button("CancelAll") {
                            IosNotificationManager.shared.cancelAll()
                            self.updateResult(
                                isSuccess: true,
                                result: "[cancelAll] called"
                            )
                        }
                        .accessibilityIdentifier(ID.button(ID.ButtonName.cancelAll))

                        Button("RemoveDeliveredById") {
                            IosNotificationManager.shared.removeDelivered(identifier: notificationId)
                            self.updateResult(
                                isSuccess: true,
                                result: "[removeDelivered] id: \(notificationId)"
                            )
                        }
                        .accessibilityIdentifier(ID.button(ID.ButtonName.removeDeliveredById))

                        Button("RemoveAllDelivered") {
                            IosNotificationManager.shared.removeAllDelivered()
                            self.updateResult(
                                isSuccess: true,
                                result: "[removeAllDelivered] called"
                            )
                        }
                        .accessibilityIdentifier(ID.button(ID.ButtonName.removeAllDelivered))
                    }

                    sectionView(title: "Schedule", identifier: ID.Section.schedule) {
                        Button("ScheduleTimeInterval(10s)") {
                            requirePermission {
                                let content = makeContent(id: scheduledId, title: "Scheduled Notification", body: "Scheduled in 10 seconds")
                                IosNotificationManager.shared.schedule(
                                    content: content,
                                    trigger: .timeInterval(10.0, repeats: false),
                                    identifier: scheduledId
                                ) { isSuccess, errorMessage in
                                    self.updateResult(
                                        isSuccess: isSuccess,
                                        result: "[scheduleTimeInterval] id: \(self.scheduledId), error: \(errorMessage ?? "nil")"
                                    )
                                }
                            }
                        }
                        .accessibilityIdentifier(ID.button(ID.ButtonName.scheduleTimeInterval))

                        Button("ScheduleCalendar(+1m)") {
                            requirePermission {
                                let content = makeContent(id: scheduledId, title: "Scheduled Calendar", body: "Scheduled by calendar")
                                let components = calendarComponents(afterMinutes: 1)
                                IosNotificationManager.shared.schedule(
                                    content: content,
                                    trigger: .calendar(components, repeats: false),
                                    identifier: scheduledId
                                ) { isSuccess, errorMessage in
                                    self.updateResult(
                                        isSuccess: isSuccess,
                                        result: "[scheduleCalendar] id: \(self.scheduledId), error: \(errorMessage ?? "nil")"
                                    )
                                }
                            }
                        }
                        .accessibilityIdentifier(ID.button(ID.ButtonName.scheduleCalendar))

                        Button("ScheduleLocation(Tokyo Station, onEntry)") {
                            requirePermission {
                                let content = makeContent(id: scheduledId, title: "Scheduled Location", body: "You arrived at Tokyo Station")
                                IosNotificationManager.shared.schedule(
                                    content: content,
                                    trigger: .location(
                                        identifier: "tokyo-station",
                                        latitude: 35.6812,
                                        longitude: 139.7671,
                                        radius: 100,
                                        notifyOnEntry: true,
                                        notifyOnExit: false
                                    ),
                                    identifier: scheduledId
                                ) { isSuccess, errorMessage in
                                    self.updateResult(
                                        isSuccess: isSuccess,
                                        result: isSuccess
                                            ? "[scheduleLocation] Registered. Notification will fire when entering Tokyo Station (radius: 100m)."
                                            : "[scheduleLocation] error: \(errorMessage ?? "nil")"
                                    )
                                }
                            }
                        }
                        .accessibilityIdentifier(ID.button(ID.ButtonName.scheduleLocation))

                        Button("CancelScheduledById") {
                            IosNotificationManager.shared.cancelScheduled(identifier: scheduledId)
                            self.updateResult(
                                isSuccess: true,
                                result: "[cancelScheduled] id: \(scheduledId)"
                            )
                        }
                        .accessibilityIdentifier(ID.button(ID.ButtonName.cancelScheduledById))

                        Button("CancelAllScheduled") {
                            IosNotificationManager.shared.cancelAllScheduled()
                            self.updateResult(
                                isSuccess: true,
                                result: "[cancelAllScheduled] called"
                            )
                        }
                        .accessibilityIdentifier(ID.button(ID.ButtonName.cancelAllScheduled))
                    }

                    sectionView(title: "Query", identifier: ID.Section.query) {
                        Button("GetScheduled") {
                            IosNotificationManager.shared.getScheduled { requests in
                                let ids = requests.map { $0.identifier }.joined(separator: ", ")
                                self.updateResult(
                                    isSuccess: true,
                                    result: "[getScheduled] count: \(requests.count), ids: [\(ids)]"
                                )
                            }
                        }
                        .accessibilityIdentifier(ID.button(ID.ButtonName.getScheduled))

                        Button("GetDelivered") {
                            IosNotificationManager.shared.getDelivered { notifications in
                                let ids = notifications.map { $0.identifier }.joined(separator: ", ")
                                self.updateResult(
                                    isSuccess: true,
                                    result: "[getDelivered] count: \(notifications.count), ids: [\(ids)]"
                                )
                            }
                        }
                        .accessibilityIdentifier(ID.button(ID.ButtonName.getDelivered))
                    }

                    sectionView(title: "Badge", identifier: ID.Section.badge) {
                        Button("SetBadgeCount(1)") {
                            requirePermission {
                                IosNotificationManager.shared.setBadgeCount(1) { isSuccess, errorMessage in
                                    self.updateResult(
                                        isSuccess: isSuccess,
                                        result: "[setBadgeCount] 1, error: \(errorMessage ?? "nil")"
                                    )
                                }
                            }
                        }
                        .accessibilityIdentifier(ID.button(ID.ButtonName.setBadgeCount1))

                        Button("SetBadgeCount(0)") {
                            requirePermission {
                                IosNotificationManager.shared.setBadgeCount(0) { isSuccess, errorMessage in
                                    self.updateResult(
                                        isSuccess: isSuccess,
                                        result: "[setBadgeCount] 0, error: \(errorMessage ?? "nil")"
                                    )
                                }
                            }
                        }
                        .accessibilityIdentifier(ID.button(ID.ButtonName.setBadgeCount0))
                    }

                    sectionView(title: "Category", identifier: ID.Section.category) {
                        Button("RegisterCategory") {
                            IosNotificationManager.shared.registerCategory(makeCategory())
                            self.updateResult(
                                isSuccess: true,
                                result: "[registerCategory] Registered. Send a notification and long-press to see the actions (Open, Delete, Reply)."
                            )
                        }
                        .accessibilityIdentifier(ID.button(ID.ButtonName.registerCategory))

                        Button("RemoveCategory") {
                            IosNotificationManager.shared.removeCategory(identifier: categoryId)
                            self.updateResult(
                                isSuccess: true,
                                result: "[removeCategory] id: \(categoryId)"
                            )
                        }
                        .accessibilityIdentifier(ID.button(ID.ButtonName.removeCategory))
                    }

                    sectionView(title: "Swift API (2.0.0)", identifier: ID.Section.swiftAPI) {
                        swiftAPIStatusView

                        Button("AddSecondListener") {
                            self.updateResult(isSuccess: true, result: NotificationEventRouting.shared.addSecondListener())
                        }
                        .accessibilityIdentifier(ID.button(ID.ButtonName.addSecondListener))

                        Button("RemoveSecondListener") {
                            self.updateResult(isSuccess: true, result: NotificationEventRouting.shared.removeSecondListener())
                        }
                        .accessibilityIdentifier(ID.button(ID.ButtonName.removeSecondListener))

                        Button("ReadLaunchResponse") {
                            self.updateResult(isSuccess: true, result: NotificationEventRouting.shared.launchResponseLine())
                        }
                        .accessibilityIdentifier(ID.button(ID.ButtonName.readLaunchResponse))

                        Button("ShowHostNotification") {
                            requirePermission {
                                SampleHostNotificationDelegate.post { line in
                                    self.updateResult(isSuccess: true, result: line)
                                }
                            }
                        }
                        .accessibilityIdentifier(ID.button(ID.ButtonName.showHostNotification))

                        // The userInfo checks come first and reach the async form as their cases (SA-09):
                        // the library's reserved key, and a value that is not a property-list value.
                        Button("ShowReservedKey") {
                            logger.debug("[showReservedKey]")
                            requirePermission {
                                Task {
                                    await runShow(label: "showReservedKey", content: makeContent(
                                        id: notificationId, title: "Reserved Key", body: "Never shown",
                                        userInfo: ["com.jonghyunkim.nativetoolkit": 1]))
                                }
                            }
                        }
                        .accessibilityIdentifier(ID.button(ID.ButtonName.showReservedKey))

                        Button("ShowInvalidUserInfo") {
                            logger.debug("[showInvalidUserInfo]")
                            requirePermission {
                                Task {
                                    await runShow(label: "showInvalidUserInfo", content: makeContent(
                                        id: notificationId, title: "Invalid UserInfo", body: "Never shown",
                                        userInfo: ["url": URL(string: "https://example.com")!]))
                                }
                            }
                        }
                        .accessibilityIdentifier(ID.button(ID.ButtonName.showInvalidUserInfo))

                        // The result line is written in the completion, after the category is
                        // registered (SA-10): a notification posted then shows its actions at once.
                        Button("RegisterCategoryWithCompletion") {
                            logger.debug("[registerCategoryWithCompletion]")
                            IosNotificationManager.shared.registerCategory(makeCategory()) {
                                self.updateResult(isSuccess: true, result: "[registerCategoryWithCompletion] completed")
                            }
                        }
                        .accessibilityIdentifier(ID.button(ID.ButtonName.registerCategoryWithCompletion))

                        // The permission with the app's own notification settings, from the
                        // foreground (SA-13, the async form): Settings then shows the link that
                        // sends openSettingsFor.
                        Button("RequestPermissionWithAppSettings") {
                            logger.debug("[requestPermissionWithAppSettings]")
                            Task {
                                do {
                                    let granted = try await IosNotificationManager.shared.requestPermission(
                                        options: [.alert, .sound, .badge, .providesAppNotificationSettings],
                                        presenter: .foreground
                                    )
                                    report("requestPermissionWithAppSettings", Result<Bool, NotificationError>.success(granted))
                                } catch let error as NotificationError {
                                    report("requestPermissionWithAppSettings", Result<Bool, NotificationError>.failure(error))
                                } catch {
                                    updateResult(isSuccess: false, result: "[requestPermissionWithAppSettings] failure \(error)")
                                }
                            }
                        }
                        .accessibilityIdentifier(ID.button(ID.ButtonName.requestPermissionWithAppSettings))

                        // The settings page from the foreground, in the callback form the C ABI
                        // uses (SA-13).
                        Button("OpenNotificationSettingsForeground") {
                            logger.debug("[openNotificationSettingsForeground]")
                            IosNotificationManager.shared.openNotificationSettings(presenter: .foreground) { result in
                                report("openNotificationSettingsForeground", result.map { "opened" })
                            }
                        }
                        .accessibilityIdentifier(ID.button(ID.ButtonName.openNotificationSettingsForeground))

                        #if DEBUG
                        // Test only: requested 3 seconds later, so that a UI test can move the app to
                        // the background (notForeground while not determined, no alert. SA-05). The
                        // scene's state when the request is made is in the result line. The callback
                        // form, as `shareAfter3Seconds`.
                        Button("RequestPermissionAfter3Seconds") {
                            logger.debug("[requestPermissionAfter3Seconds]")
                            DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
                                let state = Self.sceneState()
                                IosNotificationManager.shared.requestPermission(presenter: .foreground) { result in
                                    report("requestPermissionAfter3Seconds@\(state)", result)
                                }
                            }
                        }
                        .accessibilityIdentifier(ID.button(ID.ButtonName.requestPermissionAfter3Seconds))
                        #endif
                    }
                }
                .padding(.trailing, 12)
                .padding(.bottom, 12)
            }
            .padding()
        }
        .onAppear {
            // Events that arrived before this screen existed (e.g. a cold start) are kept in the
            // app-wide store, so re-read it whenever the screen appears.
            eventViewModel.reload()
        }
    }

    /// The last notification event received by this process (tap, action or reply).
    ///
    /// The sequence line's `accessibilityValue` tells the UI tests how the event came and what
    /// this process read at launch (SA-18; it does not change what is shown).
    private var lastEventView: some View {
        let event = eventViewModel.snapshot
        let status = eventViewModel.status
        let route = "path=\(event.path?.rawValue ?? "-"),launch=\(event.isLaunchResponse),delivery=\(event.delivery?.rawValue ?? "-"),"
            + "mode=\(status.mode.rawValue),source=\(status.source.rawValue)"
        return VStack(alignment: .leading, spacing: 2) {
            Text("sequence=\(event.sequence)")
                .accessibilityIdentifier(ID.lastEvent(ID.LastEventField.sequence))
                .accessibilityValue(route)
            Text("kind=\(event.kind?.rawValue ?? "none")")
                .accessibilityIdentifier(ID.lastEvent(ID.LastEventField.kind))
            Text("notificationId=\(event.notificationId ?? "-")")
                .accessibilityIdentifier(ID.lastEvent(ID.LastEventField.notificationId))
            Text("actionId=\(event.actionId ?? "-")")
                .accessibilityIdentifier(ID.lastEvent(ID.LastEventField.actionId))
            Text("userText=\(event.userText ?? "-")")
                .accessibilityIdentifier(ID.lastEvent(ID.LastEventField.userText))
        }
        .font(.footnote)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal)
    }

    /// The status lines of the Swift API section.
    private var swiftAPIStatusView: some View {
        let status = eventViewModel.status
        return VStack(alignment: .leading, spacing: 2) {
            Text("install=\(status.install), isDelegateInstalled=\(status.isDelegateInstalled), mode=\(status.mode.rawValue), "
                 + "source=\(status.source.rawValue), hostDelegate=\(status.hostDelegate ? "on" : "off")")
                .accessibilityIdentifier(ID.status(ID.StatusName.launchStatus))
            Text("first=\(status.firstListenerCount), second=\(status.secondListenerCount), secondListener=\(status.secondListenerState)")
                .accessibilityIdentifier(ID.status(ID.StatusName.listenerCounts))
            Text("settingsRequests=\(status.settingsRequestCount), notificationId=\(status.lastSettingsRequestId ?? "-")")
                .accessibilityIdentifier(ID.status(ID.StatusName.lastSettingsRequest))
            Text("hostWillPresent=\(status.hostWillPresentCount), hostDidReceive=\(status.hostDidReceiveCount), "
                 + "notificationId=\(status.hostLastNotificationId ?? "-"), actionId=\(status.hostLastActionId ?? "-")")
                .accessibilityIdentifier(ID.status(ID.StatusName.hostEvent))
        }
        .font(.footnote)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private func sectionView<Content: View>(
        title: String,
        identifier: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(.headline)
                .accessibilityIdentifier(ID.section(identifier))
            content()
                .buttonStyle(FullWidthPressableButtonStyle())
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 4)
    }

    private func makeContent(id: String, title: String, body: String, userInfo extra: sending [String: Any] = [:]) -> sending NotificationContent {
        var userInfo = extra
        userInfo["source"] = "IosLibraryExample"
        userInfo["id"] = id
        return NotificationContent(
            id: id,
            title: title,
            body: body,
            categoryIdentifier: categoryId,
            userInfo: userInfo
        )
    }

    /// The sample's category: Open (foreground), Delete (destructive), Reply (text input), with
    /// the custom dismiss action.
    private func makeCategory() -> NotificationCategory {
        NotificationCategory(
            identifier: categoryId,
            actions: [
                NotificationAction(
                    identifier: "open",
                    title: "Open",
                    options: [.foreground]
                ),
                NotificationAction(
                    identifier: "delete",
                    title: "Delete",
                    options: [.destructive]
                )
            ],
            textInputActions: [
                TextInputNotificationAction(
                    identifier: "reply",
                    title: "Reply",
                    buttonTitle: "Send",
                    textInputPlaceholder: "IosLibraryExample reply"
                )
            ],
            options: [.customDismissAction]
        )
    }

    /// Shows `content` with the `async` form and writes `[<label>] success` or
    /// `[<label>] failure <case>` (Swift API section).
    private func runShow(label: String, content: sending NotificationContent) async {
        logger.debug("[runShow] label: \(label, privacy: .public), content.id: \(content.id, privacy: .public)")
        do {
            try await IosNotificationManager.shared.show(content: content, trigger: nil)
            report(label, Result<String, NotificationError>.success("shown"))
        } catch let error as NotificationError {
            report(label, Result<String, NotificationError>.failure(error))
        } catch {
            updateResult(isSuccess: false, result: "[\(label)] failure \(error)")
        }
    }

    /// Writes a typed result of the Swift API to the result line: `[<label>] success <value>` or
    /// `[<label>] failure <case>`.
    private func report<Value>(_ label: String, _ result: Result<Value, NotificationError>) {
        switch result {
        case .success(let value):
            logger.debug("[\(label, privacy: .public)] success: \(String(describing: value), privacy: .public)")
            let detail = (value as? Bool).map { "granted=\($0)" } ?? String(describing: value)
            updateResult(isSuccess: true, result: "[\(label)] success \(detail)")
        case .failure(let error):
            logger.debug("[\(label, privacy: .public)] failure: \(Self.caseName(of: error), privacy: .public)")
            updateResult(isSuccess: false, result: "[\(label)] failure \(Self.caseName(of: error))")
        }
    }

    /// The case of a notification error, with the domain and code of its detail.
    private static func caseName(of error: NotificationError) -> String {
        switch error {
        case .permissionDenied: return "permissionDenied"
        case .attachmentLoadFailed(_, let detail): return "attachmentLoadFailed(domain=\(detail.domain), code=\(detail.code))"
        case .addRequestFailed(let detail): return "addRequestFailed(domain=\(detail.domain), code=\(detail.code))"
        case .setBadgeCountFailed(let detail): return "setBadgeCountFailed(domain=\(detail.domain), code=\(detail.code))"
        case .authorizationFailed(let detail): return "authorizationFailed(domain=\(detail.domain), code=\(detail.code))"
        case .reservedUserInfoKey: return "reservedUserInfoKey"
        case .invalidUserInfo: return "invalidUserInfo"
        case .notForeground: return "notForeground"
        case .openSettingsFailed: return "openSettingsFailed"
        case .delegateNotInstalled: return "delegateNotInstalled"
        @unknown default: return "unknown"
        }
    }

    /// The activation state of the sample's window scenes (`foregroundActive`, ...).
    private static func sceneState() -> String {
        let states = UIApplication.shared.connectedScenes.map { scene -> String in
            switch scene.activationState {
            case .foregroundActive: return "foregroundActive"
            case .foregroundInactive: return "foregroundInactive"
            case .background: return "background"
            case .unattached: return "unattached"
            @unknown default: return "unknown"
            }
        }
        return states.sorted().joined(separator: ",")
    }

    private func makeContentWithAppIconAttachment(id: String, title: String, body: String) -> sending NotificationContent {
        let base = makeContent(id: id, title: title, body: body)

        guard let imageURL = Bundle.main.url(forResource: "app-icon-attachment", withExtension: "png") else {
            return base
        }

        let attachment = NotificationAttachment(identifier: "app-icon", fileURL: imageURL)
        return NotificationContent(
            id: base.id,
            title: base.title,
            subtitle: base.subtitle,
            body: base.body,
            badge: base.badge,
            sound: base.sound,
            categoryIdentifier: base.categoryIdentifier,
            interruptionLevel: base.interruptionLevel,
            threadIdentifier: base.threadIdentifier,
            targetContentIdentifier: base.targetContentIdentifier,
            relevanceScore: base.relevanceScore,
            filterCriteria: base.filterCriteria,
            userInfo: base.userInfo,
            attachments: [attachment]
        )
    }

    private func calendarComponents(afterMinutes minutes: Int) -> DateComponents {
        let nextDate = Calendar.current.date(byAdding: .minute, value: minutes, to: Date()) ?? Date()
        return Calendar.current.dateComponents([.year, .month, .day, .hour, .minute, .second], from: nextDate)
    }

    private func requirePermission(_ action: @escaping () -> Void) {
        IosNotificationManager.shared.hasPermission { hasPermission in
            if hasPermission {
                action()
            } else {
                self.updateResult(
                    isSuccess: false,
                    result: "Notification permission is not granted. Please request permission first."
                )
            }
        }
    }

    private func updateResult(isSuccess: Bool, result: String?) {
        logger.debug("[updateResult] isSuccess: \(isSuccess, privacy: .public), result: \(result ?? "nil", privacy: .private)")
        DispatchQueue.main.async {
            resultUpdateCount += 1
            if isSuccess {
                resultText = "✅ \nResult: \(result ?? "nil")"
            } else {
                resultText = "❌ \nResult: \(result ?? "nil")"
            }
        }
    }
}

private extension View {
    func buttonStyle() -> some View {
        self.frame(maxWidth: .infinity)
    }
}

private struct FullWidthPressableButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.body.weight(.semibold))
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            .padding(.horizontal, 12)
            .background(configuration.isPressed ? Color.blue.opacity(0.65) : Color.blue)
            .foregroundColor(.white)
            .cornerRadius(10)
            .opacity(configuration.isPressed ? 0.85 : 1.0)
            .scaleEffect(configuration.isPressed ? 0.98 : 1.0)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}

private extension NotificationAuthorizationStatus {
    var label: String {
        switch self {
        case .notDetermined:
            return "notDetermined"
        case .denied:
            return "denied"
        case .authorized:
            return "authorized"
        case .provisional:
            return "provisional"
        case .ephemeral:
            return "ephemeral"
        case .unknown:
            return "unknown"
        @unknown default:
            // `IosLibrary` is built for library evolution, so a later version may add cases.
            return "unknown"
        }
    }
}

#Preview {
    NotificationSampleView()
}
