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

    private let defaultNotificationId = "mac-sample-notification"
    private let defaultScheduledId = "mac-sample-scheduled"
    private let defaultCategoryId = "mac-sample-category"

    @State private var notificationId = "mac-sample-notification"
    @State private var notificationTitle = "macOS Notification"
    @State private var notificationBody = "This is a macOS local notification sample."
    @State private var scheduleSeconds = "10"

    @State private var resultText = "Result will be displayed here"
    @State private var actionLogText = "No action callback yet"

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                Text("MacNotificationManager Example")
                    .font(.title)
                    .fontWeight(.bold)
                    .padding(.top, 8)

                Text(resultText)
                    .padding()
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.gray.opacity(0.2))
                    .cornerRadius(8)

                Text(actionLogText)
                    .padding()
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.gray.opacity(0.12))
                    .cornerRadius(8)

                inputSection

                sectionView(title: "Permission") {
                    Button("RequestPermission") {
                        Log.d(TAG, "[RequestPermission] called")
                        MacNotificationManager.shared.requestPermission { result in
                            switch result {
                            case .success(let granted):
                                updateResult(isSuccess: granted, result: "[requestPermission] granted=\(granted)")
                            case .failure(let error):
                                updateResult(error: error, prefix: "[requestPermission]")
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

                sectionView(title: "Show / Update") {
                    Button("ShowImmediate") {
                        runWithPermission(operation: "showImmediate") {
                            let immediateId = "\(notificationId)-\(Int(Date().timeIntervalSince1970))"
                            guard let content = validatedContent(identifier: immediateId) else { return }
                            Log.d(TAG, "[ShowImmediate] before API call id: \(content.id)")
                            MacNotificationManager.shared.show(content: content) { result in
                                handleResult(operation: "showImmediate", result: result)
                            }
                        }
                    }

                    Button("ShowTimeInterval") {
                        runWithPermission(operation: "showTimeInterval") {
                            guard let seconds = validatedSeconds(), let content = validatedContent(identifier: notificationId) else { return }
                            Log.d(TAG, "[ShowTimeInterval] before API call id: \(content.id), seconds: \(seconds)")
                            MacNotificationManager.shared.show(
                                content: content,
                                trigger: .timeInterval(seconds: seconds, repeats: false)
                            ) { result in
                                handleResult(operation: "showTimeInterval", result: result)
                            }
                        }
                    }

                    Button("ShowCalendar(+1m)") {
                        runWithPermission(operation: "showCalendar") {
                            guard let content = validatedContent(identifier: notificationId) else { return }
                            var components = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute], from: Date().addingTimeInterval(60))
                            components.second = 0
                            Log.d(TAG, "[ShowCalendar] before API call id: \(content.id)")
                            MacNotificationManager.shared.show(
                                content: content,
                                trigger: .calendar(dateComponents: components, repeats: false)
                            ) { result in
                                handleResult(operation: "showCalendar", result: result)
                            }
                        }
                    }

                    Button("UpdateById") {
                        runWithPermission(operation: "updateById") {
                            guard let content = validatedContent(identifier: notificationId) else { return }
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
                }

                sectionView(title: "Schedule") {
                    Button("ScheduleTimeInterval") {
                        runWithPermission(operation: "scheduleTimeInterval") {
                            guard let seconds = validatedSeconds(), let content = validatedContent(identifier: defaultScheduledId) else { return }
                            Log.d(TAG, "[ScheduleTimeInterval] before API call id: \(content.id), seconds: \(seconds)")
                            MacNotificationManager.shared.schedule(
                                content: content,
                                trigger: .timeInterval(seconds: seconds, repeats: false)
                            ) { result in
                                handleResult(operation: "scheduleTimeInterval", result: result)
                            }
                        }
                    }

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

                    Button("CancelScheduledById") {
                        Log.d(TAG, "[CancelScheduledById] called id: \(defaultScheduledId)")
                        MacNotificationManager.shared.cancelScheduled(identifier: defaultScheduledId)
                        updateResult(isSuccess: true, result: "[cancelScheduled] id=\(defaultScheduledId)")
                    }

                    Button("CancelAllScheduled") {
                        Log.d(TAG, "[CancelAllScheduled] called")
                        MacNotificationManager.shared.cancelAllScheduled()
                        updateResult(isSuccess: true, result: "[cancelAllScheduled] called")
                    }
                }

                sectionView(title: "Query / Remove") {
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

                sectionView(title: "Category / Badge") {
                    Button("RegisterCategory") {
                        Log.d(TAG, "[RegisterCategory] called id: \(defaultCategoryId)")
                        let category = NotificationCategory(
                            id: defaultCategoryId,
                            actions: [
                                NotificationAction(id: "open", title: "Open", isForeground: true),
                                NotificationAction(id: "reply", title: "Reply", isTextInput: true, textInputPlaceholder: "Type message")
                            ]
                        )
                        MacNotificationManager.shared.registerCategory(category) { result in
                            handleResult(operation: "registerCategory", result: result)
                        }
                    }

                    Button("RemoveCategory") {
                        Log.d(TAG, "[RemoveCategory] called id: \(defaultCategoryId)")
                        MacNotificationManager.shared.removeCategory(identifier: defaultCategoryId) { result in
                            handleResult(operation: "removeCategory", result: result)
                        }
                    }

                    Button("SetBadgeCount(1)") {
                        Log.d(TAG, "[SetBadgeCount] called count: 1")
                        MacNotificationManager.shared.setBadgeCount(1) { result in
                            handleResult(operation: "setBadgeCount(1)", result: result)
                        }
                    }

                    Button("SetBadgeCount(0)") {
                        Log.d(TAG, "[SetBadgeCount] called count: 0")
                        MacNotificationManager.shared.setBadgeCount(0) { result in
                            handleResult(operation: "setBadgeCount(0)", result: result)
                        }
                    }
                }
            }
            .padding()
        }
        .navigationTitle("Notification Example")
        .onAppear {
            Log.d(TAG, "[onAppear] called")
            MacNotificationManager.shared.setActionReceivedHandler { notificationId, actionId in
                Log.d(TAG, "[ActionHandler] notificationId: \(notificationId), actionId: \(actionId)")
                DispatchQueue.main.async {
                    actionLogText = "action received: notificationId=\(notificationId), actionId=\(actionId)"
                }
            }

            MacNotificationManager.shared.setTextInputActionReceivedHandler { notificationId, actionId, userText in
                Log.d(TAG, "[TextInputActionHandler] notificationId: \(notificationId), actionId: \(actionId), userText: \(userText)")
                DispatchQueue.main.async {
                    actionLogText = "text action received: notificationId=\(notificationId), actionId=\(actionId), text=\(userText)"
                }
            }
        }
    }

    @ViewBuilder
    private var inputSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Input")
                .font(.headline)

            TextField("Notification Identifier", text: $notificationId)
                .textFieldStyle(.roundedBorder)

            TextField("Title", text: $notificationTitle)
                .textFieldStyle(.roundedBorder)

            TextField("Body", text: $notificationBody)
                .textFieldStyle(.roundedBorder)

            TextField("Schedule Seconds (>= 1)", text: $scheduleSeconds)
                .textFieldStyle(.roundedBorder)
        }
        .padding()
        .background(Color.gray.opacity(0.08))
        .cornerRadius(8)
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
                            updateResult(isSuccess: false, result: "[\(operation)] permission denied")
                        }
                    case .failure(let error):
                        updateResult(error: error, prefix: "[\(operation)]")
                    }
                }
            case .failure(let error):
                updateResult(error: error, prefix: "[\(operation)]")
            }
        }
    }

    private func validatedContent(identifier: String) -> NotificationContent? {
        Log.d(TAG, "[validatedContent] identifier: \(identifier), title: \(notificationTitle)")
        if identifier.isEmpty || identifier.count > 128 {
            updateResult(isSuccess: false, result: "Invalid identifier length. Required: 1...128")
            return nil
        }

        if notificationTitle.isEmpty || notificationTitle.count > 128 {
            updateResult(isSuccess: false, result: "Invalid title length. Required: 1...128")
            return nil
        }

        if notificationBody.count > 1024 {
            updateResult(isSuccess: false, result: "Invalid body length. Required: 0...1024")
            return nil
        }

        return NotificationContent(
            id: identifier,
            title: notificationTitle,
            body: notificationBody,
            subtitle: "MacLibraryExample",
            userInfo: ["source": "MacLibraryExample", "id": identifier],
            badge: nil
        )
    }

    private func validatedSeconds() -> TimeInterval? {
        Log.d(TAG, "[validatedSeconds] scheduleSeconds: \(scheduleSeconds)")
        guard let value = TimeInterval(scheduleSeconds), value >= 1 else {
            updateResult(isSuccess: false, result: "Invalid schedule seconds. Required: number >= 1")
            return nil
        }
        return value
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
        case .notDetermined:
            return "notDetermined"
        case .denied:
            return "denied"
        case .authorized:
            return "authorized"
        case .provisional:
            return "provisional"
        case .unsupported:
            return "unsupported"
        @unknown default:
            return "unknown"
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