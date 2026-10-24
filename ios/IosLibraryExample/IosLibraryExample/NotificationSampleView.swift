import SwiftUI
import IosLibrary

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
    }

    enum LastEventField {
        static let sequence = "sequence"
        static let kind = "kind"
        static let notificationId = "notificationId"
        static let actionId = "actionId"
        static let userText = "userText"
    }
}

struct NotificationSampleView: View {

    private let TAG = "NotificationSampleView"

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
                            let category = NotificationCategory(
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
                                options: [.customDismissAction, .allowAnnouncement]
                            )
                            IosNotificationManager.shared.registerCategory(category)
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
    private var lastEventView: some View {
        let event = eventViewModel.snapshot
        return VStack(alignment: .leading, spacing: 2) {
            Text("sequence=\(event.sequence)")
                .accessibilityIdentifier(ID.lastEvent(ID.LastEventField.sequence))
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

    private func makeContent(id: String, title: String, body: String) -> NotificationContent {
        NotificationContent(
            id: id,
            title: title,
            body: body,
            categoryIdentifier: categoryId,
            userInfo: ["source": "IosLibraryExample", "id": id]
        )
    }

    private func makeContentWithAppIconAttachment(id: String, title: String, body: String) -> NotificationContent {
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
        Log.d(TAG, "[updateResult] isSuccess: \(isSuccess), result: \(result ?? "nil")")
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
        }
    }
}

#Preview {
    NotificationSampleView()
}
