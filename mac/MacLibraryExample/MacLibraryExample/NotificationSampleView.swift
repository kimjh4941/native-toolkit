//
//  NotificationSampleView.swift
//  MacLibraryExample
//
//  Created by Kim Jong Hyun on 2026/05/09.
//

import SwiftUI
import MacLibrary
import Foundation

struct NotificationSampleView: View {

    private let TAG = "NotificationSampleView"

    private let notificationId = "mac-sample-notification"
    private let scheduledId = "mac-sample-scheduled"
    private let categoryId = "mac-sample-category"

    @State private var resultText = "Result will be displayed here"

    var body: some View {
        VStack(spacing: 12) {
            Text("MacNotificationManager Example")
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
                            Log.d(TAG, "[RequestPermission] called")
                            MacNotificationManager.shared.requestPermission { result in
                                switch result {
                                case .success:
                                    updateResult(isSuccess: true, result: "[requestPermission] granted")
                                case .failure(let error):
                                    if error.errorCode == 1002 || error.errorCode == 1003 {
                                        updateResult(isSuccess: false, result: "[requestPermission] denied. Permission dialog will not appear again. Please enable notifications in Settings.")
                                    } else {
                                        updateResult(error: error, prefix: "[requestPermission]")
                                    }
                                }
                            }
                        }

                        Button("HasPermission") {
                            Log.d(TAG, "[HasPermission] called")
                            MacNotificationManager.shared.getAuthorizationStatus { result in
                                switch result {
                                case .success(let status):
                                    let has = status == .authorized || status == .provisional
                                    updateResult(isSuccess: true, result: "[hasPermission] \(has)")
                                case .failure(let error):
                                    updateResult(error: error, prefix: "[hasPermission]")
                                }
                            }
                        }

                        Button("AuthorizationStatus") {
                            Log.d(TAG, "[AuthorizationStatus] called")
                            MacNotificationManager.shared.getAuthorizationStatus { result in
                                switch result {
                                case .success(let status):
                                    updateResult(isSuccess: true, result: "[authorizationStatus] \(label(for: status))")
                                case .failure(let error):
                                    updateResult(error: error, prefix: "[authorizationStatus]")
                                }
                            }
                        }

                        Button("OpenNotificationSettings") {
                            Log.d(TAG, "[OpenNotificationSettings] called")
                            MacNotificationManager.shared.openNotificationSettings { result in
                                handleResult(operation: "openNotificationSettings", result: result)
                            }
                        }
                    }

                    sectionView(title: "Show") {
                        Button("ShowImmediate") {
                            runWithPermission(operation: "showImmediate") {
                                let immediateId = "\(notificationId)-\(Int(Date().timeIntervalSince1970))"
                                let content = makeContent(id: immediateId, title: "Immediate Notification", body: "Displayed now")
                                Log.d(TAG, "[ShowImmediate] before API call id: \(content.id)")
                                MacNotificationManager.shared.show(content: content) { result in
                                    handleResult(operation: "showImmediate", result: result)
                                }
                            }
                        }

                        Button("ShowTimeInterval(10s)") {
                            runWithPermission(operation: "showTimeInterval") {
                                let content = makeContent(id: notificationId, title: "10s Notification", body: "Will be shown after 10 seconds")
                                Log.d(TAG, "[ShowTimeInterval] before API call id: \(content.id)")
                                MacNotificationManager.shared.show(
                                    content: content,
                                    trigger: .timeInterval(seconds: 10, repeats: false)
                                ) { result in
                                    handleResult(operation: "showTimeInterval", result: result)
                                }
                            }
                        }

                        Button("ShowCalendar(+1m)") {
                            runWithPermission(operation: "showCalendar") {
                                let content = makeContent(id: notificationId, title: "Calendar Notification", body: "Will be shown in one minute")
                                let components = calendarComponents(afterMinutes: 1)
                                Log.d(TAG, "[ShowCalendar] before API call id: \(content.id)")
                                MacNotificationManager.shared.show(
                                    content: content,
                                    trigger: .calendar(dateComponents: components, repeats: false)
                                ) { result in
                                    handleResult(operation: "showCalendar", result: result)
                                }
                            }
                        }
                    }

