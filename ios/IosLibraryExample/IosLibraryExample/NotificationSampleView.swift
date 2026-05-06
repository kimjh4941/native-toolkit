import SwiftUI
import IosLibrary

struct NotificationSampleView: View {

    private let TAG = "NotificationSampleView"

    private let notificationId = "sample-notification"
    private let scheduledId = "scheduled-notification"
    private let categoryId = "sample-category"

    @State private var resultText = "Result will be displayed here"

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

            ScrollView {
                VStack(spacing: 16) {
                    sectionView(title: "Permission") {
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

                        Button("HasPermission") {
                            IosNotificationManager.shared.hasPermission { hasPermission in
                                self.updateResult(
                                    isSuccess: true,
                                    result: "[hasPermission] \(hasPermission)"
                                )
                            }
                        }

                        Button("AuthorizationStatus") {
                            IosNotificationManager.shared.authorizationStatus { status in
                                self.updateResult(
                                    isSuccess: true,
                                    result: "[authorizationStatus] \(status.label)"
                                )
                            }
                        }

                        Button("OpenNotificationSettings") {
                            IosNotificationManager.shared.openNotificationSettings()
                            self.updateResult(
                                isSuccess: true,
                                result: "[openNotificationSettings] called"
                            )
                        }
                    }

                    sectionView(title: "Show") {
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
                    }

                    sectionView(title: "Update / Cancel / Remove") {
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

                        Button("CancelById") {
                            IosNotificationManager.shared.cancel(identifier: notificationId)
                            self.updateResult(
                                isSuccess: true,
                                result: "[cancel] id: \(notificationId)"
                            )
                        }

                        Button("CancelAll") {
                            IosNotificationManager.shared.cancelAll()
                            self.updateResult(
                                isSuccess: true,
                                result: "[cancelAll] called"
                            )
                        }

                        Button("RemoveDeliveredById") {
                            IosNotificationManager.shared.removeDelivered(identifier: notificationId)
                            self.updateResult(
                                isSuccess: true,
                                result: "[removeDelivered] id: \(notificationId)"
                            )
                        }

                        Button("RemoveAllDelivered") {
                            IosNotificationManager.shared.removeAllDelivered()
                            self.updateResult(
                                isSuccess: true,
                                result: "[removeAllDelivered] called"
                            )
                        }
                    }

                    sectionView(title: "Schedule") {
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

                        Button("CancelScheduledById") {
                            IosNotificationManager.shared.cancelScheduled(identifier: scheduledId)
                            self.updateResult(
                                isSuccess: true,
                                result: "[cancelScheduled] id: \(scheduledId)"
                            )
                        }

                        Button("CancelAllScheduled") {
                            IosNotificationManager.shared.cancelAllScheduled()
                            self.updateResult(
                                isSuccess: true,
                                result: "[cancelAllScheduled] called"
                            )
                        }
                    }

                    sectionView(title: "Query") {
                        Button("GetScheduled") {
                            IosNotificationManager.shared.getScheduled { requests in
                                let ids = requests.map { $0.identifier }.joined(separator: ", ")
                                self.updateResult(
                                    isSuccess: true,
                                    result: "[getScheduled] count: \(requests.count), ids: [\(ids)]"
                                )
                            }
                        }

                        Button("GetDelivered") {
                            IosNotificationManager.shared.getDelivered { notifications in
                                let ids = notifications.map { $0.identifier }.joined(separator: ", ")
                                self.updateResult(
                                    isSuccess: true,
                                    result: "[getDelivered] count: \(notifications.count), ids: [\(ids)]"
                                )
                            }
                        }
                    }

                    sectionView(title: "Badge") {
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
                    }

                    sectionView(title: "Category") {
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
                                        textInputPlaceholder: "Type a message"
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

                        Button("RemoveCategory") {
                            IosNotificationManager.shared.removeCategory(identifier: categoryId)
                            self.updateResult(
                                isSuccess: true,
                                result: "[removeCategory] id: \(categoryId)"
                            )
                        }
                    }
                }
                .padding(.trailing, 12)
                .padding(.bottom, 12)
            }
            .padding()
        }
    }

    @ViewBuilder
    private func sectionView<Content: View>(title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(.headline)
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
