# Notification Feature

Language:

- 日本語: [notification.ja.md](notification.ja.md)
- English (this page)
- 한국어: [notification.ko.md](notification.ko.md)

← [Back to Manual Top](index.md)

---

## Table of Contents

- [Android](#android)
  - [Setup](#setup)
  - [Permission](#permission)
  - [Channel Management](#channel-management)
  - [Basic Notification Operations](#basic-notification-operations)
  - [Notification Styles](#notification-styles)
  - [Platform Options](#platform-options)
  - [Custom View Styles](#custom-view-styles)
  - [Group Notifications](#group-notifications)
  - [Interaction](#interaction)
  - [Progress Notifications](#progress-notifications)
  - [Foreground Service Notifications](#foreground-service-notifications)
  - [Scheduled Notifications](#scheduled-notifications)
- [iOS](#ios)
  - [IosNotificationManager](#iosnotificationmanager)
  - [Setup](#setup-1)
  - [Permission](#permission-1)
    - [Request Notification Permission](#request-notification-permission)
    - [Check Permission](#check-permission)
    - [Get Authorization Status](#get-authorization-status)
    - [Open Notification Settings](#open-notification-settings)
  - [Show Notification](#show-notification)
    - [Immediate](#immediate)
    - [Immediate with Attachment](#immediate-with-attachment)
    - [Time Interval Trigger](#time-interval-trigger)
    - [Calendar Trigger](#calendar-trigger)
    - [Location Trigger](#location-trigger)
  - [Attachment](#attachment)
  - [Update Notification](#update-notification)
  - [Cancel / Remove Notification](#cancel--remove-notification)
  - [Scheduled Notifications](#scheduled-notifications-1)
    - [Cancel Scheduled](#cancel-scheduled)
  - [Query](#query)
  - [Badge](#badge)
  - [Categories and Actions](#categories-and-actions)
    - [Register Category](#register-category)
    - [Attach Category to Notification](#attach-category-to-notification)
    - [Remove Category](#remove-category)
    - [Action Received Callbacks](#action-received-callbacks)
- [Windows](#windows)
- [macOS](#macos)
  - [MacNotificationManager](#macnotificationmanager)
  - [Setup](#setup-2)
  - [Permission](#permission-2)
    - [Request Permission](#request-permission)
    - [Get Authorization Status](#get-authorization-status-1)
    - [Open Notification Settings](#open-notification-settings-1)
  - [Show Notification](#show-notification-1)
    - [Immediate](#immediate-1)
    - [Time Interval Trigger](#time-interval-trigger-1)
    - [Calendar Trigger](#calendar-trigger-1)
  - [Update Notification](#update-notification-1)
  - [Schedule](#schedule)
    - [Schedule Future Notification](#schedule-future-notification)
    - [Cancel Scheduled](#cancel-scheduled-1)
    - [Get Scheduled](#get-scheduled)
  - [Delivered Notifications](#delivered-notifications)
  - [Categories and Actions](#categories-and-actions-1)
    - [Register Category](#register-category-1)
    - [Remove Category](#remove-category-1)
    - [Action Received Callbacks](#action-received-callbacks-1)
  - [Badge](#badge-1)
  - [Error Codes](#error-codes)

---

## Android

### Setup

#### AndroidManifest.xml

Add the permissions required for the features you use.

```xml
<!-- Required to post notifications on Android 13 and above -->
<uses-permission android:name="android.permission.POST_NOTIFICATIONS" />

<!-- Required for scheduled notifications (exact alarms) -->
<uses-permission android:name="android.permission.SCHEDULE_EXACT_ALARM" />
<uses-permission android:name="android.permission.RECEIVE_BOOT_COMPLETED" />

<!-- Required for foreground services -->
<uses-permission android:name="android.permission.FOREGROUND_SERVICE" />
<uses-permission android:name="android.permission.FOREGROUND_SERVICE_DATA_SYNC" />
```

#### Initializing NotificationUseCases

```kotlin
import android.library.notification.data.repository.NotificationUseCases

val useCases = NotificationUseCases(context)
```

---

### Permission

```kotlin
import android.library.notification.presentation.permission.NotificationPermissionHelper

val permissionHelper = NotificationPermissionHelper(activity)

// Whether notification permission is granted (Android 13 and above)
val hasPermission: Boolean = permissionHelper.hasPermission()

// Whether app notifications are enabled
val enabled: Boolean = permissionHelper.areNotificationsEnabled()

// Whether exact alarm scheduling is permitted
val canSchedule: Boolean = permissionHelper.canScheduleExactAlarms()

// Request notification permission
permissionHelper.requestPermission { granted ->
    if (granted) { /* permission granted */ }
}

// Open settings screens
permissionHelper.openNotificationSettings()
permissionHelper.openExactAlarmSettings()
```

---

### Channel Management

A notification channel must be created before posting notifications.

```kotlin
import android.library.notification.domain.model.NotificationChannel

val channel = NotificationChannel(
    id = "my_channel",
    name = "My Channel",
    description = "Sample notification channel"
)

// Create
useCases.createChannel(channel)
    .onSuccess { /* done */ }
    .onFailure { /* handle error */ }

// Create multiple at once
useCases.createChannels(listOf(channel1, channel2))

// Delete
useCases.deleteChannel("my_channel")
```

---

### Basic Notification Operations

#### Show

```kotlin
import android.library.notification.application.model.AndroidNotificationCommand
import android.library.notification.domain.model.NotificationContent

val command = AndroidNotificationCommand(
    content = NotificationContent(
        id = 1001,
        title = "Title",
        message = "Body text",
        channel = channel
    )
)

useCases.show(command)
    .onSuccess { /* shown */ }
    .onFailure { /* handle error */ }
```

#### Update

Pass a command with the same `id` / `tag` to overwrite an active notification.

```kotlin
useCases.update(updatedCommand)
```

#### Cancel

```kotlin
// Cancel a specific notification
useCases.cancel(id = 1001)
useCases.cancel(id = 1001, tag = "my_tag")

// Cancel all notifications
useCases.cancelAll()
```

#### Get Active Notifications

Retrieve the list of currently displayed notifications (Android 6.0 and above).

```kotlin
val activeList: List<ActiveNotification> = useCases.getActive()
activeList.forEach { it.id; it.title }
```

---

### Notification Styles

Set the `style` property on `NotificationContent`.

#### Default

```kotlin
style = NotificationStyle.Default
```

<p align="center">
    <img src="images/android/notification/Example_Default.png" alt="Example_Default" width="400" />
</p>

#### BigText

Displays long text when the notification is expanded.

```kotlin
style = NotificationStyle.BigText(
    bigText = "Long body text shown when the notification is expanded.",
    summaryText = "Summary",
    bigContentTitle = "Expanded title"
)
```

<p align="center">
    <img src="images/android/notification/Example_BigText.png" alt="Example_BigText" width="400" />
</p>

#### Inbox

Displays multiple lines in a list format when expanded.

```kotlin
style = NotificationStyle.Inbox(
    lines = listOf("• Item 1", "• Item 2", "• Item 3"),
    summaryText = "3 items",
    bigContentTitle = "Expanded title"
)
```

<p align="center">
    <img src="images/android/notification/Example_Inbox.png" alt="Example_Inbox" width="400" />
</p>

#### BigPicture

Displays an image when the notification is expanded.

```kotlin
style = NotificationStyle.BigPicture(
    pictureResId = R.drawable.my_image,  // or use pictureUriString
    summaryText = "Image description",
    bigContentTitle = "Expanded title"
)
```

<p align="center">
    <img src="images/android/notification/Example_BigPicture.png" alt="Example_BigPicture" width="400" />
</p>

#### Messaging

Displays chat history in conversation format.

```kotlin
import android.library.notification.domain.model.NotificationMessage

val now = System.currentTimeMillis()

style = NotificationStyle.Messaging(
    userDisplayName = "You",
    conversationTitle = "Group name",
    isGroupConversation = true,
    messages = listOf(
        NotificationMessage(
            text = "Message body",
            timestampMillis = now - 60_000L,
            senderName = "Alice"          // null = local user
        )
    )
)
```

<p align="center">
    <img src="images/android/notification/Example_Messaging.png" alt="Example_Messaging" width="400" />
</p>

#### Media

Displays in media player format. Specify the indices of action buttons to show in compact view.

```kotlin
style = NotificationStyle.Media(
    compactActionIndices = listOf(0, 1, 2)  // up to 3
)
```

<p align="center">
    <img src="images/android/notification/Example_Media.png" alt="Example_Media" width="400" />
</p>

Set action buttons via `AndroidNotificationPlatformOptions.actions` (see [Platform Options](#platform-options)).

---

### Platform Options

Use `AndroidNotificationPlatformOptions` to configure Android-specific behavior.

```kotlin
import android.library.notification.application.model.AndroidNotificationPlatformOptions
import android.library.notification.application.model.AndroidPendingIntentRequest
import android.library.notification.application.model.AndroidNotificationAction

val command = AndroidNotificationCommand(
    content = NotificationContent( /* ... */ ),
    platformOptions = AndroidNotificationPlatformOptions(
        // Intent launched when the notification is tapped
        contentIntent = AndroidPendingIntentRequest(
            intent = Intent(context, MainActivity::class.java),
            requestCode = 1000
        ),
        // Intent fired when the notification is dismissed (swiped away)
        deleteIntent = AndroidPendingIntentRequest(
            intent = Intent(context, MyReceiver::class.java),
            requestCode = 1001,
            type = AndroidPendingIntentType.BROADCAST
        ),
        // Intent for full-screen display (e.g. while the device is locked)
        fullScreenIntent = AndroidPendingIntentRequest(
            intent = Intent(context, FullScreenActivity::class.java),
            requestCode = 1002,
            type = AndroidPendingIntentType.ACTIVITY
        ),
        // Action buttons
        actions = listOf(
            AndroidNotificationAction(
                title = "Accept",
                pendingIntent = AndroidPendingIntentRequest(
                    intent = Intent(context, ActionReceiver::class.java).apply {
                        action = "ACTION_ACCEPT"
                    },
                    requestCode = 2000,
                    type = AndroidPendingIntentType.BROADCAST
                ),
                iconResId = android.R.drawable.ic_menu_call
            )
        )
    )
)
```

---

### Custom View Styles

Display notifications using a custom layout. Use `RemoteViewAction` to set view content and click events.

#### DecoratedCustomView

```kotlin
import android.library.notification.application.model.AndroidNotificationCustomViewPlatformOptions
import android.library.notification.application.model.RemoteViewAction
import android.library.notification.domain.model.NotificationCustomViewStyleData

val command = AndroidNotificationCommand(
    content = NotificationContent(
        id = 1007,
        title = "Title",
        message = "Body",
        channel = channel,
        style = NotificationStyle.DecoratedCustomView(
            customView = NotificationCustomViewStyleData(
                layoutResId = R.layout.notification_custom,       // collapsed view
                bigLayoutResId = R.layout.notification_custom_big // expanded view (optional)
            )
        )
    ),
    platformOptions = AndroidNotificationPlatformOptions(
        customViewOptions = AndroidNotificationCustomViewPlatformOptions(
            viewActions = listOf(
                // Set text
                RemoteViewAction.SetText(R.id.notification_title, "Custom title"),
                RemoteViewAction.SetText(R.id.notification_message, "Custom body"),
                // Set image
                RemoteViewAction.SetImage(R.id.notification_icon, R.mipmap.ic_launcher),
                // Set click intent on a button
                RemoteViewAction.SetClickIntent(
                    viewId = R.id.notification_btn_dismiss,
                    pendingIntent = AndroidPendingIntentRequest(
                        intent = Intent(context, ActionReceiver::class.java).apply {
                            action = "ACTION_DISMISS"
                        },
                        requestCode = 2100,
                        type = AndroidPendingIntentType.BROADCAST
                    )
                )
            )
        )
    )
)

useCases.show(command)
```

<p align="center">
    <img src="images/android/notification/Example_DecoratedCustomView.png" alt="Example_DecoratedCustomView" width="400" />
</p>

> **Note:** Due to `RemoteViews` constraints, use `LinearLayout` + `TextView` instead of `Button` for clickable elements. Click events are set via `setOnClickPendingIntent`.

#### DecoratedMediaCustomView

Combines Media style with a custom view.

```kotlin
style = NotificationStyle.DecoratedMediaCustomView(
    customView = NotificationCustomViewStyleData(
        layoutResId = R.layout.notification_media_custom
    ),
    compactActionIndices = listOf(0, 1, 2)
)
```

<p align="center">
    <img src="images/android/notification/Example_DecoratedMediaCustomView.png" alt="Example_DecoratedMediaCustomView" width="400" />
</p>

Usage of `customViewOptions` is the same as `DecoratedCustomView`.

---

### Group Notifications

Group multiple notifications together.

```kotlin
val GROUP_KEY = "my_group_key"

// Child notification 1
val child1 = AndroidNotificationCommand(
    content = NotificationContent(
        id = 1101,
        title = "Notification 1",
        message = "Group child notification #1",
        channel = channel,
        groupKey = GROUP_KEY,
        groupAlertBehavior = NotificationCompat.GROUP_ALERT_SUMMARY,
        sortKey = "01"
    )
)

// Child notification 2
val child2 = AndroidNotificationCommand(
    content = NotificationContent(
        id = 1102,
        title = "Notification 2",
        message = "Group child notification #2",
        channel = channel,
        groupKey = GROUP_KEY,
        groupAlertBehavior = NotificationCompat.GROUP_ALERT_SUMMARY,
        sortKey = "02"
    )
)

// Summary notification (group header)
val summary = AndroidNotificationCommand(
    content = NotificationContent(
        id = 1100,
        title = "Group Summary",
        message = "2 notifications",
        channel = channel,
        groupKey = GROUP_KEY,
        isGroupSummary = true,
        groupAlertBehavior = NotificationCompat.GROUP_ALERT_SUMMARY,
        sortKey = "00"
    )
)

useCases.show(child1)
useCases.show(child2)
useCases.show(summary)
```

<p align="center">
    <img src="images/android/notification/Example_Group.png" alt="Example_Group" width="400" />
</p>

> **Tip:** Setting `groupAlertBehavior = GROUP_ALERT_SUMMARY` makes only the summary play sound and vibration; child notifications are silent.

---

### Interaction

#### Action Buttons (BroadcastReceiver)

Add buttons to a notification and receive taps via a `BroadcastReceiver`.

```kotlin
class NotificationActionReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent?) {
        val actionId = intent?.getStringExtra("extra_action_id") ?: return
        // Handle action
    }
}
```

```kotlin
// Notification with action buttons
platformOptions = AndroidNotificationPlatformOptions(
    actions = listOf(
        AndroidNotificationAction(
            title = "Accept",
            pendingIntent = AndroidPendingIntentRequest(
                intent = Intent(context, NotificationActionReceiver::class.java).apply {
                    putExtra("extra_action_id", "accept")
                },
                requestCode = 5000,
                type = AndroidPendingIntentType.BROADCAST
            )
        ),
        AndroidNotificationAction(
            title = "Decline",
            pendingIntent = AndroidPendingIntentRequest(
                intent = Intent(context, NotificationActionReceiver::class.java).apply {
                    putExtra("extra_action_id", "decline")
                },
                requestCode = 5001,
                type = AndroidPendingIntentType.BROADCAST
            )
        )
    )
)
```

<p align="center">
    <img src="images/android/notification/Example_ActionButtons.png" alt="Example_ActionButtons" width="400" />
</p>

#### DeleteIntent (Dismiss Event)

Fired when the user swipes the notification away.

```kotlin
platformOptions = AndroidNotificationPlatformOptions(
    deleteIntent = AndroidPendingIntentRequest(
        intent = Intent(context, NotificationDeleteReceiver::class.java).apply {
            action = "ACTION_NOTIFICATION_DELETED"
        },
        requestCode = 5100,
        type = AndroidPendingIntentType.BROADCAST
    )
)
```

#### FullScreenIntent (Full-Screen Display)

Launches a full-screen activity when the device is locked or the screen is off (e.g. alarms, incoming calls).

```kotlin
// Requires a high-priority channel and an appropriate category
val content = NotificationContent(
    id = 1111,
    title = "Alarm",
    message = "Time to wake up",
    channel = highPriorityChannel,
    category = NotificationCompat.CATEGORY_ALARM,
    priority = NotificationCompat.PRIORITY_HIGH
)

platformOptions = AndroidNotificationPlatformOptions(
    fullScreenIntent = AndroidPendingIntentRequest(
        intent = Intent(context, AlarmActivity::class.java),
        requestCode = 5200,
        type = AndroidPendingIntentType.ACTIVITY,
        mutable = true
    )
)
```

<p align="center">
    <img src="images/android/notification/Example_FullScreenIntent.png" alt="Example_FullScreenIntent" width="400" />
</p>

> **Note:** Depending on device state and Android policy, the notification may appear as a heads-up notification instead of full-screen.

---

### Progress Notifications

Display a progress bar for downloads or long-running operations.

```kotlin
import android.library.notification.domain.model.NotificationProgress

// Determinate progress bar
val command = AndroidNotificationCommand(
    content = NotificationContent(
        id = 1009,
        title = "Downloading",
        message = "50% complete",
        channel = channel,
        ongoing = true,
        autoCancel = false,
        progress = NotificationProgress(
            max = 100,
            current = 50,
            indeterminate = false
        )
    )
)

useCases.show(command)

// Indeterminate progress bar
val indeterminate = NotificationProgress(max = 0, current = 0, indeterminate = true)

// On completion (hide the bar and revert to a normal notification)
val complete = NotificationContent(
    id = 1009,
    ongoing = false,
    autoCancel = true,
    progress = NotificationProgress(max = 100, current = 100, indeterminate = false),
    /* ... */
)
```

<p align="center">
    <img src="images/android/notification/Example_Progress.png" alt="Example_Progress" width="400" />
</p>

---

### Foreground Service Notifications

#### Progress FGS (Long-Running Background Tasks)

Use `ProgressForegroundNotifications` to show a progress notification tied to a foreground service.

```kotlin
import android.library.notification.presentation.progress.ProgressForegroundNotifications

// Start the foreground service (also shows the notification)
ProgressForegroundNotifications.start(context, progressCommand)

// Update progress
ProgressForegroundNotifications.update(context, updatedProgressCommand)

// Complete (stop the service and demote to a regular notification)
ProgressForegroundNotifications.complete(context, completionCommand)

// Force stop (also removes the notification)
ProgressForegroundNotifications.stop(context)
```

<p align="center">
    <img src="images/android/notification/Example_ProgressForeground.png" alt="Example_ProgressForeground" width="400" />
</p>

Declare the service in `AndroidManifest.xml`.

```xml
<service
    android:name="android.library.notification.presentation.progress.ProgressForegroundService"
    android:foregroundServiceType="dataSync"
    android:exported="false" />
```

#### Call Style FGS (Call Notifications)

Show CallStyle notifications (incoming, ongoing, screening) via a foreground service.

```kotlin
import android.library.notification.presentation.call.CallStyleForegroundService
import androidx.core.content.ContextCompat

// Start incoming call notification
ContextCompat.startForegroundService(
    context,
    CallStyleForegroundService.createIncomingStartIntent(context)
)

// Switch to ongoing call notification
ContextCompat.startForegroundService(
    context,
    CallStyleForegroundService.createOngoingStartIntent(context)
)

// Stop
context.startService(CallStyleForegroundService.createStopIntent(context))
```

<p align="center">
    <img src="images/android/notification/Example_CallStyle.png" alt="Example_CallStyle" width="400" />
</p>

Declare the service in `AndroidManifest.xml`.

```xml
<service
    android:name="android.library.notification.presentation.call.CallStyleForegroundService"
    android:foregroundServiceType="specialUse"
    android:exported="false">
    <property
        android:name="android.app.PROPERTY_SPECIAL_USE_FGS_SUBTYPE"
        android:value="call" />
</service>
```

---

### Scheduled Notifications

Automatically show a notification at a specified time.

```kotlin
import android.library.notification.domain.model.NotificationSchedule

val schedule = NotificationSchedule(
    triggerAtMillis = System.currentTimeMillis() + 15_000L, // 15 seconds from now
    exact = true,           // exact alarm (requires SCHEDULE_EXACT_ALARM)
    allowWhileIdle = true,  // fires even in Doze mode
    persistAcrossBoot = true // restored after device reboot
)

useCases.schedule(command, schedule)
    .onSuccess { /* scheduled */ }
    .onFailure { /* handle error */ }
```

<p align="center">
    <img src="images/android/notification/Example_Scheduled.png" alt="Example_Scheduled" width="400" />
</p>

#### Cancel Scheduled Notifications

```kotlin
useCases.cancelScheduled(id = 1010)
useCases.cancelAllScheduled()
```

#### Restore After Reboot

Use `RECEIVE_BOOT_COMPLETED` to restore schedules after a device reboot.

```kotlin
// Call inside BroadcastReceiver.onReceive
useCases.restoreScheduled()
```

Declare the receiver in `AndroidManifest.xml`.

```xml
<receiver
    android:name="android.library.notification.data.repository.ScheduledNotificationBootReceiver"
    android:exported="false">
    <intent-filter>
        <action android:name="android.intent.action.BOOT_COMPLETED" />
        <action android:name="android.intent.action.LOCKED_BOOT_COMPLETED" />
        <action android:name="android.intent.action.MY_PACKAGE_REPLACED" />
    </intent-filter>
</receiver>
```

#### Check Scheduled Status

```kotlin
val isScheduled: Boolean = useCases.isScheduled(context, id = 1010)
```

---

## iOS

### IosNotificationManager

`IosNotificationManager` is a singleton class that provides all local notification operations on iOS.

<p align="center">
    <img src="images/ios/notification/Example_IosNotificationManager.png" alt="Example_IosNotificationManager" width="400" />
</p>

### Setup

Call `setup()` once at app launch (e.g. in `AppDelegate.application(_:didFinishLaunchingWithOptions:)`).

```swift
import IosLibrary

IosNotificationManager.setup()
```

### Permission

#### Request Notification Permission

```swift
IosNotificationManager.shared.requestPermission { isSuccess, errorMessage in
    if isSuccess {
        // Granted
    } else {
        // Denied. User must enable manually in Settings.
    }
}
```

<p align="center">
    <img src="images/ios/notification/Example_IosNotificationManager_RequestPermission.png" alt="Example_IosNotificationManager_RequestPermission" width="400" />
</p>

#### Check Permission

```swift
IosNotificationManager.shared.hasPermission { hasPermission in
    print(hasPermission) // true / false
}
```

#### Get Authorization Status

```swift
IosNotificationManager.shared.authorizationStatus { status in
    // .notDetermined / .denied / .authorized / .provisional / .ephemeral / .unknown
    print(status)
}
```

#### Open Notification Settings

```swift
IosNotificationManager.shared.openNotificationSettings()
```

### Show Notification

Create a `NotificationContent` and call `show()`.

#### Immediate

```swift
let content = NotificationContent(
    id: "sample-notification",
    title: "Immediate Notification",
    body: "Displayed now",
    categoryIdentifier: "sample-category",
    userInfo: ["source": "IosLibraryExample", "id": "sample-notification"]
)

IosNotificationManager.shared.show(content: content) { isSuccess, errorMessage in
    print(isSuccess, errorMessage ?? "")
}
```

<p align="center">
    <img src="images/ios/notification/Example_IosNotificationManager_ShowImmediate.png" alt="Example_IosNotificationManager_ShowImmediate" width="400" />
</p>

#### Immediate with Attachment

Show a notification with an image file bundled in the app.
Expand the notification (long-press) to see the attachment thumbnail.

```swift
guard let imageURL = Bundle.main.url(forResource: "app-icon-attachment", withExtension: "png") else { return }

let attachment = NotificationAttachment(identifier: "app-icon", fileURL: imageURL)
let content = NotificationContent(
    id: "sample-notification",
    title: "Immediate Notification with Attachment",
    body: "Displayed with app icon attachment",
    categoryIdentifier: "sample-category",
    userInfo: ["source": "IosLibraryExample", "id": "sample-notification"],
    attachments: [attachment]
)

IosNotificationManager.shared.show(content: content) { isSuccess, errorMessage in
    print(isSuccess, errorMessage ?? "")
}
```

<p align="center">
    <img src="images/ios/notification/Example_IosNotificationManager_ShowImmediateWithAttachment.png" alt="Example_IosNotificationManager_ShowImmediateWithAttachment" width="400" />
</p>

#### Time Interval Trigger

```swift
IosNotificationManager.shared.show(
    content: content,
    trigger: .timeInterval(5.0, repeats: false)
) { isSuccess, errorMessage in
    print(isSuccess, errorMessage ?? "")
}
```

#### Calendar Trigger

```swift
var components = DateComponents()
components.hour = 9
components.minute = 0

IosNotificationManager.shared.show(
    content: content,
    trigger: .calendar(components, repeats: true)
) { isSuccess, errorMessage in
    print(isSuccess, errorMessage ?? "")
}
```

#### Location Trigger

Location notifications use CoreLocation. Add a location usage description to `Info.plist`.

```swift
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
    print(isSuccess, errorMessage ?? "")
}
```

### Attachment

Use `NotificationAttachment` to attach images, audio, or video to a notification.
The attachment thumbnail is shown when the notification is expanded (long-press).

```swift
guard let imageURL = Bundle.main.url(forResource: "app-icon-attachment", withExtension: "png") else { return }

let attachment = NotificationAttachment(identifier: "app-icon", fileURL: imageURL)
let content = NotificationContent(
    id: "sample-notification",
    title: "Notification with Image",
    body: "Expand to see the image",
    attachments: [attachment]
)

IosNotificationManager.shared.show(content: content) { isSuccess, errorMessage in
    print(isSuccess, errorMessage ?? "")
}
```

### Update Notification

Update the content or trigger of a pending notification.

```swift
let updatedContent = NotificationContent(
    id: "sample-notification",
    title: "Updated Title",
    body: "Content has changed"
)

IosNotificationManager.shared.update(
    identifier: "sample-notification",
    content: updatedContent,
    trigger: nil
) { isSuccess, errorMessage in
    print(isSuccess, errorMessage ?? "")
}
```

### Cancel / Remove Notification

```swift
// Cancel a specific pending notification
IosNotificationManager.shared.cancel(identifier: "sample-notification")

// Cancel all pending notifications
IosNotificationManager.shared.cancelAll()

// Remove a specific delivered notification from Notification Center
IosNotificationManager.shared.removeDelivered(identifier: "sample-notification")

// Remove all delivered notifications from Notification Center
IosNotificationManager.shared.removeAllDelivered()
```

### Scheduled Notifications

Schedule a notification for future delivery with a specific identifier.

```swift
let content = NotificationContent(
    id: "scheduled-notification",
    title: "Scheduled Notification",
    body: "Displayed after 10 seconds"
)

IosNotificationManager.shared.schedule(
    content: content,
    trigger: .timeInterval(10.0, repeats: false),
    identifier: "scheduled-notification"
) { isSuccess, errorMessage in
    print(isSuccess, errorMessage ?? "")
}
```

#### Cancel Scheduled

```swift
// Cancel a specific scheduled notification
IosNotificationManager.shared.cancelScheduled(identifier: "scheduled-notification")

// Cancel all scheduled notifications
IosNotificationManager.shared.cancelAllScheduled()
```

### Query

```swift
// Get all pending (not yet delivered) notification requests
IosNotificationManager.shared.getScheduled { requests in
    requests.forEach { print($0.identifier) }
}

// Get all notifications visible in Notification Center
IosNotificationManager.shared.getDelivered { notifications in
    notifications.forEach { print($0.identifier) }
}
```

### Badge

```swift
// Set badge count (use 0 to clear)
IosNotificationManager.shared.setBadgeCount(1) { isSuccess, errorMessage in
    print(isSuccess, errorMessage ?? "")
}

IosNotificationManager.shared.setBadgeCount(0) { isSuccess, errorMessage in
    print(isSuccess, errorMessage ?? "")
}
```

### Category and Actions

Add action buttons or text input to notifications.

#### Register Category

```swift
let category = NotificationCategory(
    identifier: "sample-category",
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
```

#### Attach Category to Notification

Set the `categoryIdentifier` in `NotificationContent`.
Long-press the notification to see the action buttons.

```swift
let content = NotificationContent(
    id: "sample-notification",
    title: "Notification with Actions",
    body: "Long-press to see actions",
    categoryIdentifier: "sample-category"
)
```

#### Remove Category

```swift
IosNotificationManager.shared.removeCategory(identifier: "sample-category")
```

<p align="center">
    <img src="images/ios/notification/Example_IosNotificationManager_Category.png" alt="Example_IosNotificationManager_Category" width="400" />
</p>

#### Action Received Callbacks

```swift
// Receive action button taps
IosNotificationManager.shared.onActionReceived = { notificationId, actionId, userInfo in
    print("notification: \(notificationId), action: \(actionId)")
}

// Receive text input action submissions
IosNotificationManager.shared.onTextInputActionReceived = { notificationId, actionId, userText, userInfo in
    print("notification: \(notificationId), action: \(actionId), text: \(userText)")
}
```

---

## Windows

(Coming soon)

---

## macOS

### MacNotificationManager

`MacNotificationManager` is a singleton class that provides all local notification operations on macOS.

**Requirements:** macOS 15+. Calls on earlier OS versions return `unsupportedOS` (error code 1001).

**Thread safety:** Public APIs can be called from any thread. All completion callbacks are dispatched to the **main queue**.

### Setup

Call `setup()` once at app launch (e.g. in `applicationDidFinishLaunching`).

```swift
import MacLibrary

MacNotificationManager.shared.setup()

// Set up action callbacks (optional)
MacNotificationManager.shared.setActionReceivedHandler { notificationId, actionId, userInfoJson in
    print("Action received: \(notificationId), \(actionId)")
}

MacNotificationManager.shared.setTextInputActionReceivedHandler { notificationId, actionId, userText, userInfoJson in
    print("Text input received: \(userText)")
}
```

### Permission

#### Request Permission

```swift
MacNotificationManager.shared.requestPermission { result in
    // runs on main queue
    switch result {
    case .success(let granted):
        print("Granted: \(granted)")
    case .failure(let error):
        print("Error \(error.errorCode): \(error.errorMessage)")
    }
}
```

![Request Permission Dialog](images/mac/notification/Example_MacNotificationManager_RequestPermission.png)

> Note: Screenshots must be added manually.

#### Get Authorization Status

```swift
MacNotificationManager.shared.getAuthorizationStatus { result in
    switch result {
    case .success(let status):
        // .notDetermined / .denied / .authorized / .provisional / .unsupported
        print(status)
    case .failure(let error):
        print("Error \(error.errorCode): \(error.errorMessage)")
    }
}
```

#### Open Notification Settings

```swift
MacNotificationManager.shared.openNotificationSettings { result in
    if case .failure(let error) = result {
        print("Error \(error.errorCode): \(error.errorMessage)")
    }
}
```

### Show Notification

Create a `NotificationContent` and call `show()`.

**`NotificationContent` constraints:**
- `id`: 1–128 chars (`[A-Za-z0-9\-_]`)
- `title`: 1–128 chars
- `body`: 0–1024 chars (optional)

#### Immediate

```swift
import MacLibrary

let content = NotificationContent(
    id: "hello-notification",
    title: "Hello",
    body: "This is an immediate notification.",
    categoryIdentifier: "sample-category"
)

MacNotificationManager.shared.show(content: content) { result in
    // runs on main queue
    switch result {
    case .success:
        print("Notification shown")
    case .failure(let error):
        print("Error \(error.errorCode): \(error.errorMessage)")
    }
}
```

![Immediate Notification](images/mac/notification/Example_MacNotificationManager_ShowImmediate.png)

> Note: Screenshots must be added manually.

#### Time Interval Trigger

```swift
MacNotificationManager.shared.show(
    content: content,
    trigger: .timeInterval(seconds: 10, repeats: false)
) { result in
    switch result {
    case .success:
        print("Scheduled for 10 seconds")
    case .failure(let error):
        print("Error \(error.errorCode): \(error.errorMessage)")
    }
}
```

#### Calendar Trigger

```swift
var components = DateComponents()
components.hour = 9
components.minute = 0

MacNotificationManager.shared.show(
    content: content,
    trigger: .calendar(dateComponents: components, repeats: true)
) { result in
    switch result {
    case .success:
        print("Scheduled daily at 09:00")
    case .failure(let error):
        print("Error \(error.errorCode): \(error.errorMessage)")
    }
}
```

### Update Notification

Replaces a pending notification with new content.

```swift
let updatedContent = NotificationContent(
    id: "hello-notification",
    title: "Updated Title",
    body: "The content has been updated."
)

MacNotificationManager.shared.update(
    identifier: "hello-notification",
    content: updatedContent,
    trigger: .timeInterval(seconds: 5, repeats: false)
) { result in
    switch result {
    case .success:
        print("Updated")
    case .failure(let error):
        // error code 1104 if notification not found
        print("Error \(error.errorCode): \(error.errorMessage)")
    }
}
```

### Schedule

Use `schedule()` to register a future notification. The trigger must not be `.immediate`.

#### Schedule Future Notification

```swift
let content = NotificationContent(
    id: "scheduled-notification",
    title: "Scheduled Notification",
    body: "Delivered after 30 seconds."
)

MacNotificationManager.shared.schedule(
    content: content,
    trigger: .timeInterval(seconds: 30, repeats: false)
) { result in
    switch result {
    case .success:
        print("Scheduled")
    case .failure(let error):
        print("Error \(error.errorCode): \(error.errorMessage)")
    }
}
```

#### Cancel Scheduled

```swift
// Cancel a specific pending notification
MacNotificationManager.shared.cancelScheduled(identifier: "scheduled-notification")

// Cancel all pending notifications
MacNotificationManager.shared.cancelAllScheduled()
```

#### Get Scheduled

```swift
MacNotificationManager.shared.getScheduled { result in
    switch result {
    case .success(let notifications):
        notifications.forEach { print($0.identifier, $0.title) }
    case .failure(let error):
        print("Error \(error.errorCode): \(error.errorMessage)")
    }
}
```

### Delivered Notifications

```swift
// Get all delivered notifications
MacNotificationManager.shared.getDelivered { result in
    switch result {
    case .success(let notifications):
        notifications.forEach { print($0.identifier, $0.date) }
    case .failure(let error):
        print("Error \(error.errorCode): \(error.errorMessage)")
    }
}

// Remove a specific delivered notification
MacNotificationManager.shared.removeDelivered(identifier: "hello-notification")

// Remove all delivered notifications
MacNotificationManager.shared.removeAllDelivered()
```

### Categories and Actions

#### Register Category

```swift
let category = NotificationCategory(
    id: "sample-category",
    actions: [
        NotificationAction(
            id: "open",
            title: "Open",
            isForeground: true
        ),
        NotificationAction(
            id: "delete",
            title: "Delete",
            isForeground: false
        ),
        NotificationAction(
            id: "reply",
            title: "Reply",
            isTextInput: true,
            textInputPlaceholder: "Type a message"
        )
    ]
)

MacNotificationManager.shared.registerCategory(category) { result in
    switch result {
    case .success:
        print("Category registered")
    case .failure(let error):
        print("Error \(error.errorCode): \(error.errorMessage)")
    }
}
```

Attach the category to a notification by setting `categoryIdentifier` in `NotificationContent`.

```swift
let content = NotificationContent(
    id: "action-notification",
    title: "Notification with Actions",
    body: "Long-press to see actions",
    categoryIdentifier: "sample-category"
)
```

![Category Actions](images/mac/notification/Example_MacNotificationManager_Category.png)

> Note: Screenshots must be added manually.

#### Remove Category

```swift
MacNotificationManager.shared.removeCategory(identifier: "sample-category") { result in
    if case .failure(let error) = result {
        print("Error \(error.errorCode): \(error.errorMessage)")
    }
}
```

#### Action Received Callbacks

```swift
// Receive action button taps
MacNotificationManager.shared.setActionReceivedHandler { notificationId, actionId, userInfoJson in
    print("notification: \(notificationId), action: \(actionId)")
}

// Receive text input action submissions
MacNotificationManager.shared.setTextInputActionReceivedHandler { notificationId, actionId, userText, userInfoJson in
    print("notification: \(notificationId), action: \(actionId), text: \(userText)")
}
```

### Badge

```swift
// Set badge count
MacNotificationManager.shared.setBadgeCount(1) { result in
    switch result {
    case .success:
        print("Badge set to 1")
    case .failure(let error):
        print("Error \(error.errorCode): \(error.errorMessage)")
    }
}

// Clear badge
MacNotificationManager.shared.setBadgeCount(0) { result in
    switch result {
    case .success:
        print("Badge cleared")
    case .failure(let error):
        print("Error \(error.errorCode): \(error.errorMessage)")
    }
}
```

![Badge](images/mac/notification/Example_MacNotificationManager_Badge.png)

> Note: Screenshots must be added manually.

### Error Codes

| Code | Case | Description |
|---|---|---|
| 1001 | `unsupportedOS` | macOS 15+ required |
| 1002 | `permissionDenied` | User denied notification permission |
| 1003 | `permissionRequestFailed` | Failed to request permission |
| 1101 | `invalidContent` | Invalid id, title, or body |
| 1102 | `invalidTrigger` | Invalid trigger (e.g. `timeInterval` < 1 second) |
| 1103 | `invalidCategory` | Invalid category |
| 1104 | `notificationNotFound` | No pending notification for the given identifier |
| 1201 | `addFailed` | Failed to add notification request |
| 1202 | `removeFailed` | Failed to remove notification |
| 1203 | `queryFailed` | Failed to query notifications |
| 1204 | `setBadgeFailed` | Failed to set badge count |
| 1205 | `openSettingsFailed` | Failed to open notification settings |
| 1999 | `unknown` | Unknown error |