                    sectionView(title: "Update / Cancel / Remove") {
                        Button("UpdateById") {
                            runWithPermission(operation: "updateById") {
                                let content = makeContent(id: notificationId, title: "Updated Notification", body: "This content was updated")
                                Log.d(TAG, "[UpdateById] before API call identifier: \(notificationId)")
                                MacNotificationManager.shared.update(
                                    identifier: notificationId,
                                    content: content,
                                    trigger: .immediate
                                ) { result in
                                    handleResult(operation: "updateById", result: result)
                                }
                            }
                        }

                        Button("CancelById") {
                            Log.d(TAG, "[CancelById] called id: \(notificationId)")
                            MacNotificationManager.shared.cancelScheduled(identifier: notificationId)
                            updateResult(isSuccess: true, result: "[cancelById] id=\(notificationId)")
                        }

                        Button("CancelAll") {
                            Log.d(TAG, "[CancelAll] called")
                            MacNotificationManager.shared.cancelAllScheduled()
                            updateResult(isSuccess: true, result: "[cancelAll] called")
                        }

                        Button("RemoveDeliveredById") {
                            Log.d(TAG, "[RemoveDeliveredById] called id: \(notificationId)")
                            MacNotificationManager.shared.removeDelivered(identifier: notificationId)
                            updateResult(isSuccess: true, result: "[removeDelivered] id=\(notificationId)")
                        }

                        Button("RemoveAllDelivered") {
                            Log.d(TAG, "[RemoveAllDelivered] called")
                            MacNotificationManager.shared.removeAllDelivered()
                            updateResult(isSuccess: true, result: "[removeAllDelivered] called")
                        }
                    }

                    sectionView(title: "Schedule") {
                        Button("ScheduleTimeInterval(10s)") {
                            runWithPermission(operation: "scheduleTimeInterval") {
                                let content = makeContent(id: scheduledId, title: "Scheduled Notification", body: "Scheduled in 10 seconds")
                                Log.d(TAG, "[ScheduleTimeInterval] before API call id: \(content.id)")
                                MacNotificationManager.shared.schedule(
                                    content: content,
                                    trigger: .timeInterval(seconds: 10, repeats: false)
                                ) { result in
                                    handleResult(operation: "scheduleTimeInterval", result: result)
                                }
                            }
                        }

                        Button("ScheduleCalendar(+1m)") {
                            runWithPermission(operation: "scheduleCalendar") {
                                let content = makeContent(id: scheduledId, title: "Scheduled Calendar", body: "Scheduled by calendar")
                                let components = calendarComponents(afterMinutes: 1)
                                Log.d(TAG, "[ScheduleCalendar] before API call id: \(content.id)")
                                MacNotificationManager.shared.schedule(
                                    content: content,
                                    trigger: .calendar(dateComponents: components, repeats: false)
                                ) { result in
                                    handleResult(operation: "scheduleCalendar", result: result)
                                }
                            }
                        }

                        Button("CancelScheduledById") {
                            Log.d(TAG, "[CancelScheduledById] called id: \(scheduledId)")
                            MacNotificationManager.shared.cancelScheduled(identifier: scheduledId)
                            updateResult(isSuccess: true, result: "[cancelScheduled] id=\(scheduledId)")
                        }

                        Button("CancelAllScheduled") {
                            Log.d(TAG, "[CancelAllScheduled] called")
                            MacNotificationManager.shared.cancelAllScheduled()
                            updateResult(isSuccess: true, result: "[cancelAllScheduled] called")
                        }
                    }

                    sectionView(title: "Query") {
                        Button("GetScheduled") {
                            Log.d(TAG, "[GetScheduled] called")
                            MacNotificationManager.shared.getScheduled { result in
                                switch result {
                                case .success(let items):
                                    let ids = items.map { $0.identifier }.joined(separator: ", ")
                                    updateResult(isSuccess: true, result: "[getScheduled] count=\(items.count), ids=[\(ids)]")
                                case .failure(let error):
                                    updateResult(error: error, prefix: "[getScheduled]")
                                }
                            }
                        }

                        Button("GetDelivered") {
                            Log.d(TAG, "[GetDelivered] called")
                            MacNotificationManager.shared.getDelivered { result in
                                switch result {
                                case .success(let items):
                                    let ids = items.map { $0.identifier }.joined(separator: ", ")
                                    updateResult(isSuccess: true, result: "[getDelivered] count=\(items.count), ids=[\(ids)]")
                                case .failure(let error):
                                    updateResult(error: error, prefix: "[getDelivered]")
                                }
                            }
                        }
                    }

                    sectionView(title: "Badge") {
                        Button("SetBadgeCount(1)") {
                            runWithPermission(operation: "setBadgeCount(1)") {
                                Log.d(TAG, "[SetBadgeCount] called count: 1")
                                MacNotificationManager.shared.setBadgeCount(1) { result in
                                    handleResult(operation: "setBadgeCount(1)", result: result)
                                }
                            }
                        }

                        Button("SetBadgeCount(0)") {
                            runWithPermission(operation: "setBadgeCount(0)") {
                                Log.d(TAG, "[SetBadgeCount] called count: 0")
                                MacNotificationManager.shared.setBadgeCount(0) { result in
                                    handleResult(operation: "setBadgeCount(0)", result: result)
                                }
                            }
                        }
                    }

                    sectionView(title: "Category") {
                        Button("RegisterCategory") {
                            Log.d(TAG, "[RegisterCategory] called id: \(categoryId)")
                            let category = NotificationCategory(
                                id: categoryId,
                                actions: [
                                    NotificationAction(id: "open", title: "Open", isForeground: true),
                                    NotificationAction(id: "reply", title: "Reply", isTextInput: true, textInputPlaceholder: "Type message")
                                ]
                            )
                            MacNotificationManager.shared.registerCategory(category) { result in
                                switch result {
                                case .success:
                                    updateResult(isSuccess: true, result: "[registerCategory] Registered. Send a notification and right-click to see the actions (Open, Reply).")
                                case .failure(let error):
                                    updateResult(error: error, prefix: "[registerCategory]")
                                }
                            }
                        }

                        Button("RemoveCategory") {
                            Log.d(TAG, "[RemoveCategory] called id: \(categoryId)")
                            MacNotificationManager.shared.removeCategory(identifier: categoryId) { result in
                                handleResult(operation: "removeCategory", result: result)
                            }
                        }
                    }
                }
                .padding(.trailing, 12)
                .padding(.bottom, 12)
            }
            .padding()
        }
        .navigationTitle("Notification Example")
        .onAppear {
            Log.d(TAG, "[onAppear] called")
            MacNotificationManager.shared.setActionReceivedHandler { notificationId, actionId, userInfoJson in
                Log.d(TAG, "[ActionHandler] notificationId: \(notificationId), actionId: \(actionId), userInfoJson: \(userInfoJson)")
                updateResult(isSuccess: true, result: "[actionReceived] notificationId=\(notificationId), actionId=\(actionId), userInfoJson=\(userInfoJson)")
            }
            MacNotificationManager.shared.setTextInputActionReceivedHandler { notificationId, actionId, userText, userInfoJson in
                Log.d(TAG, "[TextInputActionHandler] notificationId: \(notificationId), actionId: \(actionId), userText: \(userText), userInfoJson: \(userInfoJson)")
                updateResult(isSuccess: true, result: "[textActionReceived] notificationId=\(notificationId), actionId=\(actionId), text=\(userText), userInfoJson=\(userInfoJson)")
            }
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
            subtitle: "MacLibraryExample",
            categoryIdentifier: categoryId,
            userInfo: ["source": "MacLibraryExample", "id": id],
            badge: nil
        )
    }

    private func calendarComponents(afterMinutes minutes: Int) -> DateComponents {
        let nextDate = Calendar.current.date(byAdding: .minute, value: minutes, to: Date()) ?? Date()
        var components = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute], from: nextDate)
        components.second = 0
        return components
    }

    private func runWithPermission(operation: String, action: @escaping () -> Void) {
        Log.d(TAG, "[runWithPermission] operation: \(operation)")
        MacNotificationManager.shared.getAuthorizationStatus { result in
            switch result {
            case .success(let status):
                if status == .authorized || status == .provisional {
                    action()
                    return
                }
                MacNotificationManager.shared.requestPermission { permissionResult in
                    switch permissionResult {
                    case .success(let granted):
                        if granted {
                            action()
                        } else {
                            updateResult(isSuccess: false, result: "Notification permission is not granted. Please request permission first.")
                        }
                    case .failure(let error):
                        if error.errorCode == 1002 || error.errorCode == 1003 {
                            updateResult(isSuccess: false, result: "Notification permission is not granted. Please request permission first.")
                        } else {
                            updateResult(error: error, prefix: "[\(operation)]")
                        }
                    }
                }
            case .failure(let error):
                updateResult(error: error, prefix: "[\(operation)]")
            }
        }
    }

    private func handleResult(operation: String, result: Result<Void, NotificationDomainError>) {
        switch result {
        case .success:
            Log.d(TAG, "[\(operation)] success")
            updateResult(isSuccess: true, result: "[\(operation)] success")
        case .failure(let error):
            Log.e(TAG, "[\(operation)] error: \(error)")
            updateResult(error: error, prefix: "[\(operation)]")
        }
    }

    private func updateResult(error: NotificationDomainError, prefix: String) {
        updateResult(
            isSuccess: false,
            result: "\(prefix) errorCode=\(error.errorCode), errorMessage=\(error.errorMessage)"
        )
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

    private func label(for status: NotificationAuthorizationStatus) -> String {
        switch status {
        case .notDetermined: return "notDetermined"
        case .denied:        return "denied"
        case .authorized:    return "authorized"
        case .provisional:   return "provisional"
        case .unsupported:   return "unsupported"
        @unknown default:    return "unknown"
        }
    }
}

private struct FullWidthPressableButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.body.weight(.semibold))
            .frame(maxWidth: .infinity)
            .padding(.vertical, 10)
            .padding(.horizontal, 12)
            .background(configuration.isPressed ? Color.blue.opacity(0.65) : Color.blue)
            .foregroundColor(.white)
            .cornerRadius(10)
            .opacity(configuration.isPressed ? 0.85 : 1.0)
            .scaleEffect(configuration.isPressed ? 0.98 : 1.0)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}

#Preview {
    NotificationSampleView()
}
